/*
 * BleVesselConnect.mc
 * VesselConnect wrapper around BleService — the latter owns the GATT
 * delegate, scan/pair, read/write loop, and characteristic decoding;
 * this thin facade adapts that surface to the unified VesselConnect
 * interface that VesselModel and the views speak to.
 *
 * The BleService stays a separate object because Toybox.BluetoothLowEnergy
 * requires its delegate to extend Ble.BleDelegate, and folding all the
 * VesselConnect surface plus the CIQ delegate machinery into one class
 * pulls a lot of unrelated concerns into one file. Keeping them split
 * also matches CLAUDE.md's "model + transport" architecture pattern.
 *
 * Status mapping — internal BLE_* → unified CONN_*:
 *   BLE_DISCONNECTED → CONN_DISCONNECTED
 *   BLE_CONNECTING   → CONN_CONNECTING
 *   BLE_CONNECTED    → CONN_CONNECTED
 *
 * Glance side-effects: on link transitions, persists a snapshot fragment
 * with the device name / connection-type marker so the glance can render
 * the right "BLE / <device>" line without touching the BleService.
 */

using Toybox.Lang;
using Toybox.Application.Storage;
using Toybox.System;
using Toybox.WatchUi;

class BleVesselConnect extends VesselConnect {

    private var service;

    function initialize(vesselRef) {
        VesselConnect.initialize(vesselRef);
        service = new BleService(vesselRef, self);
    }

    /*
     * ============== Lifecycle ==============
     */

    /*
     * Kicks the silent autoconnect scan if the user has previously
     * paired and not subsequently hit Disconnect. No-op otherwise. The
     * BleConnectView spinner flow uses startConnect() instead.
     */
    function start() as Void {
        System.println("[BLE] start (try autoconnect)");
        service.tryAutoconnect();
    }

    /*
     * Tears down the BLE link without touching the sticky autoconnect
     * flag. Called by app-shutdown (onStop) and transport-switch
     * teardown — both must preserve the flag so re-launch /
     * switch-back-to-BLE will autoconnect transparently. The
     * user-initiated opt-out path is `disconnect()` below, which DOES
     * clear the flag.
     */
    function stop() as Void {
        System.println("[BLE] stop — tearing down GATT link");
        service.teardownLink();
    }

    /*
     * BLE link state is push-driven by CIQ (onConnectedStateChanged);
     * there's nothing to refresh on demand. Provided for interface
     * symmetry with REST.refresh(); StatusView calls vessel.refresh()
     * unconditionally.
     */
    function refresh() as Void {}

    /*
     * ============== Status surface ==============
     */

    function getDisplayTitle() as Lang.String {
        return WatchUi.loadResource(Rez.Strings.TitleBle) as Lang.String;
    }

    function getStatusKind() as Lang.Number {
        var s = service.getState();
        if (s == BLE_CONNECTED)  { return CONN_CONNECTED; }
        if (s == BLE_CONNECTING) { return CONN_CONNECTING; }
        return CONN_DISCONNECTED;
    }

    function getStatusLabel() as Lang.String {
        var s = service.getState();
        if (s == BLE_CONNECTED) {
            var name = service.getConnectedDeviceName();
            if (name != null && name.length() > 0) {
                return name;
            }
            return WatchUi.loadResource(Rez.Strings.BleStatusConnected) as Lang.String;
        }
        if (s == BLE_CONNECTING) {
            return WatchUi.loadResource(Rez.Strings.BleStatusConnecting) as Lang.String;
        }
        return WatchUi.loadResource(Rez.Strings.BleStatusNotConnected) as Lang.String;
    }

    /*
     * ============== Connect surface ==============
     */

    function startConnect(onConnectedCb) as Void {
        service.startConnect(onConnectedCb);
    }

    function cancelConnect() as Void {
        service.cancelConnect();
    }

    function disconnect() as Void {
        service.disconnect();
    }

    /*
     * ============== Streaming surface ==============
     */

    function beginDataStreaming(charUuidStr as Lang.String) as Void {
        service.beginDataStreaming(charUuidStr);
    }

    function endDataStreaming() as Void {
        service.endDataStreaming();
    }

    /*
     * ============== Command surface ==============
     */

    function setAutopilotState(state) as Void {
        System.println("[AP] setAutopilotState '" + state + "' (BLE)");
        service.sendAutopilotSetState(state);
    }

    function changeHeading(degrees) as Void {
        System.println("[AP] changeHeading " + degrees + "° (BLE)");
        service.sendAutopilotChangeHeading(degrees);
    }

    /*
     * ============== Link observer hooks ==============
     * Called by BleService on state transitions. Keeps the side effects
     * (status redraw, glance snapshot fragment) here so BleService stays
     * a pure GATT/scan owner.
     */

    function onLinkConnected() as Void {
        System.println("[BLE] onLinkConnected (facade) — persisting glance snapshot");
        if (vessel != null) {
            vessel.persistGlanceSnapshot();
        }
        WatchUi.requestUpdate();
    }

    function onLinkDisconnected() as Void {
        System.println("[BLE] onLinkDisconnected (facade)");
        WatchUi.requestUpdate();
    }
}
