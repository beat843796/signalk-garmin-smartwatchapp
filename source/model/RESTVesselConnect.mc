/*
 * RESTVesselConnect.mc
 * REST-over-HTTP implementation of VesselConnect. Owns the SignalK
 * device-access-request flow, the vessel-data poll, the autopilot
 * command PUT, and the /signalk discovery probe.
 *
 * Auth flow (device access request — no username/password):
 *   1. First launch generates a v4 UUID `clientId` and persists it.
 *   2. POST /signalk/v1/access/requests {clientId, description}.
 *      Server responds 202 with a polling URL ("href") — persisted.
 *   3. Poll GET <href> every 3s until state == COMPLETED.
 *   4. APPROVED returns a JWT → stored as "Bearer <token>" and used
 *      as the Authorization header on all subsequent data calls.
 *      DENIED is terminal (clientId burned server-side; user must
 *      reset to request again).
 *
 * Why TEXT_PLAIN instead of HTTP_RESPONSE_CONTENT_TYPE_JSON: CIQ's
 * auto-parse swallows the real HTTP status code on parse failure
 * (replaces with -400). signalk-server returns plain-text error bodies
 * for 401/404 etc., so auto-parse hid auth failures behind "missing
 * plugin". With TEXT_PLAIN we always get the real status code; we run
 * Json.parse manually on 200 responses.
 */

using Toybox.System;
using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Timer;
using Toybox.Communications;
using Toybox.Attention;
using Toybox.Lang;
using Toybox.WatchUi;

using Utilities as Utils;

class RESTVesselConnect extends VesselConnect {

    /*
     * Main data-poll interval (ms). 3 polls per second — feels live on
     * the dashboards. Higher cadence than this hammers the server and
     * drains battery; the user knowingly traded battery for liveness
     * here.
     */
    const updateInterval = 333;

    /*
     * Access-request poll interval (ms). Much slower — admin has to
     * click a button in the SignalK admin UI, no point hammering.
     */
    const pendingPollInterval = 3000;

    // Retry interval after transient errors on the data poll (ms).
    const retryInterval = 5000;

    /*
     * Write a glance snapshot every N data-ticks (≈ 5 s wall-clock
     * regardless of updateInterval). Cuts flash wear vs every tick.
     */
    const glanceSnapshotEveryNTicks = 5000 / updateInterval;

    /*
     * Hard ceiling on the access-request POST. Without this CIQ would
     * happily wait 30+ s on a dead/unreachable server before reporting
     * timeout, and the UX would be unusable.
     */
    const accessRequestTimeoutMs = 3000;

    // Spinner cosmetics — stagger so fast responses never flash one.
    const spinnerTickMs = 150;
    const spinnerShowAfterMs = 250;

    protected var baseURL = null;
    protected var token = null;             // "Bearer <JWT>" when authorised
    protected var clientId = null;          // v4 UUID, stable across launches
    protected var accessRequestHref = null; // e.g. "/signalk/v1/requests/<id>"

    /*
     * Most recent HTTP / CIQ code observed from any request to the
     * underlying server. null = nothing observed yet. Drives the unified
     * status mapping in getStatusKind().
     */
    public var lastNetCode = null;

    /*
     * Most recent /signalk discovery probe outcome. Only consulted by
     * deriveConnectivity on ambiguous codes (404/400). null = haven't
     * probed yet (or last data poll succeeded — see onDataReceive).
     */
    public var probeOk = null;

    protected var updateTimer;
    protected var retryTimer;
    protected var pollTimer;
    protected var requestTimeoutTimer;
    protected var spinnerTimer;
    protected var spinnerDelayTimer;

    private var accessRequestInFlight = false;
    private var spinnerVisible = false;
    private var isAutopilotRequestPending = false;

    private var lastAuthStateObserved = -1;

    /*
     * Throttling state for the recurring data-poll log. The poll fires
     * 3×/s; logging every iteration drowns the [Data] log. We heartbeat
     * once per ~5 s while everything is fine, AND log every non-200 /
     * state transition unconditionally so failures stand out.
     *
     * `dataPollLastLogAt` is a millisecond System.getTimer() value;
     * 0 = "haven't logged yet" (forces the next request/response to log
     * unconditionally — matches the BleService read-loop pattern).
     */
    private var dataPollLastLogAt = 0;
    private const dataPollLogIntervalMs = 5000;

