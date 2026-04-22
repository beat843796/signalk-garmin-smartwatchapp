// Constants.mc
// Shared string constants used across the main-app slice AND the glance
// slice. Kept in a non-annotated module so both slices compile with them.
//
// - StorageKeys: Application.Storage key names. Writer (VesselModel) and
//   reader (SignalKGlanceView) live in different compile slices; a typo in
//   either would silently break the glance — pinning the keys here prevents
//   that.
// - ApStates: the autopilot protocol-level state strings used in server
//   requests and responses. Duplicated as raw strings in 13+ places before
//   this was added.

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
