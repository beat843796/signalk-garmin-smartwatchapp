/*
 * VesselModel.mc
 * Transport-agnostic representation of the vessel: data fields,
 * formatters, and the autopilot command surface that views interact
 * with. All network ops are delegated to a VesselConnect (REST today,
 * BLE tomorrow). One instance lives at `VesselConnectApp.vessel` and
 * is read by every view.
 *
 * VesselModel is the only thing views touch. Even though current views
 * still reference `vessel.connect.*` for some auth-flow specifics, the
 * data + commands surface (changeHeading, setAutopilotState, the data
 * fields, the formatters) is transport-agnostic on purpose so a future
 * BLE backend can drop in without touching any view.
 */

using Toybox.System;
using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.WatchUi;

using Utilities as Utils;

class VesselModel {

    /*
     * ============== Vessel data fields ==============
     * Populated by VesselConnect via applyVesselDataDict(). Units
     * follow the SignalK spec (SI everywhere) — formatters convert.
     */
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

    /*
     * The transport. Constructed in initialize as RESTVesselConnect;
     * future swap-in for BLE happens here.
     */
    public var connect;

    /*
     * Counter for throttled glance-snapshot writes. Driven by the
     * transport calling persistGlanceSnapshotIfDue() after each
     * successful data apply.
     */
    private var glanceSnapshotCounter = 0;
    private const glanceSnapshotEveryNTicks = 5;

    function initialize() {
        connect = new RESTVesselConnect(self);
    }

    /*
     * Re-reads persisted config (base URL etc.) and recomputes auth
     * state. Called from VesselConnectApp on app start and on settings
     * change.
     */
    function configureSignalK() {
        connect.configureSignalK();
    }

    /*
     * ============== Connectivity (user-facing state) ==============
     */

    /*
     * Returns the current CONN_* state for view rendering. Combines
     * URL/auth state with the transport's most recent network outcome
     * and (if relevant) the discovery probe result.
     */
    function getConnectivity() {
        return Utils.deriveConnectivity(
            connect.getBaseURL(),
            connect.hasToken(),
            connect.hasHref(),
            connect.lastNetCode,
            connect.probeOk);
    }

    /*
     * ============== Autopilot command surface ==============
     */

    function setAutopilotState(state) {
        connect.setAutopilotState(state);
    }

    function changeHeading(change) {
        connect.changeHeading(change);
    }

    /*
     * ============== Auth flow surface ==============
     */

    function requestAccess() {
        connect.requestAccess();
    }

    function resetAccessRequest() {
        connect.reset();
    }

    function startUpdatingData() {
        connect.start();
    }

    function stopUpdatingData() {
        connect.stop();
    }

    function getBaseURL() {
        return connect.getBaseURL();
    }

    function isSpinnerVisible() as Lang.Boolean {
        return connect.isSpinnerVisible();
    }

    function isAccessRequestInFlight() as Lang.Boolean {
        return connect.isAccessRequestInFlight();
    }

    function getDeviceDescription() as Lang.String {
        return connect.getDeviceDescription();
    }

    /*
     * Auth state (REST-specific). Views still branch on AUTH_* in the
     * current UX; the Step 2d UI rework will replace these checks with
     * getConnectivity().
     */
    function getAuthState() {
        return connect.authState;
    }

    /*
     * ============== Data write-back from transport ==============
     */

    /*
     * Applies a parsed vessel-data dict to the local fields. Called
     * by RESTVesselConnect.onDataReceive when a 200 + valid JSON body
     * arrives. Schema is the minimumvesseldatarest plugin's flat dict
     * of SI numbers + autopilotState string. Missing fields land as
     * `null`; formatters render those as "—" so absent values are
     * not confused with valid zero readings.
     */
    function applyVesselDataDict(data as Lang.Dictionary) as Void {
        try {
            depthBelowTranscuder = data["depthBelowTransducer"];
            apparentWindSpeed = data["windSpeedApparent"];
            waterTemperature = data["waterTemperature"];
            speedOverGround = data["speedOverGround"];
            courseOverGround = data["courseOverGroundTrue"];
            apparentWindAngle = data["windAngleApparent"];
            rudderAngle = data["rudderAngle"];
            headingMagnetic = data["headingMagnetic"];
            targetHeadingMagnetic = data["autopilotTargetHeadingMagnetic"];
            targetHeadingTrue = data["autopilotTargetHeadingTrue"];
            targetHeadingWindAppearant = data["autopilotTargetWindAngleApparent"];
            tripTotal = data["tripTotal"];

            if (data["autopilotState"] != null) {
                autopilotState = data["autopilotState"];
            } else {
                autopilotState = "---";
            }
        } catch (ex) {
            ex.printStackTrace();
            resetVesselData();
        }

        /*
         * Throttled: write a glance snapshot every ~5 ticks (~5 s at
         * the default 1 s data poll) so the glance tile can show
         * last-known SOG/AWS/AP without running its own poll.
         */
        glanceSnapshotCounter++;
        if (glanceSnapshotCounter >= glanceSnapshotEveryNTicks) {
            glanceSnapshotCounter = 0;
            persistGlanceSnapshot();
        }
    }