    /*
     * Tracks whether the previous data poll succeeded. Used to detect
     * transitions:
     *   OK → fail  → redirect ViewLoop to StatusView page (once)
     *   fail → OK  → redirect ViewLoop to VesselData page (once)
     * Re-direct on every poll would constantly destroy the user's
     * loop position, so we only fire on transitions.
     *
     * Initial value `true` matches the optimistic stance taken in
     * deriveConnectivity (no poll yet + has token = CONN_CONNECTED).
     * If the first poll fails, that's an OK→fail transition and the
     * status redirect fires correctly.
     */
    private var lastDataPollOk = true;

    /*
     * Set true while a one-shot poll triggered by refresh() is in
     * flight (e.g. on AutopilotView.onShow). Suppresses the page-
     * redirect side effects of onDataReceive so a refresh on a
     * specific view doesn't yank the user away from it. Does NOT
     * suppress rescheduling — the recurring poll should keep going
     * regardless of one-shot probes.
     */
    private var oneShotInFlight = false;

    /*
     * Master switch on the recurring data poll. Cleared by
     * pausePolling() (StatusView.onShow); set by resumePolling()
     * (StatusView.onHide). While false, onDataReceive does NOT
     * reschedule the next poll, so the cadence decays to zero after
     * the in-flight response settles.
     */
    private var dataPollEnabled = true;

    /*
     * Auth state machine — REST-internal. Views surface user-facing
     * state via getStatusKind() / getStatusLabel() rather than
     * branching on AUTH_*; the only outside reader is RequestAccessView,
     * which is only ever pushed in REST mode.
     */
    public var authState = AUTH_NEEDS_REQUEST;

    function initialize(vesselRef) {
        VesselConnect.initialize(vesselRef);
        configureSignalK();
    }

    /*
     * Reads persisted config (base URL, stored token, clientId, href)
     * and computes the initial auth state. Called on construction and
     * whenever settings change.
     */
    function configureSignalK() {
        baseURL = Utils.normalizeBaseUrl(Application.Properties.getValue("baseurl_prop"));

        token = Storage.getValue(StorageKeys.TOKEN);
        clientId = Storage.getValue(StorageKeys.CLIENT_ID);
        accessRequestHref = Storage.getValue(StorageKeys.ACCESS_HREF);

        authState = Utils.deriveInitialAuthState(baseURL, token, accessRequestHref);
        Log.d("[REST] configureSignalK baseURL=" + baseURL
            + " hasToken=" + (token != null)
            + " hasHref=" + (accessRequestHref != null)
            + " authState=" + authState);
    }

    /*
     * ============== VesselConnect interface ==============
     */

    function start() as Void {
        Log.d("[REST] start authState=" + authState
            + " hasToken=" + (token != null)
            + " hasHref=" + (accessRequestHref != null));

        if (authState == AUTH_NO_URL) {
            Log.d("[REST] start skipped — no URL configured");
            return;
        }
        if (authState == AUTH_CONNECTED && token != null) {
            updateVesselDataFromServer();
        } else if (authState == AUTH_PENDING && accessRequestHref != null) {
            pollAccessRequest();
        }
    }

    function stop() as Void {
        Log.d("[REST] stop");
        Communications.cancelAllRequests();
        updateTimer = invalidateTimer(updateTimer);
        retryTimer = invalidateTimer(retryTimer);
        pollTimer = invalidateTimer(pollTimer);
        finishAccessRequestPost();
        endAuthFlow();
    }

    function setAutopilotState(state) as Void {
        Log.d("[AP] setAutopilotState '" + state + "' (REST)");
        sendAutopilotCommand({ "action" => "setState", "value" => state });
    }

    function changeHeading(degrees) as Void {
        Log.d("[AP] changeHeading " + degrees + "° (REST)");
        sendAutopilotCommand({ "action" => "changeHeading", "value" => degrees });
    }

    /*
     * ============== Unified status surface ==============
     */

