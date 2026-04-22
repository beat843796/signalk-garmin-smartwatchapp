/*
 * AuthConfigView.mc
 * Single view for the device-access-request lifecycle. Renders differently
 * based on `vessel.authState`:
 *
 *   NO_URL          "Setup"       Open Garmin Connect app    [NOT SET]
 *   NEEDS_REQUEST   "SignalK"     Tap to request              [FRESH]
 *                                 access from
 *                                 <server url>
 *   PENDING         "Waiting"     for approval on admin      [PENDING]
 *   DENIED          "Denied"      Tap to try again           [DENIED]
 *   CONNECTED       "Granted"     Tap to continue            [CONNECTED] + ✓
 *
 * Benefits of unifying:
 *   - DENIED → NEEDS_REQUEST → request took two taps; now one (select in
 *     DENIED does reset + request atomically).
 *   - Approval lands on an acknowledgement screen instead of teleporting
 *     the user straight to live data — one more tap to commit, but the
 *     grant moment is visible.
 *   - State transitions within the auth flow don't require switchToView;
 *     the same view re-renders with new content when VesselModel calls
 *     WatchUi.requestUpdate().
 *
 * Button behavior (delegate below):
 *   select  - NEEDS_REQUEST: fire request
 *             PENDING:       no-op
 *             DENIED:        reset + fire request in one action
 *             CONNECTED:     switch to VesselDataView + start data poll
 *   menu    - PENDING only: open Menu2 with "Reset request" (escape hatch
 *             to abandon a pending submission; the old request stays
 *             orphaned on the server until admin denies it — no
 *             client-side cancel endpoint exists in SignalK).
 */

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;

using Utilities as Utils;

class AuthConfigView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);

        /*
         * Only render the spinner overlay once the request has been in
         * flight for longer than VesselModel.spinnerShowAfterMs — fast
         * responses complete before the spinner is shown, avoiding a
         * flash of the loading screen.
         */
        if (vessel.isSpinnerVisible()) {
            drawRequestingOverlay(dc);
            return;
        }

        var state = vessel.authState;

        if (state == AUTH_NO_URL) {
            Utils.drawStatusScreen(dc, "Setup", Graphics.COLOR_DK_RED, "Set SignalK URL\nin Garmin Connect\napp settings");
            //drawStateChip(dc, "NOT SET", Graphics.COLOR_DK_RED);
        } else if (state == AUTH_PENDING) {
            Utils.drawStatusScreen(dc, "Waiting", Graphics.COLOR_DK_BLUE, "for approval on\nSignalK admin");
            drawDeviceLabel(dc);
            //drawStateChip(dc, "PENDING", Graphics.COLOR_DK_BLUE);
        } else if (state == AUTH_DENIED) {
            Utils.drawStatusScreen(dc, "Denied", Graphics.COLOR_DK_RED, "Tap to try again");
            //drawStateChip(dc, "DENIED", Graphics.COLOR_DK_RED);
        } else if (state == AUTH_CONNECTED) {
            Utils.drawStatusScreen(dc, "Granted", Graphics.COLOR_DK_GREEN, "Tap to continue");
            drawCheckmark(dc);
            //drawStateChip(dc, "CONNECTED", Graphics.COLOR_DK_GREEN);
        } else {
            // NEEDS_REQUEST / ERROR / anything else not explicitly handled.
            Utils.drawStatusScreen(dc, "SignalK", Graphics.COLOR_DK_BLUE, "Tap to request\naccess from");
            drawServerUrl(dc);
           // drawStateChip(dc, "FRESH", Graphics.COLOR_DK_GRAY);
        }
    }

    /*
     * Shows the configured SignalK URL in small text so the user knows
     * which server the tap will hit. Only meaningful in NEEDS_REQUEST
     * state; sits at the same y-offset as PendingView's device label so
     * the layout stays consistent across states.
     */
    function drawServerUrl(dc) {
        var url = vessel.getBaseURL();
        if (url == null) {
            return;
        }
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_WHITE);
        dc.drawText(
            dc.getWidth() / 2,
            dc.getHeight() - 50,
            Graphics.FONT_SYSTEM_XTINY,
            url,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    /*
     * Small device-identifier line so the user knows which row to approve
     * in the SignalK admin UI. Only meaningful in PENDING state.
     */
    function drawDeviceLabel(dc) {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_WHITE);
        dc.drawText(
            dc.getWidth() / 2,
            dc.getHeight() - 50,
            Graphics.FONT_SYSTEM_XTINY,
            vessel.getDeviceDescription(),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

 

    /*
     * "Requesting..." screen shown while the access-request POST is in
     * flight. Connect IQ doesn't ship an indeterminate-progress widget, so
     * we roll our own: a 90° arc rotating around a central point.
     * VesselModel drives redraws at ~150 ms cadence via its spinner timer.
     */
    function drawRequestingOverlay(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var r = (h * 0.05).toNumber();

        /*
         * Rotate one full turn per second. System.getTimer() returns ms
         * since boot; we turn that into a 0..359 angle.
         */
        var degrees = (System.getTimer() / 3) % 360;
        var start = 360 - degrees;
        var end = (start - 90 + 360) % 360;

        dc.setColor(Graphics.COLOR_DK_BLUE, Graphics.COLOR_WHITE);
        dc.setPenWidth(5);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, start, end);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.drawText(
            w / 2,
            h * 0.65,
            Graphics.FONT_SYSTEM_TINY,
            "Requesting...",
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
    }

    /*
     * Draws a green check mark in the top area of the screen (above the
     * "Granted" title). Built from two straight strokes so we don't rely on
     * a font containing the Unicode check glyph.
     */
    function drawCheckmark(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h * 0.12;
        var size = h * 0.06;

        dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_WHITE);
        dc.setPenWidth(5);
        // Short down-right stroke: from upper-left to the tick's corner.
        dc.drawLine(cx - size, cy, cx - size * 0.2, cy + size * 0.7);
        // Longer up-right stroke: corner to upper-right.
        dc.drawLine(cx - size * 0.2, cy + size * 0.7, cx + size, cy - size * 0.8);
    }
}

class AuthConfigViewDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Lang.Boolean {
        var state = vessel.authState;
        if (state == AUTH_CONNECTED) {
            // User acknowledged the grant — enter the main app.
            vessel.startUpdatingData();
            WatchUi.switchToView(new VesselDataView(), new VesselDataViewDelegate(), WatchUi.SLIDE_LEFT);
        } else if (state == AUTH_DENIED) {
            /*
             * Single-tap recovery: wipe the burned clientId, generate a
             * fresh one, fire the new request in one go.
             */
            vessel.resetAccessRequest();
            vessel.requestAccess();
        } else if (state == AUTH_NO_URL || state == AUTH_PENDING) {
            /*
             * NO_URL: nothing the user can do on the watch — must set URL
             *   in the phone's Garmin Connect app.
             * PENDING: can't progress further without admin action.
             * Both are no-ops on select.
             */
        } else {
            // NEEDS_REQUEST / ERROR / residual states.
            vessel.requestAccess();
        }
        return true;
    }

    function onMenu() as Lang.Boolean {
        if (vessel.authState == AUTH_PENDING) {
            var menu = new WatchUi.Menu2({:title => "Pending"});
            menu.addItem(new WatchUi.MenuItem("Reset request", null, :reset, null));
            WatchUi.pushView(menu, new AuthConfigMenuDelegate(), WatchUi.SLIDE_UP);
        }
        return true;
    }
}

// Menu2 delegate for the "Reset request" action from PENDING state.
class AuthConfigMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :reset) {
            vessel.resetAccessRequest();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.requestUpdate();
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
