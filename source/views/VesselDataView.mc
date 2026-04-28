/*
 * VesselDataView.mc
 * Main "connected" screen: three-cell layout with SOG on top, AWA/AWS in the
 * middle, depth at the bottom, plus an orange wind-arrow and port/starboard
 * arc indicator. The enter/select key pushes AutopilotView.
 *
 * Errors are handled globally by RESTVesselConnect — on the first failure
 * after a healthy run it redirects the ViewLoop to the StatusView (config)
 * page so the user sees the connectivity issue. While not CONNECTED this
 * view shows "—" placeholders instead of stale numbers.
 */

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;
using Toybox.Lang;
using Toybox.System;


using Utilities as Utils;

class VesselDataView extends WatchUi.View {

    var width;
    var height;
    var blockHeight;

    function initialize() {
        View.initialize();
    }

    /*
     * Subscribe to the NAV characteristic when this view becomes
     * visible. NAV carries SOG, AWA, AWS, depth — the fields rendered
     * here. Other characteristics are not read while this view is up.
     * No-op for non-BLE transports.
     */
    function onShow() as Void {
        if (vessel != null) {
            vessel.beginDataStreaming(BleCharUuids.NAV);
        }
    }

    function onUpdate(dc) {
        View.onUpdate(dc);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        width = dc.getWidth();
        height = dc.getHeight();
        blockHeight = height / 3;

        drawValues(dc);

    }

    function drawValues(dc) {

        // Grid lines dividing the three rows and splitting the middle row.
        dc.setPenWidth(2);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(0, blockHeight, width, blockHeight);
        dc.drawLine(0, blockHeight * 2, width, blockHeight * 2);
        dc.drawLine(width/2, blockHeight, width/2, blockHeight * 2);

        // Port / starboard coloured arc segments around the outer edge.
        // Slightly thicker than before so they read better on AMOLED.
        var arcLineWidth = 20;
        dc.setPenWidth(arcLineWidth);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
        dc.drawArc(width/2, height/2, (width/2), Graphics.ARC_CLOCKWISE, 90, 45);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_BLACK);
        dc.drawArc(width/2, height/2, (width/2), Graphics.ARC_COUNTER_CLOCKWISE, 90, 135);

        // While neither transport (REST nor BLE) is delivering data,
        // show "—" placeholders so the user isn't misled by frozen
        // values from a previous session.
        var connected = vessel.hasDataConnection();
        var sog = connected ? vessel.getSpeedOverGroundKnotsString() : "—";
        var dbt = connected ? vessel.getDepthBelowTranscuderMeterString() : "—";
        var awa = connected ? vessel.getAppearantWindAngleDegreeString() : "—";
        var aws = connected ? vessel.getApparentWindSpeedKnotsString() : "—";

        // Three rows of equal height. Top row = SOG, middle row split
        // into AWA | AWS, bottom row = DBT. drawCell centres the value
        // in the cell with the title floating just above.
        drawCell(dc, 0,         0,                width,         blockHeight, "SOG", sog);
        drawCell(dc, 0,         blockHeight,      width / 2,     blockHeight, "AWA", awa);
        drawCell(dc, width / 2, blockHeight,      width / 2,     blockHeight, "AWS", aws);
        drawCell(dc, 0,         blockHeight * 2,  width,         blockHeight, "DBT", dbt);

        if (connected && vessel.apparentWindAngle != null) {
            Utils.drawWindAngle(dc, vessel.apparentWindAngle, width);
        }
    }

    /*
     * Renders a single grid cell: value text vertically centred in the
     * cell, title text floating just above with a gap derived from
     * actual font metrics so the title isn't clipped by the value's
     * ascender.
     */
    function drawCell(dc, cellX, cellY, cellW, cellH, label, value) {
        var centerX = cellX + cellW / 2;
        var centerY = cellY + cellH / 2;
        var valueFont = Graphics.FONT_SYSTEM_LARGE;
        var titleFont = Graphics.FONT_SYSTEM_XTINY;
        var valueH = dc.getFontHeight(valueFont);
        var titleH = dc.getFontHeight(titleFont);
        var gap = -17;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            centerY - valueH / 2 - titleH / 2 - gap,
            titleFont,
            label,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            centerY+12,
            valueFont,
            value,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
    }
}

/*
 * Input delegate for VesselDataView. Only the select/enter key is used; it
 * opens the AutopilotView (which has its own key bindings for heading
 * adjustment and the mode menu).
 */
class VesselDataViewDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Lang.Boolean {
        // Allow opening AutopilotView whenever either transport is
        // delivering data so the user can read the current state. The
        // view itself gates command-sending on REST connectivity (UP /
        // DOWN / SELECT push NoRestConnectionView when REST is down).
        if (!vessel.hasDataConnection()) {
            return true;
        }
        WatchUi.pushView(new AutopilotView(), new AutopilotDelegate(), WatchUi.SLIDE_RIGHT);
        return true;
    }


}
