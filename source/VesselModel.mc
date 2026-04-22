/*
 * VesselModel.mc
 * Single source of truth for SignalK state: auth state machine, persisted
 * device-access-request identifiers, cached vessel data, and the HTTP polling
 * loop. One instance lives at `VesselConnectApp.vessel` and is read by every
 * view. Network callbacks update fields in place and call
 * WatchUi.requestUpdate() so views redraw automatically.
 *
 * Auth flow (device access request — no username/password):
 *   1. First launch generates a v4 UUID `clientId` and persists it.
 *   2. POST /signalk/v1/access/requests {clientId, description}.
 *      Server responds 202 with a polling URL ("href") — persisted.
 *   3. Poll GET <href> every 3s until state == COMPLETED.
 *   4. APPROVED returns a JWT → stored as "Bearer <token>" and used for all
 *      subsequent data calls. DENIED is terminal (clientId is burned
 *      server-side; user must reset to request again).
 */

using Toybox.System;
using Toybox.Application;
using Toybox.Timer;
using Toybox.Communications;
using Toybox.Attention;
using Toybox.Cryptography;
using Toybox.Lang;
using Toybox.WatchUi;

using Toybox.Application.Storage;

using Utilities as Utils;

/*
 * Autopilot modes — used as menu-item IDs and as the "value" sent to the
 * raymarine-autopilot plugin. Values are stable; do not renumber.
 */
enum {
   AP_STATE_STANDBY = 0,
   AP_STATE_AUTO = 1,
   AP_STATE_WIND = 2,
   AP_STATE_TRACK = 3,
   AP_STATE_NOT_SUPPORTED = 4,
}

/*
 * Auth / config state machine. Transitions:
 *   NO_URL        -> NEEDS_REQUEST (user sets baseurl_prop in Garmin Connect)
 *   NEEDS_REQUEST -> PENDING       (user taps the request button)
 *   PENDING       -> CONNECTED     (poll returns COMPLETED/APPROVED)
 *   PENDING       -> DENIED        (poll returns COMPLETED/DENIED)
 *   CONNECTED     -> NEEDS_REQUEST (401 from data endpoint — token revoked)
 *   DENIED        -> NEEDS_REQUEST (user taps Reset — fresh clientId)
 *   any           -> NO_URL        (user clears baseurl_prop)
 */
enum {
   AUTH_NO_URL = -1,
   AUTH_NEEDS_REQUEST = 0,
   AUTH_PENDING = 1,
   AUTH_CONNECTED = 2,
   AUTH_DENIED = 3,
   AUTH_ERROR = 4,
}

class VesselModel {

    /*
     * Main data-poll interval (ms). Lower values feel more live but hammer
     * the server and drain battery.
     */
    const updateInterval = 1000;
    /*
     * Access-request poll interval (ms). Much slower — admin has to click a
     * button in the UI, no point hammering the server.
     */
    const pendingPollInterval = 3000;
    // Retry interval after transient network errors on the data poll (ms).
    const retryInterval = 3000;
    /*
     * Write a glance snapshot every N data-ticks (≈ 5 s wall-clock regardless
     * of updateInterval). Cuts flash wear vs writing every tick.
     */
    const glanceSnapshotEveryNTicks = 5000 / updateInterval;

    protected var baseURL = null;
    protected var token = null;               // "Bearer <JWT>" when authorised
    protected var clientId = null;            // v4 UUID, stable across launches
    protected var accessRequestHref = null;   // e.g. "/signalk/v1/requests/<id>"
/*
asdasdasd
*/
    protected var updateTimer;
    protected var retryTimer;
    protected var pollTimer;
    /*
     * Fires if the initial access-request POST doesn't respond within
     * accessRequestTimeoutMs. Without this CIQ happily waits 30+ s on a
     * dead/unreachable server.
     */
    protected var requestTimeoutTimer;
    /*
     * Drives the "Requesting..." spinner animation in AuthConfigView by
     * nudging WatchUi.requestUpdate every few hundred ms while the POST
     * is in flight.
     */
    protected var spinnerTimer;
    /*
     * One-shot timer that flips spinnerVisible after spinnerShowAfterMs
     * if the request hasn't already completed. Gates the spinner so fast
     * responses don't cause a flash of the loading screen.
     */
    protected var spinnerDelayTimer;
    // Timeout for the initial access-request POST (ms).
    const accessRequestTimeoutMs = 3000;
    // How often the spinner animation advances (ms).
    const spinnerTickMs = 150;
    /*
     * Only show the spinner if the request is still in flight this many
     * ms after being sent. Prevents the spinner from flashing on and off
     * for requests that come back faster than the user can perceive.
     */
    const spinnerShowAfterMs = 250;

