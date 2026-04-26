/*
 * AuthConfigView.mc
 * Hosts the RequestAccessView — pushed on top of StatusView when the
 * user picks "Request Access" from the Config menu. The caller is
 * responsible for firing `vessel.requestAccess()` before push, so this
 * view always opens straight into the spinner; there's no
 * intermediate "tap to start" prompt anymore.
 *
 * Lifecycle:
 *   - opens with the rotating spinner; spans the access-request POST
 *     and the polling phase
 *   - on terminal state:
 *       AUTH_CONNECTED → toast "APPROVED" + auto-pop
 *       AUTH_DENIED    → toast "DENIED"   + auto-pop
 *       any other      → auto-pop (StatusView underneath shows the
 *                        new connectivity state)
 *
 * No custom delegate — back is handled by the default BehaviorDelegate;
 * select / menu are no-ops while the request is in flight.
 */

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Timer;

using Utilities as Utils;

class RequestAccessView extends WatchUi.View {

    /*
     * One-shot timer used to defer popView() out of the onUpdate call
     * stack. Calling popView from inside View.onUpdate crashes on
     * real device firmware (the render pipeline and view-stack
     * mutation race). The simulator is permissive about it, real
     * devices are not.
     */
    private var popTimer;
    private var popScheduled = false;

    function initialize() {
        View.initialize();
    }

    function onHide() {
        // If the user backs out manually, cancel any pending pop so
        // the timer can't fire against a now-destroyed view.
        if (popTimer != null) {
            popTimer.stop();
            popTimer = null;
        }
    }

    function onUpdate(dc) {
        View.onUpdate(dc);

        var state = vessel.getAuthState();

        if (vessel.isAccessRequestInFlight() || state == AUTH_PENDING) {
            drawRequestingOverlay(dc);
            return;
        }

        // Terminal state — auth flow is over. The APPROVED / DENIED
        // toast is fired from RESTVesselConnect.finalize* so it shows
        // even when the user backed out of this view before the auth
        // flow finished. Schedule the pop on the next event-loop tick
        // (popView from inside onUpdate is fragile on real devices).
        if (!popScheduled) {
            popScheduled = true;
            popTimer = new Timer.Timer();
            popTimer.start(method(:doPop), 50, false);
        }
        // Keep showing the spinner for the brief deferred-pop window
        // so the screen doesn't flicker to blank.
        drawRequestingOverlay(dc);
    }

    function doPop() as Void {
        popTimer = null;
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    /*
     * "Requesting..." screen shown while the access-request POST is
     * in flight or while polling for admin approval. CIQ doesn't ship
     * an indeterminate-progress widget, so we roll our own: a 90° arc
     * rotating around a central point. RESTVesselConnect drives
     * redraws via its spinner timer.
     */
    private function drawRequestingOverlay(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var r = (h * 0.05).toNumber();

        var degrees = (System.getTimer() / 3) % 360;
        var start = 360 - degrees;
        var end = (start - 90 + 360) % 360;

        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_BLACK);
        dc.setPenWidth(5);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, start, end);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2,
            h * 0.65,
            Graphics.FONT_SYSTEM_TINY,
            "Pending Approval",
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));

    }
}
