/*
 * BleConnectView.mc
 * Spinner view shown while BleService is in BLE_CONNECTING. Displays
 * the shared rotating-arc spinner with a "Connecting <name>" label.
 *
 * Drives a 150 ms redraw timer purely for the spinner animation — the
 * actual connection retry cadence (1 s) lives inside BleService and is
 * driven by its own timer.
 *
 * Lifecycle:
 *   onShow         — registers the success callback on BleService.
 *                    BleService is the source of truth for connect
 *                    attempts; the view does not own the BLE state.
 *   onConnected    — fired by BleService once CONNECTION_STATE_CONNECTED
 *                    arrives. Toasts and pops the view back to StatusView.
 *   onBack         — cancels the in-flight attempt and pops.
 *   onHide         — stops the redraw timer; safety in case the view is
 *                    torn down by another mechanism (e.g. the back-stack
 *                    being unwound by parent code).
 */

using Toybox.WatchUi;
using Toybox.Lang;
using Toybox.Timer;
using Toybox.System;

using Utilities as Utils;

class BleConnectView extends WatchUi.View {

    private var redrawTimer;
    private var label;

    /*
     * Defer the post-success view transition through a one-shot timer
     * to keep WatchUi calls out of the onUpdate / BLE-callback stack
     * — same reason AuthConfigView defers its terminal pop. On
     * success, instead of popping back to StatusView, we switchToView
     * straight to the data dashboard so a successful pair lands the
     * user where they want to be.
     */
    private var popTimer;
    private var popScheduled = false;

    function initialize() {
        View.initialize();
        label = "Connecting SignalK";
    }

    function onShow() {
        System.println("[BLE] BleConnectView onShow");
        // Only ever pushed in BLE mode (Config menu gates inclusion of
        // the "Connect" item on transport type), so vessel.connect is a
        // BLEVesselConnect — startConnect is a no-op default for other
        // transports anyway.
        vessel.connect.startConnect(method(:onConnected));
        redrawTimer = new Timer.Timer();
        redrawTimer.start(method(:onRedrawTick), 150, true);
    }

    function onHide() {
        System.println("[BLE] BleConnectView onHide");
        if (redrawTimer != null) {
            redrawTimer.stop();
            redrawTimer = null;
        }
        if (popTimer != null) {
            popTimer.stop();
            popTimer = null;
        }
    }

    function onRedrawTick() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        Utils.drawSpinner(dc, label);
    }

    /*
     * Called by BleService once the link is up. Toast confirms the
     * pair, then we switch directly to the data dashboard — the
     * spinner was the user's most recent intent, and after success
     * they want to see live data, not the status screen.
     */
    function onConnected() as Void {
        System.println("[BLE] BleConnectView onConnected");
        WatchUi.showToast("Connected", null);
        if (!popScheduled) {
            popScheduled = true;
            popTimer = new Timer.Timer();
            popTimer.start(method(:doNavigateToData), 50, false);
        }
    }

    function doNavigateToData() as Void {
        popTimer = null;
        var pair = VesselViewLoop.build(VIEWLOOP_PAGE_DATA);
        WatchUi.switchToView(pair[0], pair[1], WatchUi.SLIDE_RIGHT);
    }
}

class BleConnectViewDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Lang.Boolean {
        System.println("[BLE] BleConnectView onBack — cancelling");
        vessel.connect.cancelConnect();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
