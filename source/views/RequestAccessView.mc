/*
 * RequestAccessView.mc
 * Pushed on top of StatusView when the user picks "Request Access"
 * from the Config menu. The caller is responsible for firing
 * `vessel.requestAccess()` before push, so this view always opens
 * straight into the spinner; there's no intermediate "tap to start"
 * prompt anymore.
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
using Toybox.Lang;
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
        /*
         * If the user backs out manually, cancel any pending pop so
         * the timer can't fire against a now-destroyed view.
         */
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

        /*
         * Terminal state — auth flow is over. The APPROVED / DENIED
         * toast is fired from RESTVesselConnect.finalize* so it shows
         * even when the user backed out of this view before the auth
         * flow finished. Schedule the pop on the next event-loop tick
         * (popView from inside onUpdate is fragile on real devices).
         */
        if (!popScheduled) {
            popScheduled = true;
            popTimer = new Timer.Timer();
            popTimer.start(method(:doPop), 50, false);
        }
        /*
         * Keep showing the spinner for the brief deferred-pop window
         * so the screen doesn't flicker to blank.
         */
        drawRequestingOverlay(dc);
    }

    function doPop() as Void {
        popTimer = null;
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    /*
     * "Requesting..." screen shown while the access-request POST is
     * in flight or while polling for admin approval. Delegates to the
     * shared spinner helper; RESTVesselConnect drives redraws via its
     * spinner timer.
     */
    private function drawRequestingOverlay(dc) {
        Utils.drawSpinner(dc, WatchUi.loadResource(Rez.Strings.SpinnerPendingApproval) as Lang.String);
    }
}
