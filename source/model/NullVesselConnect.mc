/*
 * NullVesselConnect.mc
 * Stand-in transport assigned to vessel.connect when the user has not
 * yet picked a connection type (StorageKeys.CONNECTION_TYPE missing
 * or "none"). Every method inherits the no-op default from
 * VesselConnect; the only override is getStatusKind / getDisplayTitle
 * so the StatusView (or glance) can branch off CONN_NONE if useful.
 *
 * Why a Null impl rather than `vessel.connect = null`: it lets every
 * view / model callsite call methods on connect unconditionally. No
 * null guards in the data path, no risk of forgetting one and crashing
 * the app on first launch before the user has picked.
 */

using Toybox.Lang;

class NullVesselConnect extends VesselConnect {

    function initialize(vesselRef) {
        VesselConnect.initialize(vesselRef);
    }

    function getStatusKind() as Lang.Number {
        return CONN_NONE;
    }

    /*
     * No display title — StatusView is expected to push the
     * connection-type picker on top whenever the type is NONE, so this
     * label is rarely visible. Returning empty rather than "" so a
     * stray render is silent rather than showing weird placeholder
     * copy.
     */
    function getDisplayTitle() as Lang.String {
        return "";
    }

    function getStatusLabel() as Lang.String {
        return "";
    }
}
