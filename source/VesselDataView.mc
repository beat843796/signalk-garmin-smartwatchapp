/*
 * VesselDataView.mc
 * Main "connected" screen: three-cell layout with SOG on top, AWA/AWS in the
 * middle, depth at the bottom, plus an orange wind-arrow and port/starboard
 * arc indicator. The enter/select key pushes AutopilotView.
 *
 * Errors (transient network, auth revocation, etc.) are handled globally by
 * VesselModel — it pushes ErrorView on top of this view for transient
 * failures, and switches to AuthConfigView on auth revocation. This view
 * only has to render the happy-path dashboard.
 */

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;
using Toybox.Lang;


using Utilities as Utils;

class VesselDataView extends WatchUi.View {

    var width;
    var height;
    var blockHeight;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        width = dc.getWidth();
        height = dc.getHeight();
        blockHeight = height/3;

        drawValues(dc);

        /*
         * Connection dot — green while data is flowing. When an error
         * occurs, VesselModel pushes the full-screen ErrorView on top of
         * this one, so the dot only shows "healthy" states here.
         */
        dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_WHITE);
        dc.fillCircle(width/2, 3, 3);
    }

    function drawValues(dc) {

        // Grid lines dividing the three rows and splitting the middle row.
        dc.setPenWidth(2);
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_WHITE);
        dc.drawLine(0, blockHeight, width, blockHeight);
        dc.drawLine(0, blockHeight * 2, width, blockHeight * 2);
        dc.drawLine(width/2, blockHeight, width/2, blockHeight * 2);

        // Port / starboard coloured arc segments around the outer edge.
        var arcLineWidth = 15;
        dc.setPenWidth(arcLineWidth);
        dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_WHITE);
        dc.drawArc(width/2, height/2, (width/2), Graphics.ARC_CLOCKWISE, 90, 45);
        dc.setColor(Graphics.COLOR_DK_RED, Graphics.COLOR_WHITE);
        dc.drawArc(width/2, height/2, (width/2), Graphics.ARC_COUNTER_CLOCKWISE, 90, 135);

        // Data rows: SOG / (AWA | AWS) / DBT.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        drawDataText(dc, width/2, 10, "SOG", vessel.getSpeedOverGroundKnotsString());
        drawDataText(dc, width/2, height-blockHeight, "DBT", vessel.getDepthBelowTranscuderMeterString());
        drawDataText(dc, (width/4), blockHeight+5, "AWA", vessel.getAppearantWindAngleDegreeString());
        drawDataText(dc, (width*0.75), blockHeight+5, "AWS", vessel.getApparentWindSpeedKnotsString());

        Utils.drawWindAngle(dc, vessel.apparentWindAngle, width);
    }

    function drawDataText(dc, x, y, labelText, valueText) {
        dc.drawText(
            x,
            y+4,
            Graphics.FONT_SYSTEM_XTINY,
            labelText,
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(
            x,
            y+26,
            Graphics.FONT_SYSTEM_LARGE,
            valueText,
            Graphics.TEXT_JUSTIFY_CENTER);
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
        if (vessel.errorCode != null) {
            return true;
        }
        WatchUi.pushView(new AutopilotView(), new AutopilotDelegate(), WatchUi.SLIDE_RIGHT);
        return true;
    }
}
