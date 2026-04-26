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
    const BOAT_TYPE = "signalk-boat-type";
}

module ApStates {
    const STANDBY = "standby";
    const AUTO = "auto";
    const WIND = "wind";
    const ROUTE = "route";
}

/*
 * Boat type — affects which data fields are shown on VesselDataView.
 * Default is sailboat. Toggled by the user via the Config menu on
 * StatusView. Persisted in Application.Storage under BOAT_TYPE.
 */
module BoatType {
    const SAIL = "sailboat";
    const MOTOR = "motor";
}

/*
 * Auth / config state machine. Transitions:
 *   NO_URL        -> NEEDS_REQUEST (user sets baseurl_prop)
 *   NEEDS_REQUEST -> PENDING       (user taps request)
 *   PENDING       -> CONNECTED     (poll returns COMPLETED/APPROVED)
 *   PENDING       -> DENIED        (poll returns COMPLETED/DENIED)
 *   DENIED        -> NEEDS_REQUEST (user taps Reset — fresh clientId)
 *   CONNECTED     -> NEEDS_REQUEST (data poll returns 401/403 — token
 *                                   wiped server-side)
 *   any           -> NO_URL        (user clears baseurl_prop)
 *
 * Transient data-endpoint errors (-300, 404, 5xx, etc.) do NOT mutate
 * auth state — token persists, the user-visible state surfaces via
 * vessel.getConnectivity() / StatusView subtitle, and the poll retries
 * every retryInterval. Only 401/403 or an explicit user reset wipes
 * the token.
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
 * Connectivity state — the user-visible status surfaced on the config
 * (Status) view. Combines the AUTH_* state machine and the most recent
 * data-poll outcome into a single label. Derived by
 * Utilities.deriveConnectivity().
 *
 * Precedence (top to bottom): URL missing > URL not HTTPS > auth pending
 * > no token > token-but-poll-failed > all good.
 */
enum {
    CONN_NO_URL = 0,
    CONN_NO_HTTPS = 1,
    CONN_NOT_REACHABLE = 2,
    CONN_NOT_AUTH = 3,
    CONN_PENDING = 4,
    CONN_MISSING_PLUGIN = 5,
    CONN_CONNECTED = 6,
}
