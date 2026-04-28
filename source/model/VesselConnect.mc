/*
 * VesselConnect.mc
 * Abstract base for vessel-data transports. Exactly one transport is
 * active at a time — the user picks REST or BLE on first launch (and
 * can change it later via the Config menu); the picked impl is built
 * by TransportFactory and assigned to vessel.connect. View code never
 * branches on the transport flavour; it goes through the methods on
 * this base.
 *
 * Subclasses override the methods they actually implement; the defaults
 * here are no-ops so the same view can speak to any transport without
 * type-guards. Examples:
 *
 *   - REST overrides start/stop, requestAccess, refresh,
 *     getStatusKind, getStatusLabel, getDisplayTitle.
 *   - BLE overrides start/stop, startConnect/cancelConnect/disconnect,
 *     beginDataStreaming/endDataStreaming, getStatusKind, getStatusLabel,
 *     getDisplayTitle.
 *   - Null (no method picked) keeps every default — getStatusKind
 *     returns CONN_NONE.
 *
 * The interface deliberately exposes ALL operations a view might want
 * to invoke (REST-y like requestAccess, BLE-y like startConnect) so the
 * view can call them directly. Whichever ones don't apply to the active
 * transport are silently no-op'd at this level. This avoids casts in
 * views and keeps the call sites clean.
 */

using Toybox.Lang;

class VesselConnect {

    /*
     * Reference back to the VesselModel so the transport can call
     * applyVesselDataDict / applyNavData / applyApData / applyEnvData
     * and persistGlanceSnapshot.
     */
    protected var vessel;

    function initialize(vesselRef) {
        vessel = vesselRef;
    }

    /*
     * ============== Lifecycle ==============
     */

    /*
     * Begins data flow. REST: starts the data poll (or access-request
     * poll if not yet authenticated). BLE: kicks the autoconnect scan
     * if the sticky flag is set. Idempotent.
     */
    function start() as Void {}

    /*
     * Halts data flow and tears down any pending requests / timers /
     * radio state. Called from VesselConnectApp.onStop and when
     * switching transport types. Idempotent.
     */
    function stop() as Void {}

    /*
     * One-shot status refresh. REST: fires a single data poll so the
     * status label reflects current reachability. BLE: no-op (link
     * state is push-driven by CIQ's BleDelegate). Used by views in
     * onShow to keep the status label fresh without committing to a
     * recurring poll.
     */
    function refresh() as Void {}

    /*
     * Pauses the recurring data flow without tearing down auth /
     * pairing state. REST: stops the data-poll timer. BLE: no-op (the
     * BLE read loop is already gated on beginDataStreaming, which the
     * view drives). Called by StatusView.onShow so the screen the
     * user uses to manage the connection doesn't burn radio time on
     * data the screen doesn't render anyway.
     */
    function pausePolling() as Void {}

    /*
     * Re-arms the recurring data flow paused by pausePolling.
     * Idempotent — calling twice is harmless.
     */
    function resumePolling() as Void {}

    /*
     * ============== Autopilot command surface ==============
     */

    /*
     * Sets the autopilot to one of the AP_STATE_* modes via the
     * transport-specific protocol. No-op default for transports that
     * cannot send commands (e.g. NullVesselConnect).
     */
    function setAutopilotState(state) as Void {}

    /*
     * Adjusts the autopilot heading by ±N degrees.
     */
    function changeHeading(degrees) as Void {}

    /*
     * ============== Status surface (read by views) ==============
     */

    /*
     * Unified, transport-agnostic connection state. One of the CONN_*
     * values in Constants.mc. Drives view rendering: dashboards show
     * "—" placeholders unless this returns CONN_CONNECTED; AutopilotView
     * gates command-sending on this; StatusView picks its subtitle and
     * colour off this.
     */
    function getStatusKind() as Lang.Number {
        return CONN_NONE;
    }

    /*
     * Short label for the StatusView subtitle. Transport-specific:
     *   REST:    URL when CONNECTED, else a state name
     *            ("NO URL", "NOT REACHABLE", "PENDING", ...)
     *   BLE:     device name when CONNECTED, else "Connecting..." /
     *            "Not Connected"
     *   Null:    "" (StatusView shouldn't be shown in this case anyway)
     *
     * Null-safe — callers may render this directly without null checks.
     */
    function getStatusLabel() as Lang.String {
        return "";
    }

    /*
     * StatusView title — "SignalK Server" for REST, "BLE" for BLE,
     * "" for Null. Per-transport so the view doesn't branch on type.
     */
    function getDisplayTitle() as Lang.String {
        return "";
    }

    /*
     * ============== REST-specific access-request flow ==============
     * Default no-ops so views can call them without guarding on type;
     * non-REST transports simply ignore the call. The Config menu still
     * gates inclusion of the "Request Access" item on the connection
     * type so the user never sees it for BLE.
     */

    function supportsRequestAccess() as Lang.Boolean {
        return false;
    }

    function requestAccess() as Void {}

    function resetAccessRequest() as Void {}

    function isSpinnerVisible() as Lang.Boolean {
        return false;
    }

    function isAccessRequestInFlight() as Lang.Boolean {
        return false;
    }

    /*
     * REST: returns the auth state machine value. Other transports
     * return AUTH_NEEDS_REQUEST as a benign default (matches "no
     * outstanding request"). Used by RequestAccessView, which is only
     * pushed in REST mode.
     */
    function getAuthState() as Lang.Number {
        return AUTH_NEEDS_REQUEST;
    }

    /*
     * ============== BLE-specific connect surface ==============
     */

    /*
     * BLE: kicks the foreground connect flow (with spinner via the
     * onConnectedCallback). Other transports: no-op.
     */
    function startConnect(onConnectedCb) as Void {}

    /*
     * BLE: cancels an in-flight connect attempt. Other transports: no-op.
     */
    function cancelConnect() as Void {}

    /*
     * BLE: drops the GATT link and clears the sticky autoconnect flag.
     * Other transports: no-op.
     */
    function disconnect() as Void {}

    /*
     * BLE: subscribe a view to a specific characteristic. Other
     * transports: no-op (REST polls everything every tick).
     */
    function beginDataStreaming(charUuidStr as Lang.String) as Void {}

    function endDataStreaming() as Void {}

    /*
     * ============== Misc ==============
     */

    /*
     * Human-readable description of the watch — used by REST's access
     * request payload so admins can tell multiple Garmins apart in the
     * SignalK approval UI. BLE doesn't need this but the default is
     * harmless.
     */
    function getDeviceDescription() as Lang.String {
        return "Garmin Watch";
    }
}
