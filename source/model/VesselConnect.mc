/*
 * VesselConnect.mc
 * Abstract base for vessel-data transports. The transport is the only
 * place that knows about the physical layer (HTTP today, BLE tomorrow);
 * VesselModel delegates all network ops to it and stays transport-
 * agnostic. View code never touches a VesselConnect directly — it goes
 * through VesselModel.
 *
 * Subclasses must implement start/stop and the autopilot command
 * methods. REST-specific concerns (auth state machine, base URL,
 * spinner) live on RESTVesselConnect; BLE will have its own pairing
 * model and won't expose those.
 *
 * Common state lives on the base so VesselModel.getConnectivity() can
 * read a uniform shape regardless of impl:
 *   - lastNetCode: most recent HTTP / CIQ code observed from any
 *     request to the underlying server. null = nothing observed yet.
 *   - probeOk: most recent /signalk discovery probe outcome (or
 *     equivalent reachability check). Only consulted by deriveConnectivity
 *     on ambiguous codes (404/400). null = haven't probed.
 */

using Toybox.Lang;

class VesselConnect {

    /*
     * Reference back to the VesselModel so the transport can call
     * applyVesselDataDict (data write-back) and persistGlanceSnapshot
     * (throttled storage write).
     */
    protected var vessel;

    public var lastNetCode = null;
    public var probeOk = null;

    function initialize(vesselRef) {
        vessel = vesselRef;
    }

    /*
     * Begins data flow. For REST: kicks off the data poll loop or, if
     * not yet authenticated, the access-request poll loop.
     */
    function start() as Void {
        throw new Lang.Exception();
    }

    /*
     * Halts data flow. Cancels in-flight requests and any retry timers.
     */
    function stop() as Void {
        throw new Lang.Exception();
    }

    /*
     * Sets the autopilot to one of the AP_STATE_* modes via the
     * transport-specific protocol.
     */
    function setAutopilotState(state) as Void {
        throw new Lang.Exception();
    }

    /*
     * Adjusts the autopilot heading by ±N degrees.
     */
    function changeHeading(degrees) as Void {
        throw new Lang.Exception();
    }
}