    /*
     * True while requestAccess() is waiting for a response. Used to block
     * duplicate taps. Exposed via getter.
     */
    private var accessRequestInFlight = false;
    /*
     * True once the spinner-delay timer has elapsed AND the request is
     * still in flight. Views use this (not accessRequestInFlight) to
     * decide whether to draw the loading overlay.
     */
    private var spinnerVisible = false;

    // Live vessel data (populated by onReceive). Units noted per field.
    public var speedOverGround;              // meter/second
    public var apparentWindSpeed;            // meter/second
    public var trueWindSpeed;                // meter/second
    public var depthBelowTranscuder;         // meter
    public var tripTotal;                    // meter
    public var apparentWindAngle;            // radians
    public var courseOverGround;             // radians
    public var headingMagnetic;              // radians
    public var rudderAngle;                  // radians
    public var waterTemperature;             // kelvin

    public var targetHeadingTrue;            // radians
    public var targetHeadingMagnetic;        // radians
    public var targetHeadingWindAppearant;   // radians

    public var autopilotState = "---";

    private var isAutopilotRequestPending = false;

    /*
     * Counter used to throttle Storage writes for the glance snapshot.
     * Threshold is derived from `updateInterval` so cadence stays at ~5 s
     * regardless of how fast the data poll runs.
     */
    private var glanceSnapshotCounter = 0;

    /*
     * Previous auth state — used by onPollAccessReceive to skip redundant
     * WatchUi.requestUpdate calls when polling PENDING over and over.
     */
    private var lastAuthStateObserved = -1;

    /*
     * Tracks whether ErrorView is currently on top of the view stack so we
     * don't push duplicates. Cleared when the user dismisses manually or a
     * later successful request pops the view.
     */
    private var errorViewVisible = false;

    /*
     * Current auth state — one of the AUTH_* enum values. Views branch on
     * this to decide what to render / which view is active.
     */
    public var authState = AUTH_NEEDS_REQUEST;
    /*
     * Last network error code (set by showNetworkError, cleared on success).
     * Rendered by views via Utilities.errorMessage().
     */
    public var errorCode = null;

    function initialize() {
        configureSignalK();
    }

    /*
     * Reads persisted config (base URL, stored token, clientId, href) and
     * computes the initial auth state. Called on app start and whenever
     * settings change.
     */
    function configureSignalK() {

        /*
         * Read the user-configured base URL from Application.Properties
         * (edited in the Garmin Connect mobile app or the CIQ simulator's
         * Settings panel). No default: SignalK servers live on local boat
         * networks (Raspberry Pi on a yacht LAN, etc.), so a hardcoded
         * localhost default would be misleading for real users.
         */
        var configured = Application.Properties.getValue("baseurl_prop");
        if (configured == null || !(configured instanceof Lang.String) || configured.length() == 0) {
            baseURL = null;
        } else {
            /*
             * Trim any accidental trailing slash so URL composition below
             * (baseURL + "/signalk/...") stays canonical.
             */
            if (configured.substring(configured.length() - 1, configured.length()).equals("/")) {
                configured = configured.substring(0, configured.length() - 1);
            }
            baseURL = configured;
        }
        logDebug("Base URL: " + baseURL);

        token = Storage.getValue(StorageKeys.TOKEN);
        clientId = Storage.getValue(StorageKeys.CLIENT_ID);
        accessRequestHref = Storage.getValue(StorageKeys.ACCESS_HREF);

        // Derive initial auth state.
        if (baseURL == null) {
            /*
             * Nothing we can do until the user configures a server URL.
             * Persisted token / href stay intact so that once a URL is
             * entered, the user resumes where they left off (assuming it's
             * the same server — otherwise the first HTTP call will 401
             * and the normal flow bounces back to NEEDS_REQUEST).
             */
            authState = AUTH_NO_URL;
        } else if (token != null) {
            authState = AUTH_CONNECTED;
        } else if (accessRequestHref != null) {
            /*
             * Restart mid-pending: we submitted a request last session but
             * never got approved. Resume polling the same href.
             */
            authState = AUTH_PENDING;
        } else {
            authState = AUTH_NEEDS_REQUEST;
        }

        resetVesselData();
    }

    /*
     * Called on app start and from onSettingsChanged. Routes to the right
     * flow based on the current auth state.
     */
    function startUpdatingData() as Void {

        logDebug("startUpdatingData, authState=" + authState);

        if (authState == AUTH_NO_URL) {
            /*
             * No server URL configured — nothing to do until the user
             * sets baseurl_prop in Garmin Connect / sim settings.
             */
            return;
        }
        if (authState == AUTH_CONNECTED && token != null) {
            updateVesselDataFromServer();
        } else if (authState == AUTH_PENDING && accessRequestHref != null) {
            pollAccessRequest();
        }
        /*
         * NEEDS_REQUEST / DENIED: nothing to do here — the user has to act
         * via AuthConfigView first.
         */
    }

