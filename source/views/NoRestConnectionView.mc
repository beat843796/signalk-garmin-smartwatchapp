/*
 * NoRestConnectionView.mc
 * Full-screen error pushed by AutopilotView when the user attempts a
 * command (UP / DOWN / SELECT / CLOCK / MENU / mode-menu pick) while
 * the active transport is not in CONN_CONNECTED. Applies to either
 * REST or BLE — the wording stays generic ("vessel" rather than
 * "SignalK server") so it reads correctly in both modes.
 *
 * Back dismisses; no other input is wired.
 */

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;

class NoRestConnectionView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2,
            h * 0.35,
            Graphics.FONT_SYSTEM_SMALL,
            "No connection",
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2,
            h * 0.50,
            Graphics.FONT_SYSTEM_TINY,
            "to vessel",
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2,
            h * 0.70,
            Graphics.FONT_SYSTEM_XTINY,
            "Check status page",
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
    }
}

class NoRestConnectionViewDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Lang.Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
