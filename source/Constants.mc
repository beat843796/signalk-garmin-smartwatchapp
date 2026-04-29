/*
 * Constants.mc
 * Shared constants used across the main-app slice AND the glance slice.
 * Kept in a non-annotated module so both slices compile with them.
 *
 * - StorageKeys: Application.Storage key names. Writer (VesselModel) and
 *   reader (SignalKGlanceView) live in different compile slices; a typo in
 *   either would silently break the glance — pinning the keys here prevents
 *   that.
 * - ConnectionType: persisted user pick of which transport to use. The
 *   app speaks ONE transport at a time; the picked type is the single
 *   source of truth.
 * - ApStates: the autopilot protocol-level state strings used in server
 *   requests and responses.
 * - AUTH_*: REST-internal auth state machine values.
 * - AP_STATE_*: autopilot mode IDs used as menu-item IDs and command values.
 * - CONN_*: unified, transport-agnostic connectivity state surfaced by
 *   VesselConnect.getStatusKind() and rendered by views.
 */

module StorageKeys {
    const TOKEN = "signalk-token";
    const CLIENT_ID = "signalk-client-id";
    const ACCESS_HREF = "signalk-access-href";
    const GLANCE_SNAPSHOT = "signalk-glance";
    /*
     * User-selected transport. Value is one of ConnectionType.NONE / REST
     * / BLE (string). Read on launch to pick which VesselConnect impl to
     * construct; written by the connection-type picker.
     */
    const CONNECTION_TYPE = "signalk-connection-type";
    /*
     * Sticky flag set on the first successful BLE pair, cleared when
     * the user explicitly hits Disconnect from the StatusView menu.
     * While set, the app silently re-scans for the SignalK service
     * on every launch and pairs without showing the spinner — see
     * BleService.tryAutoconnect().
     */
    const BLE_AUTOCONNECT = "signalk-ble-autoconnect";
}

/*
 * Connection-type values persisted under StorageKeys.CONNECTION_TYPE.
 * Strings (rather than ints) so they're self-documenting in the
 * simulator's per-app .SET file and in System.println logs.
 */
module ConnectionType {
    const NONE = "none";
    const REST = "rest";
    const BLE  = "ble";
}

module ApStates {
    const STANDBY = "standby";
    const AUTO = "auto";
    const WIND = "wind";
    const ROUTE = "route";
}

/*
 * Auth / config state machine — REST-specific. Used internally by
 * RESTVesselConnect. Views should read the unified CONN_* via
 * vessel.getStatusKind() rather than branching on AUTH_*.
 *
 * Transitions:
 *   NO_URL        -> NEEDS_REQUEST (user sets baseurl_prop)
 *   NEEDS_REQUEST -> PENDING       (user taps request)
 *   PENDING       -> CONNECTED     (poll returns COMPLETED/APPROVED)
 *   PENDING       -> DENIED        (poll returns COMPLETED/DENIED)
 *   DENIED        -> NEEDS_REQUEST (user taps Reset — fresh clientId)
 *   CONNECTED     -> NEEDS_REQUEST (data poll returns 401/403 — token
 *                                   wiped server-side)
 *   any           -> NO_URL        (user clears baseurl_prop)
 */
enum {
    AUTH_NO_URL = -1,
    AUTH_NEEDS_REQUEST = 0,
    AUTH_PENDING = 1,
    AUTH_CONNECTED = 2,
    AUTH_DENIED = 3,
}

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
 * Unified connectivity state surfaced by VesselConnect.getStatusKind().
 * Replaces the previous split between REST-specific CONN_* and
 * BLE-specific BLE_* enums. Each transport maps its internal state to
 * one of these values; the StatusView renders a label + colour off the
 * value alone.
 *
 * Mapping summary:
 *   NONE              — no transport picked yet (NoneVesselConnect)
 *   DISCONNECTED      — transport idle / not paired / no token
 *   CONNECTING        — transport is mid-setup (BLE scanning/pairing or
 *                       REST access request submitted, awaiting approval)
 *   CONNECTED         — transport is fully usable for data + commands
 *   NO_URL            — REST: baseurl_prop missing
 *   NO_HTTPS          — REST: -1001 (Garmin's HTTPS-required policy)
 *   NOT_REACHABLE     — REST: server unreachable (timeout, DNS, 5xx, ...)
 *   NOT_AUTH          — REST: token revoked / never granted
 *   MISSING_PLUGIN    — REST: server up but vesseldata route 404
 *
 * BLE only emits NONE / DISCONNECTED / CONNECTING / CONNECTED; the
 * "error" sub-states above are REST-only because BLE has no equivalent
 * fine-grained failure modes (the link is either up or it isn't).
 */
enum {
    CONN_NONE = -1,
    CONN_NO_URL = 0,
    CONN_NO_HTTPS = 1,
    CONN_NOT_REACHABLE = 2,
    CONN_NOT_AUTH = 3,
    CONN_PENDING = 4,
    CONN_MISSING_PLUGIN = 5,
    CONN_CONNECTED = 6,
    CONN_DISCONNECTED = 7,
    CONN_CONNECTING = 8,
}

/*
 * Internal BLE link state used by BleService. Not surfaced to views —
 * BleVesselConnect maps these onto the unified CONN_* values via
 * getStatusKind(). Kept here because BleService and BleVesselConnect
 * live in different files and share the enum.
 */
enum {
    BLE_DISCONNECTED = 0,
    BLE_CONNECTING = 1,
    BLE_CONNECTED = 2,
}

/*
 * BLE GATT UUIDs — service + the three vessel-data characteristics.
 * Each characteristic carries the data subset displayed by one watch
 * view, so a view can request reads of only its own characteristic
 * (saves radio time and battery vs streaming everything always).
 *
 * Mirrored from the plugin's ble.js CHARACTERISTICS table. Bumping
 * a UUID here must be matched in the plugin or discovery breaks.
 */
module BleCharUuids {
    const SERVICE = "5b9a0001-7d65-4e9e-9e4d-1f6e2a3b4c5d";
    const NAV     = "5b9a0002-7d65-4e9e-9e4d-1f6e2a3b4c5d"; // VesselDataView
    const ENV     = "5b9a0003-7d65-4e9e-9e4d-1f6e2a3b4c5d"; // TempView
    const AP      = "5b9a0004-7d65-4e9e-9e4d-1f6e2a3b4c5d"; // AutopilotView
    const CMD     = "5b9a0005-7d65-4e9e-9e4d-1f6e2a3b4c5d"; // autopilot command (write)
}

/*
 * BLE CMD action codes — wire format mirrors the plugin's
 * CHARACTERISTICS table. Payload follows the action byte at offset 1.
 */
module BleCmdAction {
    const SET_STATE        = 0x01; // payload: u8 state code (1..4)
    const CHANGE_HEADING   = 0x02; // payload: i16 LE degrees signed
    const ADVANCE_WAYPOINT = 0x03; // payload: (none)
    const SILENCE_ALARM    = 0x04; // payload: u8 alarmId, u8 groupId
}

