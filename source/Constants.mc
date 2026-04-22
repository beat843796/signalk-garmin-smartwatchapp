/*
 * Constants.mc
 * Shared constants used across the main-app slice AND the glance slice.
 * Kept in a non-annotated module so both slices compile with them.
 *
 * - StorageKeys: Application.Storage key names. Writer (VesselModel) and
 *   reader (SignalKGlanceView) live in different compile slices; a typo in
 *   either would silently break the glance — pinning the keys here prevents
 *   that.
 * - ApStates: the autopilot protocol-level state strings used in server
 *   requests and responses.
 * - AUTH_*: auth / config state machine values (hoisted out of VesselModel
 *   so every view can reference them by bare name).
 * - AP_STATE_*: autopilot mode IDs used as menu-item IDs and command values.
 */

module StorageKeys {
    const TOKEN = "signalk-token";
    const CLIENT_ID = "signalk-client-id";
    const ACCESS_HREF = "signalk-access-href";
    const GLANCE_SNAPSHOT = "signalk-glance";
}

module ApStates {
    const STANDBY = "standby";
    const AUTO = "auto";
    const WIND = "wind";
    const ROUTE = "route";
}

/*
 * Auth / config state machine. Transitions:
 *   NO_URL        -> NEEDS_REQUEST (user sets baseurl_prop)
 *   NEEDS_REQUEST -> PENDING       (user taps request)
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