    function resetVesselData() {
        speedOverGround = null;
        apparentWindSpeed = null;
        trueWindSpeed = null;
        depthBelowTranscuder = null;
        apparentWindAngle = null;
        courseOverGround = null;
        headingMagnetic = null;
        rudderAngle = null;
        targetHeadingTrue = null;
        targetHeadingMagnetic = null;
        targetHeadingWindAppearant = null;
        tripTotal = null;
        waterTemperature = null;
        autopilotState = "---";
    }

    /*
     * ============== Display formatters ==============
     */

    /*
     * All numeric formatters return "—" when their backing field is
     * null. Missing fields in the data response land as null (not 0)
     * so absent readings aren't mistaken for valid zero values — e.g.
     * waterTemperature missing should NOT render as -273°C.
     */

    function getSpeedOverGroundKnotsString() {
        if (speedOverGround == null) { return "—"; }
        return Utils.formatSpeedKnots(speedOverGround);
    }

    function getApparentWindSpeedKnotsString() {
        if (apparentWindSpeed == null) { return "—"; }
        return Utils.formatSpeedKnots(apparentWindSpeed);
    }

    function getTrueWindSpeedKnotsString() {
        if (trueWindSpeed == null) { return "—"; }
        return Utils.formatSpeedKnots(trueWindSpeed);
    }

    function getDepthBelowTranscuderMeterString() {
        if (depthBelowTranscuder == null) { return "—"; }
        return Utils.formatDepthMeters(depthBelowTranscuder);
    }

    function getTripTotalString() {
        if (tripTotal == null) { return "—"; }
        return Utils.formatTripNauticalMiles(tripTotal);
    }

    function getWaterTemperatureString() {
        if (waterTemperature == null) { return "—"; }
        return Utils.formatTemperatureCelsius(waterTemperature);
    }

    function getAppearantWindAngleDegreeString() {
        if (apparentWindAngle == null) { return "—"; }
        return Utils.radiansToDegrees(apparentWindAngle).abs().format("%.0f") + "°";
    }

    function getCourseOverGroundDegreeString() {
        if (courseOverGround == null) { return "—"; }
        return Utils.radiansToDegrees(courseOverGround).abs().format("%.0f") + "°";
    }

    function getHeadingMagneticDegreeString() {
        if (headingMagnetic == null) { return "—"; }
        return Utils.radiansToDegrees(headingMagnetic).abs().format("%.0f") + "°";
    }

    function getTargetHeadingTrueDegreeString() {
        if (targetHeadingTrue == null) { return "—"; }
        return Utils.radiansToDegrees(targetHeadingTrue).abs().format("%.0f") + "°";
    }

    function getTargetHeadingMagneticDegreeString() {
        if (targetHeadingMagnetic == null) { return "—"; }
        return Utils.radiansToDegrees(targetHeadingMagnetic).abs().format("%.0f") + "°";
    }

    function getTargetHeadingWindAppearantDegreeString() {
        if (targetHeadingWindAppearant == null) { return "—"; }
        return Utils.radiansToDegrees(targetHeadingWindAppearant).abs().format("%.0f") + "°";
    }

    /*
     * Autopilot state names are lower-case in SignalK but rendered
     * upper-case in the UI, with "route" reduced to "TRACK" so it
     * fits on-screen.
     */
    function getNameForActiveState() {
        var stateName = autopilotState.toUpper();
        if (stateName.equals(ApStates.ROUTE.toUpper())) {
            stateName = "TRACK";
        }
        return stateName;
    }

    /*
     * ============== Helpers ==============
     */

    function persistGlanceSnapshot() {
        Storage.setValue(StorageKeys.GLANCE_SNAPSHOT, {
            "sog" => (speedOverGround != null)   ? Utils.meterPerSecondToKnots(speedOverGround)   : null,
            "aws" => (apparentWindSpeed != null) ? Utils.meterPerSecondToKnots(apparentWindSpeed) : null,
            "ap"  => getNameForActiveState()
        });
    }

    /*
     * ============== Boat type ==============
     * Persisted choice between sailboat (default) and motor. Read on
     * every getBoatType call (cheap — Application.Storage is in-memory
     * after first read). Will eventually drive which fields appear on
     * VesselDataView.
     */
    function getBoatType() as Lang.String {
        var stored = Storage.getValue(StorageKeys.BOAT_TYPE);
        if (stored == null) {
            return BoatType.SAIL;
        }
        return stored;
    }

    function setBoatType(type as Lang.String) as Void {
        Storage.setValue(StorageKeys.BOAT_TYPE, type);
    }
}