    function stopUpdatingData() {
        logDebug("stopUpdatingData");
        Communications.cancelAllRequests();
        updateTimer = invalidateTimer(updateTimer);
        retryTimer = invalidateTimer(retryTimer);
        pollTimer = invalidateTimer(pollTimer);
        finishAccessRequest();
    }

    function resetVesselData() {
        speedOverGround = 0.0d;
        apparentWindSpeed = 0.0d;
        trueWindSpeed = 0.0d;
        depthBelowTranscuder = 0.0d;
        apparentWindAngle = 0.0d;
        courseOverGround = 0.0d;
        headingMagnetic = 0.0d;
        rudderAngle = 0.0d;
        targetHeadingTrue = 0.0d;
        targetHeadingMagnetic = 0.0d;
        targetHeadingWindAppearant = 0.0d;
        tripTotal = 0.0d;
        waterTemperature = 0.0d;
        autopilotState = "---";
    }

    function getSpeedOverGroundKnotsString() {
        return Utils.meterPerSecondToKnots(speedOverGround).format("%.1f");
    }

    function getApparentWindSpeedKnotsString() {
        return Utils.meterPerSecondToKnots(apparentWindSpeed).format("%.1f");
    }

    function getTrueWindSpeedKnotsString() {
        return Utils.meterPerSecondToKnots(trueWindSpeed).format("%.1f");
    }

    function getDepthBelowTranscuderMeterString() {
        if (depthBelowTranscuder > 500.0d) {
            return "---";
        }
        return depthBelowTranscuder.format("%.1f") + "m";
    }

    function getTripTotalString() {
        return Utils.metersToNauticalMiles(tripTotal).format("%.1f") + "nm";
    }

    function getWaterTemperatureString() {
        return Utils.kelvinToCelsius(waterTemperature).format("%.1f") + "°C";
    }

    function getAppearantWindAngleDegreeString() {
        return Utils.radiansToDegrees(apparentWindAngle).abs().format("%.0f") + "°";
    }

    function getCourseOverGroundDegreeString() {
        return Utils.radiansToDegrees(courseOverGround).abs().format("%.0f") + "°";
    }

    function getHeadingMagneticDegreeString() {
        return Utils.radiansToDegrees(headingMagnetic).abs().format("%.0f") + "°";
    }

    function getTargetHeadingTrueDegreeString() {
        return Utils.radiansToDegrees(targetHeadingTrue).abs().format("%.0f") + "°";
    }

    function getTargetHeadingMagneticDegreeString() {
        return Utils.radiansToDegrees(targetHeadingMagnetic).abs().format("%.0f") + "°";
    }

    function getTargetHeadingWindAppearantDegreeString() {
        return Utils.radiansToDegrees(targetHeadingWindAppearant).abs().format("%.0f") + "°";
    }

    /*
     * Autopilot state names are lower-case in SignalK but rendered upper-case
     * in the UI, with "route" reduced to "TRACK" so it fits on-screen.
     */
    function getNameForActiveState() {
        var stateName = autopilotState.toUpper();
        if (stateName.equals(ApStates.ROUTE.toUpper())) {
            stateName = "TRACK";
        }
        return stateName;
    }

    function setAutopilotState(state) {
        var command = { "action" => "setState", "value" => state };
        sendAutopilotCommand(command);
    }

    function changeHeading(change) {
        var command = { "action" => "changeHeading", "value" => change };
        sendAutopilotCommand(command);
    }

    /*
     * Stops a timer if it exists and returns null so the caller can assign
     * the result back to its own field. The earlier "timer = null" inside
     * this function did nothing — Monkey C passes refs by value, so the
     * caller's var stayed non-null and stale timers could leak.
     * Usage: `myTimer = invalidateTimer(myTimer);`
     */
    function invalidateTimer(timer) {
        if (timer != null) {
            timer.stop();
        }
        return null;
    }

    /*
     * //////////////////////////////////////////////////////
     * //////////////// ACCESS REQUEST //////////////////////
     * //////////////////////////////////////////////////////
     */

    /*
     * Ensures we have a stable clientId — generates a v4 UUID on first call
     * and persists it. Same clientId is reused across launches and across
     * re-requests against the same SignalK server.
     */
    function getOrCreateClientId() as Lang.String {
        if (clientId != null) {
            return clientId;
        }
        clientId = generateUuidV4();
        Storage.setValue(StorageKeys.CLIENT_ID, clientId);
        logDebug("Generated new clientId: " + clientId);
        return clientId;
    }

    /*
     * Accessor for baseURL so views can render the configured server in
     * their UI copy (e.g. AuthConfigView's "tap to request from <url>").
     */
    function getBaseURL() {
        return baseURL;
    }

