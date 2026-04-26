/*
 * TempView.mc
 * ViewLoop page showing the current water temperature large in the
 * centre of the screen. Select pushes AutopilotView — same as the main
 * data page — so autopilot control is reachable from here too.
 */

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;

class TempView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        var temp = (vessel.getConnectivity() == CONN_CONNECTED)
            ? vessel.getWaterTemperatureString()
            : "—";

        // Title sits above the value with a real gap derived from font
        // metrics — the previous fixed -50 offset got intersected by
        // the LARGE font's ascender on this device.
        var valueFont = Graphics.FONT_SYSTEM_LARGE;
        var titleFont = Graphics.FONT_SYSTEM_XTINY;
        var valueH = dc.getFontHeight(valueFont);
        var titleH = dc.getFontHeight(titleFont);
        var gap = 6;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(
            cx,
            cy - valueH / 2 - titleH / 2 - gap,
            titleFont,
            "WATER TEMP",
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(
            cx,
            cy,
            valueFont,
            temp,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
    }
}

class TempViewDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Lang.Boolean {
        if (vessel.getConnectivity() != CONN_CONNECTED) {
            return true;
        }
        WatchUi.pushView(new AutopilotView(), new AutopilotDelegate(), WatchUi.SLIDE_RIGHT);
        return true;
    }
}
