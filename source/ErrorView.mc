/*
 * ErrorView.mc
 * Full-screen error display. Pushed by VesselModel on any network error
 * regardless of which view is currently showing; popped automatically when
 * a later request succeeds (errorCode clears). The user can also pop it
 * manually with the back key — if the error is still active, the next
 * failed poll will push it again.
 *
 * Rendering matches the original drawError() layout from VesselDataView:
 * two horizontal dark-red lines dividing the screen into thirds, with the
 * Utilities.errorMessage(code) label centred in the middle band.
 */

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;

using Utilities as Utils;

class ErrorView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var blockHeight = h / 3;

        var code = vessel.errorCode;
        var msg = (code != null) ? Utils.errorMessage(code) : "Unknown error";

        dc.setPenWidth(2);
        dc.setColor(Graphics.COLOR_DK_RED, Graphics.COLOR_WHITE);
        dc.drawLine(0, blockHeight, w, blockHeight);
        dc.drawLine(0, blockHeight * 2, w, blockHeight * 2);

        dc.setColor(Graphics.COLOR_DK_RED, Graphics.COLOR_WHITE);
        dc.drawText(
            w/2,
            blockHeight / 2,
            Graphics.FONT_SYSTEM_XTINY,
            "CONNECTION",
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.drawText(
            w/2,
            h/2,
            Graphics.FONT_SYSTEM_TINY,
            msg,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));

    }
}

/*
 * Back key dismisses the error view. VesselModel's errorViewVisible flag is
 * cleared so a subsequent failed poll can re-push the view; if the user
 * just wants to read the error once, they can hit back and only see it
 * again when the error recurs.
 */
class ErrorViewDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Lang.Boolean {
        vessel.dismissErrorView();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        return true;
    }
}