    /*
     * True while requestAccess is waiting for a response. Used internally
     * and (historically) externally to block duplicate taps.
     */
    function isAccessRequestInFlight() as Lang.Boolean {
        return accessRequestInFlight;
    }

    /*
     * True once the request has been in flight longer than
     * spinnerShowAfterMs. Views should use this to draw the loading
     * overlay so fast responses don't cause a flash.
     */
    function isSpinnerVisible() as Lang.Boolean {
        return spinnerVisible;
    }

    /*
     * Human-readable label shown to the admin in the SignalK approval UI.
     * Uses the device's part number so admins can tell multiple Garmins
     * apart.
     */
    function getDeviceDescription() as Lang.String {
        var settings = System.getDeviceSettings();
        var partNumber = null;
        if (settings != null && settings has :partNumber) {
            partNumber = settings.partNumber;
        }
        if (partNumber == null) {
            return "Garmin Watch";
        }
        return "Garmin " + partNumber;
    }

    /*
     * First-time access request. Posts the clientId + description. On 202
     * the server returns a polling href which we persist and then poll every
     * `pendingPollInterval` ms until approved/denied.
     *
     * Does NOT flip authState here — that happens only when the 202 callback
     * confirms the server accepted the request. Otherwise a failed POST
     * would leave us in a bogus PENDING state with no actual pending request
     * on the server.
     *
     * Duplicate-tap guarded via accessRequestInFlight. Bounded with a
     * requestTimeoutTimer so an unreachable server doesn't hang the UX for
     * the full CIQ default (~30 s).
     */
    function requestAccess() {

        if (accessRequestInFlight) {
            System.println("[Auth] requestAccess ignored — another in flight");
            return;
        }

        if (baseURL == null) {
            System.println("[Auth] requestAccess ignored — no URL configured");
            return;
        }

        // Make sure we have a clientId before submitting.
        getOrCreateClientId();

        accessRequestInFlight = true;
        startRequestTimeoutTimer();
        /*
         * Don't start the spinner yet — wait spinnerShowAfterMs to see if
         * the response arrives first. Also intentionally no
         * requestUpdate() here: if the request is fast, nothing visible
         * should change.
         */
        startSpinnerDelayTimer();

        var body = {
            "clientId" => clientId,
            "description" => getDeviceDescription()
        };

        var url = baseURL + "/signalk/v1/access/requests";
        System.println("[Auth] POST " + url);
        System.println("[Auth]   clientId=" + clientId);
        System.println("[Auth]   description=" + getDeviceDescription());

        Communications.makeWebRequest(
            url,
            body,
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onRequestAccessReceive)
        );
    }

    function startRequestTimeoutTimer() as Void {
        requestTimeoutTimer = invalidateTimer(requestTimeoutTimer);
        requestTimeoutTimer = new Timer.Timer();
        requestTimeoutTimer.start(method(:onRequestAccessTimeout), accessRequestTimeoutMs, false);
    }

    function startSpinnerDelayTimer() as Void {
        spinnerDelayTimer = invalidateTimer(spinnerDelayTimer);
        spinnerDelayTimer = new Timer.Timer();
        spinnerDelayTimer.start(method(:onSpinnerDelayElapsed), spinnerShowAfterMs, false);
    }

    /*
     * Fires spinnerShowAfterMs after the request was sent. If the request
     * already completed, this is a no-op. Otherwise we flip spinnerVisible
     * and kick off the animation timer.
     */
    function onSpinnerDelayElapsed() as Void {
        if (!accessRequestInFlight) {
            return;
        }
        spinnerVisible = true;
        startSpinnerTimer();
        WatchUi.requestUpdate();
    }

    function startSpinnerTimer() as Void {
        spinnerTimer = invalidateTimer(spinnerTimer);
        spinnerTimer = new Timer.Timer();
        spinnerTimer.start(method(:onSpinnerTick), spinnerTickMs, true);
    }

    /*
     * Periodic spinner nudge — only triggers a view redraw so the
     * spinner's rotation advances.
     */
    function onSpinnerTick() as Void {
        if (accessRequestInFlight) {
            WatchUi.requestUpdate();
        } else {
            spinnerTimer = invalidateTimer(spinnerTimer);
        }
    }

    /*
     * Fired when the access-request POST hasn't responded within
     * accessRequestTimeoutMs. Cancels the in-flight request (so a late
     * response can't fire the callback) and surfaces a timeout error.
     */
    function onRequestAccessTimeout() as Void {
        if (!accessRequestInFlight) {
            return;
        }
        System.println("[Auth] requestAccess timed out after " + accessRequestTimeoutMs + "ms");
        Communications.cancelAllRequests();
        finishAccessRequest();
        authState = AUTH_NEEDS_REQUEST;
        showNetworkError(-300); // NETWORK_REQUEST_TIMED_OUT
    }

    /*
     * Common cleanup path for the end of a request attempt (success,
     * error, or timeout). Stops all related timers and clears flags.
     */
    function finishAccessRequest() as Void {
        accessRequestInFlight = false;
        spinnerVisible = false;
        requestTimeoutTimer = invalidateTimer(requestTimeoutTimer);
        spinnerTimer = invalidateTimer(spinnerTimer);
        spinnerDelayTimer = invalidateTimer(spinnerDelayTimer);
    }

    function onRequestAccessReceive(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {

        /*
         * If the timeout fired first, we already cleaned up and surfaced
         * a timeout error. Late responses after that are no-ops.
         */
        if (!accessRequestInFlight) {
            System.println("[Auth] onRequestAccessReceive late response ignored");
            return;
        }
        finishAccessRequest();

        System.println("[Auth] onRequestAccessReceive code=" + responseCode + " dataType=" + typeName(data));
        if (data instanceof Lang.Dictionary) {
            System.println("[Auth]   data=" + data);
        } else if (data instanceof Lang.String) {
            System.println("[Auth]   data(string)=" + data);
        }

        /*
         * SignalK server sends HTTP 202 on the initial accept. Some servers
         * / CIQ versions hand back 200 on the same shape — treat both as OK.
         */
        if ((responseCode == 202 || responseCode == 200) && data instanceof Lang.Dictionary) {
            accessRequestHref = data["href"];
            System.println("[Auth] href=" + accessRequestHref);
            if (accessRequestHref == null) {
                authState = AUTH_ERROR;
                showNetworkError(-400);
                return;
            }
            Storage.setValue(StorageKeys.ACCESS_HREF, accessRequestHref);
            enterPendingState();
            return;
        }

        if (responseCode == 400) {
            /*
             * "Already requested" — server still remembers us. If we have a
             * persisted href, just resume polling; otherwise the clientId is
             * burned and the user needs to reset.
             */
            if (accessRequestHref != null) {
                System.println("[Auth] 400 but we have href — resuming poll");
                enterPendingState();
                return;
            }
        }

        /*
         * Submit failed. Stay on NEEDS_REQUEST so the user is still on
         * AuthConfigView when they dismiss the ErrorView — they can tap the
         * button again to retry.
         */
        System.println("[Auth] submit failed, errorCode=" + responseCode);
        authState = AUTH_NEEDS_REQUEST;
        showNetworkError(responseCode);
    }

    /*
     * Transitions into PENDING state on a confirmed-accepted request:
     * flips state, clears any lingering error, starts polling, and asks
     * the (already-active) AuthConfigView to re-render with the new state.
     * Called only after the server acknowledges the submit (202 or a 400
     * resume-from-existing-href).
     */
    function enterPendingState() as Void {
        authState = AUTH_PENDING;
        errorCode = null;
        dismissErrorViewIfShown();
        schedulePoll();
        WatchUi.requestUpdate();
    }

    // GETs the polling href. Called on a timer while authState == PENDING.
    function pollAccessRequest() as Void {

        if (accessRequestHref == null) {
            System.println("[Auth] pollAccessRequest: no href, skipping");
            return;
        }

        var url = baseURL + accessRequestHref;
        System.println("[Auth] GET " + url);

        Communications.makeWebRequest(
            url,
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onPollAccessReceive)
        );
    }

    function onPollAccessReceive(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {

        System.println("[Auth] onPollAccessReceive code=" + responseCode + " dataType=" + typeName(data));
        if (data instanceof Lang.Dictionary) {
            System.println("[Auth]   poll data=" + data);
        } else if (data instanceof Lang.String) {
            /*
             * JSON parse failed but we got raw text — log it so we can see
             * what the server is returning on approval.
             */
            System.println("[Auth]   poll data(string)=" + data);
        }

        if (responseCode != 200) {
            System.println("[Auth] poll non-200, scheduling retry");
            schedulePoll();
            showNetworkError(responseCode);
            return;
        }

        /*
         * If the JSON parser didn't give us a Dictionary but we have a
         * String, try our own substring-based parse — some server responses
         * may include fields CIQ's JSON parser chokes on, and we still need
         * to extract state / token.
         */
        if (!(data instanceof Lang.Dictionary)) {
            if (data instanceof Lang.String) {
                handlePollStringResponse(data);
                return;
            }
            System.println("[Auth] poll 200 but data isn't Dictionary or String");
            schedulePoll();
            showNetworkError(-400);
            return;
        }

        var state = data["state"];
        System.println("[Auth]   state=" + state);

        if (state != null && state.equals("PENDING")) {
            /*
             * Skip requestUpdate when nothing has changed from the last
             * poll — avoids waking the UI every 3 s while we wait.
             */
            if (errorCode != null || lastAuthStateObserved != AUTH_PENDING) {
                errorCode = null;
                lastAuthStateObserved = AUTH_PENDING;
                dismissErrorViewIfShown();
                WatchUi.requestUpdate();
            }
            schedulePoll();
            return;
        }

        if (state != null && state.equals("COMPLETED")) {
            var accessRequest = data["accessRequest"];
            System.println("[Auth]   accessRequest=" + accessRequest);
            var permission = null;
            var jwt = null;
            if (accessRequest instanceof Lang.Dictionary) {
                permission = accessRequest["permission"];
                jwt = accessRequest["token"];
            }
            System.println("[Auth]   permission=" + permission + " tokenPresent=" + (jwt != null));

            if (permission != null && permission.equals("APPROVED") && jwt != null) {
                finalizeApproval(jwt);
                return;
            }

            if (permission != null && permission.equals("DENIED")) {
                finalizeDenial();
                return;
            }
        }

        System.println("[Auth] poll: unknown state, scheduling retry");
        schedulePoll();
    }

    /*
     * Fallback parser for when CIQ's JSON parser hands us a string. Looks
     * for "APPROVED" / "DENIED" / "PENDING" substrings and extracts the
     * token field by string slicing. Ugly but resilient to parser quirks.
     */
    function handlePollStringResponse(body as Lang.String) as Void {
        System.println("[Auth] handlePollStringResponse, len=" + body.length());

        if (body.find("\"state\":\"PENDING\"") != null) {
            System.println("[Auth]   (string) state=PENDING");
            errorCode = null;
            WatchUi.requestUpdate();
            schedulePoll();
            return;
        }

        if (body.find("\"permission\":\"DENIED\"") != null) {
            System.println("[Auth]   (string) DENIED");
            finalizeDenial();
            return;
        }

        if (body.find("\"permission\":\"APPROVED\"") != null) {
            var tokenTag = "\"token\":\"";
            var start = body.find(tokenTag);
            if (start != null) {
                var valueStart = start + tokenTag.length();
                var valueEnd = body.substring(valueStart, body.length()).find("\"");
                if (valueEnd != null) {
                    var jwt = body.substring(valueStart, valueStart + valueEnd);
                    System.println("[Auth]   (string) APPROVED, jwt len=" + jwt.length());
                    finalizeApproval(jwt);
                    return;
                }
            }
            System.println("[Auth]   APPROVED found but couldn't extract token");
        }

        System.println("[Auth] (string) no known state — retrying");
        schedulePoll();
    }

    function finalizeApproval(jwt as Lang.String) as Void {
        pollTimer = invalidateTimer(pollTimer);
        token = "Bearer " + jwt;
        Storage.setValue(StorageKeys.TOKEN, token);
        Storage.deleteValue(StorageKeys.ACCESS_HREF);
        accessRequestHref = null;
        authState = AUTH_CONNECTED;
        errorCode = null;
        System.println("[Auth] ** APPROVED ** — token stored; waiting for user ack");
        /*
         * Stay on AuthConfigView. It re-renders as "Granted — tap to
         * continue"; the user's next tap starts data polling and switches
         * to VesselDataView (see AuthConfigViewDelegate.onSelect).
         */
        WatchUi.requestUpdate();
    }

    function finalizeDenial() as Void {
        pollTimer = invalidateTimer(pollTimer);
        Storage.deleteValue(StorageKeys.ACCESS_HREF);
        accessRequestHref = null;
        authState = AUTH_DENIED;
        errorCode = null;
        System.println("[Auth] ** DENIED ** — user must reset to try again");
        // Same AuthConfigView — re-render with DENIED content.
        WatchUi.requestUpdate();
    }

    /*
     * Small helper for verbose logging — returns a readable type name for
     * whatever CIQ handed to the callback.
     */
    function typeName(v) as Lang.String {
        if (v == null) { return "Null"; }
        if (v instanceof Lang.Dictionary) { return "Dictionary"; }
        if (v instanceof Lang.String) { return "String"; }
        if (v instanceof Lang.Array) { return "Array"; }
        if (v instanceof Lang.Number) { return "Number"; }
        return "Other";
    }

    /*
     * Drops clientId, href, token locally and generates a fresh clientId so
     * the user can submit a new request. Called from AuthConfigView (reset
     * menu while pending; implicit reset on tap from denied state).
     * Note: this does NOT cancel the old request on the server — there's no
     * client-side cancel endpoint in SignalK (verified against 2.x server
     * source). An orphaned PENDING request sits on the server until admin
     * denies it.
     */
    function resetAccessRequest() {

        logDebug("resetAccessRequest");

        stopUpdatingData();

        Storage.deleteValue(StorageKeys.TOKEN);
        Storage.deleteValue(StorageKeys.CLIENT_ID);
        Storage.deleteValue(StorageKeys.ACCESS_HREF);
        Storage.deleteValue(StorageKeys.GLANCE_SNAPSHOT);

        token = null;
        clientId = null;
        accessRequestHref = null;

        authState = AUTH_NEEDS_REQUEST;
        errorCode = null;
    }

    function schedulePoll() {
        pollTimer = invalidateTimer(pollTimer);
        pollTimer = new Timer.Timer();
        pollTimer.start(method(:pollAccessRequest), pendingPollInterval, false);
    }

    /*
     * //////////////////////////////////////////////////////
     * /////////////////// NETWORKING ///////////////////////
     * //////////////////////////////////////////////////////
     */

    /*
     * Fetches the aggregated vessel data from the minimumvesseldatarest
     * plugin. Re-scheduled on each successful response at `updateInterval`
     * cadence while authState == CONNECTED.
     */
    function updateVesselDataFromServer() as Void {

        updateTimer = invalidateTimer(updateTimer);

        /*
         * Endpoint is under /signalk/v1/api/ (not /plugins/) so readwrite
         * tokens work — /plugins/* is hardcoded admin-only by signalk-server.
         */
        Communications.makeWebRequest(
            baseURL + "/signalk/v1/api/minimumvesseldatarest/vesseldata",
            {},
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED,
                    "Authorization" => token
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onReceive)
        );
    }

    function onReceive(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {

        /*
         * -1003 is REQUEST_CANCELLED (e.g. when we stopped polling before
         * the response came back). Treat as no-op.
         */
        if (responseCode == -1003) {
            return;
        }

        if (responseCode == 200 && data instanceof Lang.Dictionary) {

            try {
                depthBelowTranscuder = setValueIfPresent(data["depthBelowTransducer"]);
                apparentWindSpeed = setValueIfPresent(data["windSpeedApparent"]);
                waterTemperature = setValueIfPresent(data["waterTemperature"]);
                speedOverGround = setValueIfPresent(data["speedOverGround"]);
                courseOverGround = setValueIfPresent(data["courseOverGroundTrue"]);
                apparentWindAngle = setValueIfPresent(data["windAngleApparent"]);
                rudderAngle = setValueIfPresent(data["rudderAngle"]);
                headingMagnetic = setValueIfPresent(data["headingMagnetic"]);
                targetHeadingMagnetic = setValueIfPresent(data["autopilotTargetHeadingMagnetic"]);
                targetHeadingTrue = setValueIfPresent(data["autopilotTargetHeadingTrue"]);
                targetHeadingWindAppearant = setValueIfPresent(data["autopilotTargetWindAngleApparent"]);
                tripTotal = setValueIfPresent(data["tripTotal"]);

                if (data["autopilotState"] != null) {
                    autopilotState = data["autopilotState"];
                } else {
                    autopilotState = "---";
                }
            } catch (ex) {
                ex.printStackTrace();
                resetVesselData();
            }

            errorCode = null;

            /*
             * Recovery: if ErrorView is still showing from a previous
             * failure, pop it now that data is flowing again.
             */
            dismissErrorViewIfShown();

            /*
             * Throttled: write a glance snapshot every ~5 seconds so the
             * glance tile can show last-known SOG/AWS/AP without running
             * its own network poll.
             */
            glanceSnapshotCounter++;
            if (glanceSnapshotCounter >= glanceSnapshotEveryNTicks) {
                glanceSnapshotCounter = 0;
                persistGlanceSnapshot();
            }

            WatchUi.requestUpdate();

            updateTimer = new Timer.Timer();
            updateTimer.start(method(:updateVesselDataFromServer), updateInterval, false);
            return;
        }

        logDebug("Data response code: " + responseCode);

        /*
         * 401 (explicit unauthorized) or -400 (body couldn't be parsed as
         * JSON — SignalK returns plain text "Unauthorized" on auth failure,
         * which CIQ surfaces as -400 instead of passing 401 through). Both
         * mean the token is dead server-side (admin deleted the access
         * request, token expired, etc). Reset to NEEDS_REQUEST so the
         * user can re-register, same as a fresh install.
         */
        if (responseCode == 401 || responseCode == -400 || responseCode == 403) {
            logDebug("Token rejected (code=" + responseCode + "). Clearing and bouncing to AuthConfigView.");
            resetAccessRequest();
            WatchUi.switchToView(new AuthConfigView(), new AuthConfigViewDelegate(), WatchUi.SLIDE_RIGHT);
            return;
        }

        // Other failures: show the error, retry after a delay.
        resetVesselData();
        showNetworkError(responseCode);
        startRetryTimer();
    }

    /*
     * POSTs an autopilot command to the raymarine-autopilot plugin. Gated by
     * a simple in-flight flag so rapid key taps don't queue up commands.
     */
    function sendAutopilotCommand(command) {

        if (isAutopilotRequestPending == true) {
            return;
        }

        isAutopilotRequestPending = true;

        /*
         * Endpoint is under /signalk/v1/api/ (not /plugins/) so readwrite
         * tokens work — /plugins/* is hardcoded admin-only by signalk-server.
         */
        Communications.makeWebRequest(
            baseURL + "/signalk/v1/api/raymarineautopilotfork/command",
            command,
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Accept" => "application/json",
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => token
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onAutopilotReceive)
        );
    }

    function onAutopilotReceive(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {

        if (responseCode == 200) {
            Attention.playTone(Attention.TONE_KEY);
        } else {
            if (Attention has :vibrate) {
                var vibeData = [ new Attention.VibeProfile(50, 100) ];
                Attention.vibrate(vibeData);
            }
        }

        isAutopilotRequestPending = false;
    }

    function setValueIfPresent(value) {
        if (value != null) {
            return value;
        }
        return 0.0;
    }

    /*
     * Writes last-known data values to Storage keys that SignalKGlanceView
     * reads on its next render. Called from onReceive at ~5 s cadence.
     * Combining the three values into one Storage entry cuts flash writes
     * 3x vs setValue-per-field (this function runs every ~5 s).
     */
    function persistGlanceSnapshot() {
        Storage.setValue(StorageKeys.GLANCE_SNAPSHOT, {
            "sog" => Utils.meterPerSecondToKnots(speedOverGround),
            "aws" => Utils.meterPerSecondToKnots(apparentWindSpeed),
            "ap"  => getNameForActiveState()
        });
    }

    /*
     * Sets errorCode and shows the full-screen ErrorView (if it isn't
     * already visible). Called from every callback that sees a recoverable
     * transient failure (not auth — auth failures call resetAccessRequest
     * and bounce to AuthConfigView instead).
     */
    function showNetworkError(responseCode) {
        errorCode = responseCode;
        if (!errorViewVisible) {
            errorViewVisible = true;
            WatchUi.pushView(new ErrorView(), new ErrorViewDelegate(), WatchUi.SLIDE_IMMEDIATE);
        } else {
            WatchUi.requestUpdate();
        }
    }

    /*
     * Called by ErrorViewDelegate when the user presses back. The view
     * itself pops; we just clear the flag so the next error (or a
     * recurrence of this one) can push again.
     */
    function dismissErrorView() as Void {
        errorViewVisible = false;
    }

    /*
     * Called from successful callbacks to clear a lingering error state.
     * Pops the ErrorView if it's currently on top of the stack.
     */
    function dismissErrorViewIfShown() as Void {
        if (errorViewVisible) {
            errorViewVisible = false;
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
    }

    function startRetryTimer() {
        logDebug("Network error. Retry in " + retryInterval / 1000 + "s");
        retryTimer = invalidateTimer(retryTimer);
        retryTimer = new Timer.Timer();
        retryTimer.start(method(:startUpdatingData), retryInterval, false);
    }

    /*
     * //////////////////////////////////////////////////////
     * ////////////////// UUID v4 HELPER ////////////////////
     * //////////////////////////////////////////////////////
     */

    /*
     * Generates a RFC 4122 version-4 UUID as a lowercase hex string with
     * dashes, e.g. "550e8400-e29b-41d4-a716-446655440000". Uses the CIQ
     * cryptographic RNG for the 16 random bytes.
     */
    function generateUuidV4() as Lang.String {
        var bytes = Cryptography.randomBytes(16);

        // Force the version and variant bits per RFC 4122 §4.4.
        bytes[6] = (bytes[6] & 0x0F) | 0x40;  // version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80;  // variant 10xxxxxx

        var hex = "0123456789abcdef";
        var out = "";
        for (var i = 0; i < 16; i++) {
            if (i == 4 || i == 6 || i == 8 || i == 10) {
                out += "-";
            }
            var b = bytes[i] & 0xFF;
            out += hex.substring((b >> 4) & 0x0F, ((b >> 4) & 0x0F) + 1);
            out += hex.substring(b & 0x0F, (b & 0x0F) + 1);
        }
        return out;
    }

    /*
     * //////////////////////////////////////////////////////
     * /////////////////// LOGGING //////////////////////////
     * //////////////////////////////////////////////////////
     */

    /*
     * Single-place wrapper around System.println so the debug output can
     * later be gated behind a build-type annotation without touching call
     * sites. For now this always prints; the sim swallows output and on
     * a real device it just goes to the log nothing reads.
     */
    function logDebug(msg) {
        System.println(msg);
    }
}
