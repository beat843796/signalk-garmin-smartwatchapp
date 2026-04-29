/*
 * VesselModel.mc
 * Transport-agnostic representation of the vessel: data fields,
 * formatters, and the autopilot command surface that views interact
 * with. All network ops are delegated to a VesselConnect — exactly
 * one transport at a time. Constructed at app start with a Null
 * transport; the picker (or the launch-time TransportFactory call)
 * swaps in the user-selected impl via attachTransport.
 *
 * VesselModel is the only thing views touch.
 */

using Toybox.System;
using Toybox.Application.Storage;
using Toybox.Application.Properties;
using Toybox.Lang;
using Toybox.WatchUi;

using Utilities as Utils;

class VesselModel {

    /*
     * ============== Vessel data fields ==============
     * Populated by the active VesselConnect via applyVesselDataDict()
     * (REST, full poll) or applyNavData/applyEnvData/applyApData (BLE,
     * per-characteristic). Units follow the SignalK spec (SI
     * everywhere) — formatters convert.
     */
    public var speedOverGround;              // meter/second
    public var speedThroughWater;            // meter/second
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
     * The active transport. Constructed in initialize as a
     * NoneVesselConnect; replaced by attachTransport once the user's
     * picked type is known. View code calls connect.* directly for
     * transport-specific operations (startConnect for BLE, requestAccess
     * for REST), trusting the no-op defaults on VesselConnect to keep
     * unrelated calls safe.
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
        connect = new NoneVesselConnect(self);
    }

    /*
     * ============== Transport lifecycle ==============
     */

    /*
     * Replaces the current transport (REST, BLE, or Null) with a new
     * one constructed via TransportFactory. Cleanly stops the old one
     * before installing the new — but does NOT delete persisted state
     * (REST token, BLE_AUTOCONNECT) so the user can switch back later
     * without re-authing / re-pairing.
     */
    function attachTransport(newConnect) as Void {
        var fromName = (connect != null) ? classNameOf(connect) : "null";
        var toName = (newConnect != null) ? classNameOf(newConnect) : "null";
        System.println("[Model] attachTransport " + fromName + " → " + toName);
        if (connect != null) {
            connect.stop();
        }
        connect = newConnect;
        /*
         * Reset stale data fields so values from the previous transport
         * don't bleed through while the new one is still warming up.
         */
        resetVesselData();
        Storage.deleteValue(StorageKeys.GLANCE_SNAPSHOT);
    }

    /*
     * Short-form transport tag for log lines — REST/BLE/None — without
     * pulling in any reflection. Keeps [Model] entries grep-able.
     */
    private function classNameOf(c) as Lang.String {
        if (c instanceof RESTVesselConnect) { return "REST"; }
        if (c instanceof BleVesselConnect)  { return "BLE";  }
        if (c instanceof NoneVesselConnect) { return "None"; }
        return "?";
    }

    /*
     * Re-reads persisted REST config (base URL etc.) on settings
     * changes. No-op for non-REST transports.
     */
    function configureSignalK() {
        System.println("[Model] configureSignalK (settings change)");
        if (connect instanceof RESTVesselConnect) {
            connect.configureSignalK();
        }
    }

    /*
     * ============== Connectivity (user-facing state) ==============
     */

    function getStatusKind() as Lang.Number {
        return connect.getStatusKind();
    }

    /*
     * "Data is reaching us" — true iff the active transport is in
     * CONN_CONNECTED. Used by the dashboards to decide between live
     * values and "—" placeholders.
     */
    function hasDataConnection() as Lang.Boolean {
        return connect.getStatusKind() == CONN_CONNECTED;
    }

    /*
     * "Commands will work" — same condition as hasDataConnection() in
     * the one-transport-at-a-time model: if we're getting data, we can
     * also send commands; if we aren't, we can't. Kept as a separate
     * method so AutopilotView's gate stays semantically clear.
     */
    function canSendCommands() as Lang.Boolean {
        return connect.getStatusKind() == CONN_CONNECTED;
    }

    /*
     * One-shot status refresh used by AutopilotView.onShow. Delegated
     * to the transport — REST fires a single data poll; BLE is a no-op
     * (state is push-driven).
     */
    function refreshStatus() as Void {
        connect.refresh();
    }

    /*
     * Pause / resume the recurring data flow. StatusView calls these
     * in onShow/onHide so the connection-management screen doesn't
     * burn radio time on data it doesn't render.
     */
    function pausePolling() as Void {
        connect.pausePolling();
    }

    function resumePolling() as Void {
        connect.resumePolling();
    }

    /*
     * ============== Streaming control ==============
     * Only meaningful for BLE; REST polls every tick regardless. Views
     * call these in onShow/onHide unconditionally.
     */

    function beginDataStreaming(charUuidStr as Lang.String) as Void {
        connect.beginDataStreaming(charUuidStr);
    }

    function endDataStreaming() as Void {
        connect.endDataStreaming();
    }

    /*
     * ============== Autopilot command surface ==============
     */

    function setAutopilotState(state) {
        System.println("[Model] setAutopilotState '" + state + "'");
        connect.setAutopilotState(state);
    }

    function changeHeading(change) {
        System.println("[Model] changeHeading " + change + "°");
        connect.changeHeading(change);
    }

    /*
     * ============== Auth flow surface (REST passthrough) ==============
     */

    function requestAccess() {
        System.println("[Model] requestAccess (user)");
        connect.requestAccess();
    }

    function resetAccessRequest() {
        System.println("[Model] resetAccessRequest (user)");
        connect.resetAccessRequest();
    }

    function startUpdatingData() {
        connect.start();
    }

    function stopUpdatingData() {
        connect.stop();
    }

    function getBaseURL() {
        if (connect instanceof RESTVesselConnect) {
            return connect.getBaseURL();
        }
        return null;
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

    function getAuthState() {
        return connect.getAuthState();
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
            speedThroughWater = data["speedThroughWater"];
            apparentWindSpeed = data["windSpeedApparent"];
            trueWindSpeed = data["windSpeedTrue"];
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

        bumpGlanceSnapshotCounter();
    }

    /*
     * BLE-style partial apply — touches only the fields whose keys
     * are present in `data`. Used by BleService when a per-characteristic
     * read returns; each characteristic carries a subset of fields, and
     * we must NOT clobber unrelated fields (e.g. an AP read shouldn't
     * null out apparent-wind values managed by the NAV characteristic).
     */
    function applyNavData(data as Lang.Dictionary) as Void {
        if (data.hasKey("speedOverGround"))      { speedOverGround = data["speedOverGround"]; }
        if (data.hasKey("speedThroughWater"))    { speedThroughWater = data["speedThroughWater"]; }
        if (data.hasKey("depthBelowTransducer")) { depthBelowTranscuder = data["depthBelowTransducer"]; }
        if (data.hasKey("windAngleApparent"))    { apparentWindAngle = data["windAngleApparent"]; }
        if (data.hasKey("windSpeedApparent"))    { apparentWindSpeed = data["windSpeedApparent"]; }
        if (data.hasKey("windSpeedTrue"))        { trueWindSpeed = data["windSpeedTrue"]; }
        bumpGlanceSnapshotCounter();
    }

    function applyEnvData(data as Lang.Dictionary) as Void {
        if (data.hasKey("waterTemperature")) { waterTemperature = data["waterTemperature"]; }
        // No glance bump — water temp isn't on the glance tile.
    }

    function applyApData(data as Lang.Dictionary) as Void {
        if (data.hasKey("autopilotState"))                   { autopilotState = data["autopilotState"]; }
        if (data.hasKey("courseOverGroundTrue"))             { courseOverGround = data["courseOverGroundTrue"]; }
        if (data.hasKey("headingMagnetic"))                  { headingMagnetic = data["headingMagnetic"]; }
        if (data.hasKey("autopilotTargetHeadingMagnetic"))   { targetHeadingMagnetic = data["autopilotTargetHeadingMagnetic"]; }
        if (data.hasKey("autopilotTargetHeadingTrue"))       { targetHeadingTrue = data["autopilotTargetHeadingTrue"]; }
        if (data.hasKey("autopilotTargetWindAngleApparent")) { targetHeadingWindAppearant = data["autopilotTargetWindAngleApparent"]; }
        if (data.hasKey("rudderAngle"))                      { rudderAngle = data["rudderAngle"]; }
        if (data.hasKey("tripTotal"))                        { tripTotal = data["tripTotal"]; }
        bumpGlanceSnapshotCounter();
    }

    /*
     * Throttled glance-snapshot write: every ~N applies, persist a
     * compact snapshot so the glance tile can show last-known
     * SOG/AWS/AP without running its own poll.
     */
    private function bumpGlanceSnapshotCounter() as Void {
        glanceSnapshotCounter++;
        if (glanceSnapshotCounter >= glanceSnapshotEveryNTicks) {
            glanceSnapshotCounter = 0;
            persistGlanceSnapshot();
        }
    }

    function resetVesselData() {
        speedOverGround = null;
        speedThroughWater = null;
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

    /*
     * Persists a compact glance snapshot covering the picked
     * connection-type plus the values the glance tile renders. Single
     * key (rather than three) cuts flash writes; the glance reads them
     * all at once.
     *
     * `connectionType` lets the glance branch on REST/BLE/NONE without
     * loading VesselModel (forbidden in the glance compile slice).
     * `url` and `bleDeviceName` give the glance the right second-line
     * label for each transport.
     */
    function persistGlanceSnapshot() {
        var bleName = null;
        if (connect instanceof BleVesselConnect && connect.getStatusKind() == CONN_CONNECTED) {
            bleName = connect.getStatusLabel();
        }
        var url = null;
        if (connect instanceof RESTVesselConnect) {
            url = Properties.getValue("baseurl_prop");
        }
        Storage.setValue(StorageKeys.GLANCE_SNAPSHOT, {
            "connectionType" => TransportFactory.getStoredType(),
            "url" => url,
            "bleDeviceName" => bleName,
            "sog" => (speedOverGround != null)   ? Utils.meterPerSecondToKnots(speedOverGround)   : null,
            "aws" => (apparentWindSpeed != null) ? Utils.meterPerSecondToKnots(apparentWindSpeed) : null,
            "ap"  => getNameForActiveState()
        });
    }
}
