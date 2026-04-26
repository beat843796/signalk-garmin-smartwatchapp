/*
 * BLEVesselConnect.mc
 * Future BLE GATT implementation of VesselConnect. Stub today —
 * exists so the VesselConnect interface is exercised by more than one
 * concrete subclass, which keeps the seam honest. To activate, swap
 * `connect = new RESTVesselConnect(self)` to
 * `connect = new BLEVesselConnect(self)` in VesselModel.initialize().
 *
 * Implementation notes for whoever wires this up:
 *   - BLE has no SignalK-style device-access-request flow. Pairing
 *     happens at the OS level (the user pairs the watch with the
 *     boat's BLE peripheral via Garmin Connect). So there's no
 *     authState machine, no spinner, no access-request POST. The
 *     RequestAccessView wouldn't be reachable from this transport;
 *     StatusView's CONN_NOT_AUTH path would need a different action
 *     (e.g. open a "pair via Garmin Connect" prompt) when this is
 *     active.
 *   - Vessel-data subscription would be a GATT notify on a custom
 *     SignalK-over-BLE characteristic. On each notify, parse and call
 *     vessel.applyVesselDataDict.
 *   - Autopilot commands would be GATT writes to a write
 *     characteristic.
 *   - lastNetCode + probeOk semantics still apply but the codes used
 *     would be BLE-specific (-1xx range from CIQ); deriveConnectivity
 *     in Utilities would need a parallel BLE branch (or the BLE
 *     transport would normalise its codes onto the same vocabulary).
 *
 * Toybox.BluetoothLowEnergy is the relevant SDK module. See
 * developer.garmin.com for current API.
 */

using Toybox.Lang;

class BLEVesselConnect extends VesselConnect {

    function initialize(vesselRef) {
        VesselConnect.initialize(vesselRef);
        // TODO: register profile / scan for paired peripheral / etc.
    }

    function start() as Void {
        // TODO: subscribe to vessel-data characteristic via GATT notify.
        throw new Lang.Exception();
    }

    function stop() as Void {
        // TODO: unsubscribe + tear down BLE state.
        throw new Lang.Exception();
    }

    function setAutopilotState(state) as Void {
        // TODO: GATT write to autopilot-state characteristic.
        throw new Lang.Exception();
    }

    function changeHeading(degrees) as Void {
        // TODO: GATT write to heading-change characteristic.
        throw new Lang.Exception();
    }
}
