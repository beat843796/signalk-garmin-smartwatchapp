/*
 * VesselViewLoopFactory.mc
 * ViewLoopFactory for the main connected-state UI. Three pages,
 * swipeable with UP/DOWN:
 *   0: TempView       — large water-temperature read-out
 *   1: VesselDataView — three-row SOG / AWA+AWS / DBT dashboard
 *   2: StatusView     — SignalK connection status; select pushes the
 *                       request-access view when state is NOT_AUTH
 *
 * VesselDataView is at index 1 so that data-page-redirect (called on
 * data-poll recovery) lands the user there in the middle of the loop —
 * Temp is one swipe up, Status one swipe down.
 *
 * Each page returns its own BehaviorDelegate (select/menu/etc.). The
 * enclosing WatchUi.ViewLoopDelegate handles the UP/DOWN page navigation.
 */

using Toybox.WatchUi;
using Toybox.Lang;

/*
 * Page indices in the ViewLoop. Keep in sync with
 * VesselViewLoopFactory.getView. Used by callers that need to land on
 * a specific page (e.g. data-poll recovery / failure redirects).
 */
const VIEWLOOP_PAGE_TEMP = 0;
const VIEWLOOP_PAGE_DATA = 1;
const VIEWLOOP_PAGE_STATUS = 2;

class VesselViewLoopFactory extends WatchUi.ViewLoopFactory {

    function initialize() {
        ViewLoopFactory.initialize();
    }

    function getSize() as Lang.Number {
        return 3;
    }

    function getView(page as Lang.Number) as [ WatchUi.ViewLoopFactory.Views ] or [ WatchUi.ViewLoopFactory.Views, WatchUi.ViewLoopFactory.Delegates ] {
        if (page == VIEWLOOP_PAGE_DATA) {
            return [new VesselDataView(), new VesselDataViewDelegate()];
        }
        if (page == VIEWLOOP_PAGE_STATUS) {
            return [new StatusView(), new StatusViewDelegate()];
        }
        return [new TempView(), new TempViewDelegate()];
    }
}

/*
 * Convenience constructor for the ViewLoop + its delegate. Caller
 * specifies which page to land on. ViewLoop has no programmatic
 * setPage method — the only way to land on a non-zero page is to
 * construct a fresh loop with `:page => N` and switchToView. So this
 * builder is also what RESTVesselConnect uses to redirect after a
 * data-poll failure.
 */
module VesselViewLoop {

    function build(initialPage as Lang.Number) as Lang.Array {
        var loop = new WatchUi.ViewLoop(
            new VesselViewLoopFactory(),
            { :page => initialPage, :wrap => true });
        return [loop, new WatchUi.ViewLoopDelegate(loop)];
    }
}
