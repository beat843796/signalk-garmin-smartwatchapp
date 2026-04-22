// SignalKGlanceView.mc
// Glance-carousel tile shown on the watch's glance screen. Two rows:
//   Row 1: connection state ("Connected" / "Waiting" / "Disconnected").
//   Row 2: SOG / AWS / AP-state when the main app has cached values; blank
//          otherwise.
//
// The (:glance) annotation restricts this class to the glance compile slice.
// Glances get a much smaller memory budget than the full app and can't make
// network requests, so this view reads cached values straight from
// Application.Storage. The main app (VesselModel) writes a combined snapshot
// there every few seconds while the user is interacting with it.
//
// Keys live in the StorageKeys module (see source/Constants.mc) so writer
// and reader share the same names.

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Application.Storage;

(:glance)
class SignalKGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        var h = dc.getHeight();

        var token = Storage.getValue(StorageKeys.TOKEN);
        var pendingHref = Storage.getValue(StorageKeys.ACCESS_HREF);

        var stateText;
        var stateColor;
        if (token != null) {
            stateText = "Connected";
            stateColor = Graphics.COLOR_DK_GREEN;
        } else if (pendingHref != null) {
            stateText = "Waiting";
            stateColor = Graphics.COLOR_DK_BLUE;
        } else {
            stateText = "Disconnected";
            stateColor = Graphics.COLOR_DK_GRAY;
        }

        dc.setColor(stateColor, Graphics.COLOR_WHITE);
        dc.drawText(
            5,
            h * 0.15,
            Graphics.FONT_SYSTEM_SMALL,
            stateText,
            Graphics.TEXT_JUSTIFY_LEFT);

        // Row 2: last-known data summary. Only shown if the main app ran
        // recently enough to write a snapshot — otherwise blank.
        if (token != null) {
            var snapshot = Storage.getValue(StorageKeys.GLANCE_SNAPSHOT);
            if (snapshot instanceof Lang.Dictionary) {
                var sog = snapshot["sog"];
                var aws = snapshot["aws"];
                var ap = snapshot["ap"];
                var sogStr = (sog != null) ? sog.format("%.1f") : "--";
                var awsStr = (aws != null) ? aws.format("%.1f") : "--";
                var apStr  = (ap  != null) ? ap : "--";
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
                dc.drawText(
                    5,
                    h * 0.55,
                    Graphics.FONT_SYSTEM_XTINY,
                    "SOG " + sogStr + "  AWS " + awsStr + "  " + apStr,
                    Graphics.TEXT_JUSTIFY_LEFT);
            }
        }
    }
}