    function getDisplayTitle() as Lang.String {
        return WatchUi.loadResource(Rez.Strings.TitleSignalKHttps) as Lang.String;
    }

    /*
     * Maps the REST-specific (auth state + last net code + probe) tuple
     * onto one of the unified CONN_* values. Logic lives in
     * Utilities.deriveConnectivity for unit-testability.
     */
    function getStatusKind() as Lang.Number {
        return Utils.deriveConnectivity(
            baseURL,
            token != null,
            accessRequestHref != null,
            lastNetCode,
            probeOk);
    }

    /*
     * Subtitle text for the StatusView. URL when CONNECTED (so the user
     * can verify the configured target); state name otherwise. Each
     * possible CONN_* maps to a stable string — colour is the view's
     * concern.
     */
    function getStatusLabel() as Lang.String {
        var kind = getStatusKind();
        if (kind == CONN_CONNECTED) {
            return baseURL != null
                ? baseURL
                : WatchUi.loadResource(Rez.Strings.StatusConnected) as Lang.String;
        }
        var id;
        if (kind == CONN_NO_URL)              { id = Rez.Strings.StatusNoUrl; }
        else if (kind == CONN_NO_HTTPS)       { id = Rez.Strings.StatusNoHttps; }
        else if (kind == CONN_NOT_REACHABLE)  { id = Rez.Strings.StatusNotReachable; }
        else if (kind == CONN_NOT_AUTH)       { id = Rez.Strings.StatusNotAuth; }
        else if (kind == CONN_PENDING)        { id = Rez.Strings.StatusPending; }
        else if (kind == CONN_MISSING_PLUGIN) { id = Rez.Strings.StatusPluginMissing; }
        else                                  { id = Rez.Strings.StatusUnknown; }
        return WatchUi.loadResource(id) as Lang.String;
    }

    function supportsRequestAccess() as Lang.Boolean {
        return true;
    }

    /*
     * One-shot poll for status refresh on view entry (StatusView /
     * AutopilotView). Skips when nothing to ask. Does NOT cancel or
     * disrupt the recurring poll.
     */
    function refresh() as Void {
        if (baseURL == null || token == null) {
            Log.d("[REST] refresh skipped — baseURL=" + baseURL
                + " hasToken=" + (token != null));
            return;
        }
        Log.d("[REST] refresh (one-shot poll)");
        oneShotInFlight = true;
        updateVesselDataFromServer();
    }

    /*
     * Pauses the recurring data poll. Used by StatusView so the user
     * isn't burning battery on data the screen doesn't render. Token
     * + auth state survive — only the next-tick scheduling stops.
     */
    function pausePolling() as Void {
        Log.d("[REST] pausePolling");
        dataPollEnabled = false;
        updateTimer = invalidateTimer(updateTimer);
        retryTimer = invalidateTimer(retryTimer);
    }

    /*
     * Re-enables the recurring poll and re-kicks it via start(), which
     * itself gates on authState/token — resuming when there's nothing
     * to poll is therefore a no-op.
     */
    function resumePolling() as Void {
        Log.d("[REST] resumePolling");
        dataPollEnabled = true;
        start();
    }

    /*
     * ============== REST-specific accessors ==============
     */

    function getBaseURL() {
        return baseURL;
    }

    function hasToken() as Lang.Boolean {
        return token != null;
    }

    function hasHref() as Lang.Boolean {
        return accessRequestHref != null;
    }

    function isSpinnerVisible() as Lang.Boolean {
        return spinnerVisible;
    }

    function isAccessRequestInFlight() as Lang.Boolean {
        return accessRequestInFlight;
    }

    /*
     * Human-readable label shown to the admin in the SignalK approval
     * UI. Uses the device's part number so admins can tell multiple
     * Garmins apart.
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
     * ============== Access request flow ==============
     */

