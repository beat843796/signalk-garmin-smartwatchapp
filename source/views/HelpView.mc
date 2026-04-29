/*
 * HelpView.mc
 * Full-screen help page pushed from the StatusView Config menu's
 * "Help" item. Renders a centred QR code that encodes the project's
 * homepage URL (https://www.cb84.io) so users can scan it with a
 * phone to read setup docs, sibling-plugin links, etc.
 *
 * The QR PNG is shipped as a static drawable (see
 * resources/drawables/qr_help.png) — generated offline from the URL
 * and committed. Regenerate when the encoded URL changes.
 *
 * Back pops the view, returning to the Config menu.
 */

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;

class HelpView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        var qr = WatchUi.loadResource(Rez.Drawables.QrHelp);
        var qrW = qr.getWidth();
        var qrH = qr.getHeight();

        /*
         * Centre the QR on the screen. Scanners read the bitmap as-is
         * — no scaling, the source PNG already includes a quiet zone.
         */
        dc.drawBitmap((w - qrW) / 2, (h - qrH) / 2, qr);
    }
}

class HelpViewDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Lang.Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
