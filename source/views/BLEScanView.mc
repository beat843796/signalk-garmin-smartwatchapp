/*
 * BLEScanView.mc
 * Diagnostic BLE-scan screen. Shows the shared spinner with a "BLE
 * Scanning…" label while a BleScanner runs in the background. Found
 * devices are logged to System.println — there's no on-screen list yet.
 *
 * Lifecycle:
 *   onShow         — starts the scan and a 150 ms redraw timer that
 *                    keeps the spinner animating (the spinner itself is
 *                    stateless and needs an external requestUpdate cadence)
 *   onHide / back  — stops the scan and the redraw timer; the BLE stack
 *                    goes idle and no further scan callbacks fire
 */

using Toybox.WatchUi;
using Toybox.Lang;
using Toybox.Timer;

using Utilities as Utils;

class BLEScanView extends WatchUi.View {

    private var scanner;
    private var redrawTimer;

    function initialize() {
        View.initialize();
        scanner = new BleScanner();
    }

    function onShow() {
        scanner.start();
        redrawTimer = new Timer.Timer();
        redrawTimer.start(method(:onRedrawTick), 150, true);
    }

    function onHide() {
        if (redrawTimer != null) {
            redrawTimer.stop();
            redrawTimer = null;
        }
        scanner.stop();
    }

    function onRedrawTick() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        Utils.drawSpinner(dc, "BLE Scanning");
    }
}

class BLEScanViewDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Lang.Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
