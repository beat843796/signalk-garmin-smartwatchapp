/*
 * BleScanner.mc
 * Lightweight BLE peripheral scanner. Owns a BluetoothLowEnergy.BleDelegate
 * and toggles SCAN_STATE_SCANNING on the global stack. Logs every
 * advertisement seen (name + RSSI) via System.println — used today by
 * BLEScanView for a "what's around?" diagnostic before BLEVesselConnect is
 * wired up as a real transport.
 *
 * Lifecycle:
 *   start()  — registers self as delegate, kicks SCAN_STATE_SCANNING
 *   stop()   — flips back to SCAN_STATE_OFF (delegate stays registered;
 *              CIQ has no setDelegate(null) and a stale delegate is
 *              harmless once scanning is off)
 *
 * Multiple start() / stop() calls are dedup'd via the `scanning` flag so
 * a flapping view lifecycle can't queue duplicate state transitions.
 */

using Toybox.BluetoothLowEnergy as Ble;
using Toybox.System;
using Toybox.Lang;

class BleScanner extends Ble.BleDelegate {

    private var scanning = false;

    function initialize() {
        BleDelegate.initialize();
    }

    function start() as Void {
        if (scanning) {
            return;
        }
        Ble.setDelegate(self);
        Ble.setScanState(Ble.SCAN_STATE_SCANNING);
        scanning = true;
        System.println("[BleScanner] start");
    }

    function stop() as Void {
        if (!scanning) {
            return;
        }
        Ble.setScanState(Ble.SCAN_STATE_OFF);
        scanning = false;
        System.println("[BleScanner] stop");
    }

    /*
     * Called by the BLE stack with an iterator of every ScanResult seen
     * since the last call. We just log each one for now; a future
     * pairing UI will surface them on screen.
     */
    function onScanResults(scanResults as Ble.Iterator) as Void {
        var raw = scanResults.next();
        while (raw != null) {
            // CIQ's iterator types items as Object?; narrow before
            // calling ScanResult-specific accessors.
            if (raw instanceof Ble.ScanResult) {
                var name = raw.getDeviceName();
                if (name == null) {
                    name = "<no name>";
                }
                System.println("[BleScanner] device name=" + name + " rssi=" + raw.getRssi());
            }
            raw = scanResults.next();
        }
    }

    function onScanStateChange(scanState as Ble.ScanState, status as Ble.Status) as Void {
        System.println("[BleScanner] scanState=" + scanState + " status=" + status);
    }
}