    /*
     * First-time access request. Posts the clientId + description.
     * On 202 the server returns a polling href which we persist and
     * then poll every `pendingPollInterval` ms until approved/denied.
     *
     * Does NOT flip authState here — that happens only when the 202
     * callback confirms the server accepted the request. Otherwise a
     * failed POST would leave us in a bogus PENDING state with no
     * actual pending request on the server.
     *
     * Duplicate-tap guarded via accessRequestInFlight. Bounded with a
     * requestTimeoutTimer so an unreachable server doesn't hang the
     * UX for the full CIQ default (~30 s).
     */
    function requestAccess() {

        if (accessRequestInFlight) {
            Log.d("[Auth] requestAccess ignored — another in flight");
            return;
        }

        if (baseURL == null) {
            Log.d("[Auth] requestAccess ignored — no URL configured");
            return;
        }

        getOrCreateClientId();

        accessRequestInFlight = true;
        startRequestTimeoutTimer();
        startSpinnerDelayTimer();

        var body = {
            "clientId" => clientId,
            "description" => getDeviceDescription()
        };

        var url = baseURL + "/signalk/v1/access/requests";
        Log.d("[Auth] POST " + url);
        Log.d("[Auth]   clientId=" + clientId);
        Log.d("[Auth]   description=" + getDeviceDescription());

        Communications.makeWebRequest(
            url,
            body,
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
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

    function onSpinnerTick() as Void {
        /*
         * Spinner runs through the whole auth flow: in-flight POST AND
         * the polling phase (PENDING). Stops only at terminal state.
         */
        if (accessRequestInFlight || authState == AUTH_PENDING) {
            WatchUi.requestUpdate();
        } else {
            spinnerVisible = false;
            spinnerTimer = invalidateTimer(spinnerTimer);
        }
    }

    function onRequestAccessTimeout() as Void {
        if (!accessRequestInFlight) {
            return;
        }
        Log.d("[Auth] requestAccess timed out after " + accessRequestTimeoutMs + "ms");
        Communications.cancelAllRequests();
        finishAccessRequestPost();
        endAuthFlow();
        authState = AUTH_NEEDS_REQUEST;
        lastNetCode = -300;
        WatchUi.requestUpdate();
    }

    /*
     * Cleanup at the end of the access-request POST callback. Does NOT
     * stop the spinner — the auth flow may continue into PENDING, and
     * the spinner should keep spinning during polling.
     */
    function finishAccessRequestPost() as Void {
        accessRequestInFlight = false;
        requestTimeoutTimer = invalidateTimer(requestTimeoutTimer);
        spinnerDelayTimer = invalidateTimer(spinnerDelayTimer);
    }

    /*
     * Cleanup when the auth flow reaches a terminal state (CONNECTED,
     * DENIED, or hard error). Stops the spinner and any pending poll.
     */
    function endAuthFlow() as Void {
        spinnerVisible = false;
        spinnerTimer = invalidateTimer(spinnerTimer);
        pollTimer = invalidateTimer(pollTimer);
    }

    function onRequestAccessReceive(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {

        if (!accessRequestInFlight) {
            Log.d("[Auth] onRequestAccessReceive late response ignored");
            return;
        }
        finishAccessRequestPost();
        lastNetCode = responseCode;

        Log.d("[Auth] onRequestAccessReceive code=" + responseCode + " dataType=" + typeName(data));

        var parsed = tryParseBody(data);

        if ((responseCode == 202 || responseCode == 200) && parsed != null) {
            accessRequestHref = parsed["href"];
            Log.d("[Auth] href=" + accessRequestHref);
            if (accessRequestHref == null) {
                endAuthFlow();
                authState = AUTH_NEEDS_REQUEST;
                WatchUi.requestUpdate();
                return;
            }
            Storage.setValue(StorageKeys.ACCESS_HREF, accessRequestHref);
            enterPendingState();
            return;
        }

        if (responseCode == 400) {
            /*
             * "Already requested" — server still remembers us. If we
             * have a persisted href, just resume polling; otherwise
             * the clientId is burned and the user needs to reset.
             */
            if (accessRequestHref != null) {
                Log.d("[Auth] 400 but we have href — resuming poll");
                enterPendingState();
                return;
            }
        }

        Log.d("[Auth] submit failed, errorCode=" + responseCode);
        endAuthFlow();
        authState = AUTH_NEEDS_REQUEST;
        WatchUi.requestUpdate();
    }

    function enterPendingState() as Void {
        authState = AUTH_PENDING;
        /*
         * Spinner spans the polling phase too. Make sure it's running
         * even if the POST returned faster than spinnerShowAfterMs.
         */
        if (!spinnerVisible) {
            spinnerVisible = true;
            startSpinnerTimer();
        }
        schedulePoll();
        WatchUi.requestUpdate();
    }

    function pollAccessRequest() as Void {

        if (accessRequestHref == null) {
            Log.d("[Auth] pollAccessRequest: no href, skipping");
            return;
        }

        var url = baseURL + accessRequestHref;
        Log.d("[Auth] GET " + url);

        Communications.makeWebRequest(
            url,
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
            },
            method(:onPollAccessReceive)
        );
    }

    function onPollAccessReceive(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {

        Log.d("[Auth] onPollAccessReceive code=" + responseCode + " dataType=" + typeName(data));
        lastNetCode = responseCode;

        if (responseCode != 200) {
            /*
             * Bail conditions: the request is gone server-side. signalk-server
             * keeps pending access-requests in memory only — a process restart
             * loses them, and polling the (now-unknown) requestId returns 500
             * (lookup throws) or 404. In any of these cases, retrying forever
             * is a dead loop; clear the persisted href and bounce to
             * NEEDS_REQUEST so the user can re-submit.
             */
            if (responseCode == 404 ||
                responseCode == 410 ||
                (responseCode >= 500 && responseCode < 600)) {
                Log.d("[Auth] poll bailout: request gone server-side, code=" + responseCode);
                Storage.deleteValue(StorageKeys.ACCESS_HREF);
                accessRequestHref = null;
                endAuthFlow();
                authState = AUTH_NEEDS_REQUEST;
                WatchUi.requestUpdate();
                return;
            }
            Log.d("[Auth] poll non-200, scheduling retry");
            schedulePoll();
            WatchUi.requestUpdate();
            return;
        }

        var parsed = tryParseBody(data);
        if (parsed == null) {
            Log.d("[Auth] poll 200 but body unparseable");
            schedulePoll();
            return;
        }

        var state = parsed["state"];
        Log.d("[Auth]   state=" + state);

        if (state != null && state.equals("PENDING")) {
            /*
             * Skip requestUpdate when nothing has changed — saves a UI
             * wake every 3s while we wait for admin approval.
             */
            if (lastAuthStateObserved != AUTH_PENDING) {
                lastAuthStateObserved = AUTH_PENDING;
                WatchUi.requestUpdate();
            }
            schedulePoll();
            return;
        }

        if (state != null && state.equals("COMPLETED")) {
            var accessRequest = parsed["accessRequest"];
            Log.d("[Auth]   accessRequest=" + accessRequest);
            var permission = null;
            var jwt = null;
            if (accessRequest instanceof Lang.Dictionary) {
                permission = accessRequest["permission"];
                jwt = accessRequest["token"];
            }
            Log.d("[Auth]   permission=" + permission + " tokenPresent=" + (jwt != null));

            if (permission != null && permission.equals("APPROVED") && jwt != null) {
                finalizeApproval(jwt);
                return;
            }

            if (permission != null && permission.equals("DENIED")) {
                finalizeDenial();
                return;
            }
        }

        Log.d("[Auth] poll: unknown state, scheduling retry");
        schedulePoll();
    }

    function finalizeApproval(jwt as Lang.String) as Void {
        endAuthFlow();
        token = "Bearer " + jwt;
        Storage.setValue(StorageKeys.TOKEN, token);
        Storage.deleteValue(StorageKeys.ACCESS_HREF);
        accessRequestHref = null;
        authState = AUTH_CONNECTED;
        /*
         * Reset lastNetCode so the StatusView shows CONNECTED rather
         * than whatever the previous poll attempt landed on.
         */
        lastNetCode = null;
        probeOk = null;
        /*
         * Pretend the previous poll failed so the first 200 from the
         * post-approval data poll triggers the redirect to the data
         * page (instead of leaving the user on Status after auto-pop).
         */
        lastDataPollOk = false;
        Log.d("[Auth] ** APPROVED ** — starting data poll");
        /*
         * Fire the toast from here (not from the request-access view)
         * so it shows even if the user backed out of the spinner
         * before the poll completed.
         */
        WatchUi.showToast(Rez.Strings.ToastApproved, null);
        updateVesselDataFromServer();
        WatchUi.requestUpdate();
    }

    function finalizeDenial() as Void {
        endAuthFlow();
        Storage.deleteValue(StorageKeys.ACCESS_HREF);
        accessRequestHref = null;
        authState = AUTH_DENIED;
        Log.d("[Auth] ** DENIED ** — user must reset to try again");
        /*
         * Fire the toast from here so it shows even if the user
         * backed out of the spinner. The request-access view (if
         * still on top) auto-pops on the next onUpdate.
         */
        WatchUi.showToast(Rez.Strings.ToastDenied, null);
        WatchUi.requestUpdate();
    }

    /*
     * Drops clientId, href, token locally and generates a fresh
     * clientId so the user can submit a new request. Does NOT cancel
     * the old request on the server — there's no client-side cancel
     * endpoint in SignalK (verified against 2.x server source). An
     * orphaned PENDING request sits on the server until admin denies
     * it.
     */
    function resetAccessRequest() as Void {
        Log.d("[Auth] resetAccessRequest — wiping clientId/href/token");

        stop();

        Storage.deleteValue(StorageKeys.TOKEN);
        Storage.deleteValue(StorageKeys.CLIENT_ID);
        Storage.deleteValue(StorageKeys.ACCESS_HREF);

        token = null;
        clientId = null;
        accessRequestHref = null;
        lastNetCode = null;
        probeOk = null;
        lastDataPollOk = false;

        authState = AUTH_NEEDS_REQUEST;
    }

    function schedulePoll() {
        pollTimer = invalidateTimer(pollTimer);
        pollTimer = new Timer.Timer();
        pollTimer.start(method(:pollAccessRequest), pendingPollInterval, false);
    }

    /*
     * ============== Data poll ==============
     */

    function updateVesselDataFromServer() as Void {

        updateTimer = invalidateTimer(updateTimer);

        var url = baseURL + "/signalk/v1/api/minimumvesseldatarest/vesseldata";

        /*
         * Throttled "GET vesseldata" log — printing 3×/s would drown
         * the [Data] log. Log the first request after startup/recovery
         * and then a heartbeat every ~dataPollLogIntervalMs. Errors
         * and OK→fail / fail→OK transitions log unconditionally in
         * onDataReceive. One-shot refresh requests always log so the
         * trace is unambiguous about who fired them.
         */
        var now = System.getTimer();
        if (oneShotInFlight
                || dataPollLastLogAt == 0
                || (now - dataPollLastLogAt) >= dataPollLogIntervalMs) {
            Log.d("[Data] GET " + url + " (one-shot=" + oneShotInFlight + ")");
            dataPollLastLogAt = now;
        }

        Communications.makeWebRequest(
            url,
            {},
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED,
                    "Authorization" => token
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
            },
            method(:onDataReceive)
        );
    }

    function onDataReceive(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {

        /*
         * -1003 = REQUEST_CANCELLED (e.g. we stopped polling before the
         * response came back). No-op.
         */
        if (responseCode == -1003) {
            Log.d("[Data] response cancelled (-1003)");
            return;
        }

        lastNetCode = responseCode;

        if (responseCode == 200) {
            var parsed = tryParseBody(data);
            if (parsed != null) {
                vessel.applyVesselDataDict(parsed);
                // probe outcome no longer relevant once data flows again
                probeOk = null;
                if (!lastDataPollOk) {
                    /*
                     * Recovery (or first poll after fresh auth): land
                     * the user on the data page — but not on a one-shot
                     * refresh, where the user explicitly opened a
                     * specific view (autopilot / status) and should
                     * stay on it.
                     */
                    Log.d("[Data] poll recovered — code=200 (was failing)");
                    lastDataPollOk = true;
                    if (!oneShotInFlight) {
                        redirectToDataPage();
                    } else {
                        WatchUi.requestUpdate();
                    }
                } else {
                    /*
                     * Steady-state 200. The matching GET request log
                     * (gated by the same dataPollLastLogAt heartbeat)
                     * already gives us a periodic "alive" line; logging
                     * a paired "poll OK" here would just double the
                     * volume. So we stay silent on the success steady
                     * state and let the request side carry the
                     * heartbeat.
                     */
                    WatchUi.requestUpdate();
                }
                if (dataPollEnabled) {
                    updateTimer = new Timer.Timer();
                    updateTimer.start(method(:updateVesselDataFromServer), updateInterval, false);
                }
                oneShotInFlight = false;
                return;
            }
            /*
             * 200 with unparseable body — fall through to error path
             * with a synthesised -400 so the UI shows something useful.
             */
            Log.d("[Data] 200 but body unparseable — synthesising -400");
            lastNetCode = -400;
            responseCode = -400;
        }

        Log.d("[Data] poll failed code=" + responseCode
            + " wasOk=" + lastDataPollOk
            + " oneShot=" + oneShotInFlight);

        /*
         * 401 / 403: token is dead server-side. Wipe it from storage
         * and stop polling — start() returns early when authState is
         * NEEDS_REQUEST, so the retry timer would just spin without
         * hitting the network. The user re-auths via Status → Request
         * Access; finalizeApproval kicks the data poll back off.
         */
        if (responseCode == 401 || responseCode == 403) {
            Log.d("[Data] auth dead — wiping token");
            Storage.deleteValue(StorageKeys.TOKEN);
            token = null;
            authState = AUTH_NEEDS_REQUEST;
            if (lastDataPollOk) {
                lastDataPollOk = false;
                if (!oneShotInFlight) {
                    redirectToConfigPage();
                } else {
                    WatchUi.requestUpdate();
                }
            } else {
                WatchUi.requestUpdate();
            }
            oneShotInFlight = false;
            return;
        }

        /*
         * Ambiguous codes (404, 400) need the discovery probe to
         * distinguish "server is up but plugin route missing" from
         * "server is down". Only fire once per error episode.
         */
        if ((responseCode == 404 || responseCode == 400) && probeOk == null) {
            fireDiscoveryProbe();
        }

        /*
         * First failure after a healthy run: redirect ViewLoop to the
         * Status page so the user sees the error state without having
         * to swipe. Subsequent retries don't re-redirect. One-shot
         * refreshes never redirect (see oneShotInFlight comment above).
         */
        if (lastDataPollOk) {
            lastDataPollOk = false;
            if (!oneShotInFlight) {
                redirectToConfigPage();
            } else {
                WatchUi.requestUpdate();
            }
        } else {
            WatchUi.requestUpdate();
        }
        if (dataPollEnabled) {
            startRetryTimer();
        }
        oneShotInFlight = false;
    }

    /*
     * Replaces the active view with a fresh ViewLoop landing on the
     * Status (config) page. Cheap — the factory regenerates view
     * instances; ViewLoop only caches adjacent pages anyway. Called on
     * data-poll failure transitions so the user sees the connectivity
     * state without having to navigate the loop.
     */
    function redirectToConfigPage() as Void {
        Log.d("[REST] redirect → StatusView (poll failure transition)");
        var pair = VesselViewLoop.build(VIEWLOOP_PAGE_STATUS);
        WatchUi.switchToView(pair[0], pair[1], WatchUi.SLIDE_LEFT);
    }

    /*
     * Mirror of redirectToConfigPage for the recovery path: lands on
     * the VesselData page after a fail → OK transition (or after the
     * very first successful poll following a fresh auth approval).
     */
    function redirectToDataPage() as Void {
        Log.d("[REST] redirect → VesselDataView (poll recovery transition)");
        var pair = VesselViewLoop.build(VIEWLOOP_PAGE_DATA);
        WatchUi.switchToView(pair[0], pair[1], WatchUi.SLIDE_RIGHT);
    }

    function startRetryTimer() {
        Log.d("[Data] network error — retry in " + retryInterval / 1000 + "s");
        retryTimer = invalidateTimer(retryTimer);
        retryTimer = new Timer.Timer();
        retryTimer.start(method(:start), retryInterval, false);
    }

    /*
     * ============== Discovery probe ==============
     *
     * GET /signalk — SignalK spec discovery endpoint. Unauthenticated;
     * returns 200 + JSON when the server is alive, regardless of the
     * vessel-data plugin's status. Used to disambiguate 404/400 from
     * the data poll: probeOk=true → MISSING_PLUGIN, probeOk=false →
     * NOT_REACHABLE.
     */
    function fireDiscoveryProbe() as Void {
        if (baseURL == null) {
            return;
        }
        var url = baseURL + "/signalk";
        Log.d("[Probe] GET " + url);
        Communications.makeWebRequest(
            url,
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
            },
            method(:onProbeReceive)
        );
    }

    function onProbeReceive(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        Log.d("[Probe] code=" + responseCode);
        probeOk = (responseCode == 200);
        WatchUi.requestUpdate();
    }

    /*
     * ============== Autopilot ==============
     */

    function sendAutopilotCommand(command) {

        if (isAutopilotRequestPending) {
            Log.d("[AP] command dropped — previous request still pending: "
                + command);
            return;
        }
        isAutopilotRequestPending = true;

        var url = baseURL + "/signalk/v1/api/raymarineautopilotfork/command";
        Log.d("[AP] POST " + url + " body=" + command);

        Communications.makeWebRequest(
            url,
            command,
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Accept" => "application/json",
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => token
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
            },
            method(:onAutopilotReceive)
        );
    }

    function onAutopilotReceive(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {

        lastNetCode = responseCode;

        if (responseCode == 200) {
            Log.d("[AP] response code=200 — accepted");
            /*
             * Tactile confirmation that the autopilot accepted the
             * command. Single short pulse; distinct from the longer
             * double-pulse on failure below.
             */
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(50, 75)]);
            }
        } else {
            Log.d("[AP] response code=" + responseCode + " — rejected");
            /*
             * Failure: longer double-pulse so the difference between
             * success and failure is unambiguous through gloves.
             */
            if (Attention has :vibrate) {
                Attention.vibrate([
                    new Attention.VibeProfile(75, 100),
                    new Attention.VibeProfile(0, 100),
                    new Attention.VibeProfile(75, 100)
                ]);
            }
        }

