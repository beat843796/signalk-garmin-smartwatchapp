/*
 * VesselConnectApp.mc
 * App entry point. AppBase lifecycle hooks; picks the right initial view
 * based on auth state and exposes the glance view for the glance carousel.
 *
 * IMPORTANT: `vessel` is constructed lazily in getInitialView() — which is
 * the ONLY lifecycle hook guaranteed to run in the main-app slice. The
 * glance slice runs initialize() and onStart() too on some devices, and
 * `new VesselModel()` from those hooks crashes with "Class not available
 * to 'Glance'" because VesselModel isn't in the glance compile slice.
 */

using Toybox.Application;
using Toybox.System;
using Toybox.WatchUi;
using Toybox.Lang;

/*
 * Singleton SignalK model. Constructed lazily on first main-app getInitialView
 * call; stays null in glance context. Read by every main-app view.
 */
var vessel = null;

class VesselConnectApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
        System.println("[App] initialize");
    }

    /*
     * onStart runs in BOTH main-app and glance contexts on some devices, so
     * we can't touch VesselModel here. Construction happens later in
     * getInitialView (main-app only).
     */
    function onStart(state) {
        System.println("[App] onStart");
    }

    function onStop(state) {
        System.println("[App] onStop");
        if (vessel != null) {
            vessel.stopUpdatingData();
        }
    }

    function onSettingsChanged() {
        if (vessel != null) {
            vessel.stopUpdatingData();
            vessel.configureSignalK();
            vessel.startUpdatingData();
            /*
             * Nudge the currently-visible view so a URL change from "none"
             * to "set" (or vice versa) is reflected immediately without
             * waiting for the next natural redraw.
             */
            WatchUi.requestUpdate();
        }
    }

    /*
     * Called only when the app launches as a full watch-app (not as a
     * glance). Safe to construct VesselModel here because we know we
     * are in the main-app compile slice.
     *
     * Always returns the ViewLoop. The initial page depends on the
     * connectivity state: CONNECTED lands on the data dashboard; any
     * other state lands on the Status page so the user sees the
     * connection issue immediately.
     */
    function getInitialView() {
        System.println("[App] getInitialView");
        if (vessel == null) {
            System.println("[App] constructing VesselModel");
            vessel = new VesselModel();
        }
        vessel.startUpdatingData();

        var conn = vessel.getConnectivity();
        System.println("[App] connectivity=" + conn);
        var initialPage = (conn == CONN_CONNECTED) ? VIEWLOOP_PAGE_DATA : VIEWLOOP_PAGE_STATUS;
        return VesselViewLoop.build(initialPage);
    }

    /*
     * Glance carousel entry — runs in the glance compile slice with a much
     * smaller memory budget. Does not touch VesselModel; SignalKGlanceView
     * reads last-known state directly from Application.Storage.
     */
    (:glance)
    function getGlanceView() {
        return [new SignalKGlanceView()];
    }
}