        isAutopilotRequestPending = false;
    }

    /*
     * ============== Helpers ==============
     */

    /*
     * Stops a timer if it exists and returns null so the caller can
     * assign the result back to its own field. The earlier
     * "timer = null" inside this function did nothing — Monkey C
     * passes refs by value, so the caller's var stayed non-null and
     * stale timers could leak.
     * Usage: `myTimer = invalidateTimer(myTimer);`
     */
    function invalidateTimer(timer) {
        if (timer != null) {
            timer.stop();
        }
        return null;
    }

    function getOrCreateClientId() as Lang.String {
        if (clientId != null) {
            return clientId;
        }
        clientId = Utils.generateUuidV4();
        Storage.setValue(StorageKeys.CLIENT_ID, clientId);
        Log.d("[Auth] generated new clientId=" + clientId);
        return clientId;
    }

    /*
     * Body-parse helper. With TEXT_PLAIN responseType CIQ always hands
     * us a string body (or null). Returns the parsed Dictionary, or
     * null on any parse failure or null/non-string input. Callers map
     * null → -400 in their own error handling.
     */
    function tryParseBody(data) as Lang.Dictionary or Null {
        if (!(data instanceof Lang.String)) {
            return null;
        }
        try {
            return Json.parse(data);
        } catch (e instanceof Json.ParseError) {
            Log.d("[REST] body parse failed: " + e.getErrorMessage());
            return null;
        } catch (e) {
            Log.d("[REST] body parse threw: " + e.getErrorMessage());
            return null;
        }
    }

    function typeName(v) as Lang.String {
        if (v == null) { return "Null"; }
        if (v instanceof Lang.Dictionary) { return "Dictionary"; }
        if (v instanceof Lang.String) { return "String"; }
        if (v instanceof Lang.Array) { return "Array"; }
        if (v instanceof Lang.Number) { return "Number"; }
        return "Other";
    }
}
