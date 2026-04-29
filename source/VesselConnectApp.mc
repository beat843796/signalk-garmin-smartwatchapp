/*
 * VesselConnectApp.mc
 * App entry point. AppBase lifecycle hooks; constructs the global
 * VesselModel and wires in the user-picked transport via TransportFactory.
 *
 * IMPORTANT: `vessel` is constructed lazily in getInitialView() — the
 * ONLY lifecycle hook guaranteed to run in the main-app slice. The
 * glance slice runs initialize() and onStart() too on some devices, and
 * `new VesselModel()` from those hooks crashes with "Class not available
 * to 'Glance'" because VesselModel isn't in the glance compile slice.
 */

using Toybox.Application;
using Toybox.System;
using Toybox.WatchUi;
using Toybox.Lang;

/*
 * Singleton SignalK model. Constructed lazily on first main-app
 * getInitialView call; stays null in glance context. Read by every
 * main-app view. The active transport (REST / BLE / Null) is held on
 * vessel.connect.
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

    /*
     * Settings change — only meaningful for REST (baseurl_prop edit).
     * VesselModel.configureSignalK is itself transport-aware (no-op
     * for non-REST), so calling unconditionally is safe.
     */
    function onSettingsChanged() {
        if (vessel != null) {
            vessel.stopUpdatingData();
            vessel.configureSignalK();
            vessel.startUpdatingData();
            WatchUi.requestUpdate();
        }
    }

    /*
     * Called only when the app launches as a full watch-app (not as a
     * glance). Constructs VesselModel and attaches the transport
     * matching the persisted ConnectionType. Always lands on the
     * ViewLoop:
     *   - When type is NONE, StatusView's onShow auto-pushes the
     *     connection-type picker so the user can't miss the choice.
     *   - When type is REST/BLE and we already have a live connection,
     *     land on the data page.
     *   - Otherwise land on Status so the user sees what's needed
     *     (set URL, request access, connect BLE, ...).
     */
    function getInitialView() {
        System.println("[App] getInitialView");
        if (vessel == null) {
            System.println("[App] constructing VesselModel");
            vessel = new VesselModel();
        }

        var type = TransportFactory.getStoredType();
        System.println("[App] connection type=" + type);
        vessel.attachTransport(TransportFactory.build(type, vessel));
        vessel.startUpdatingData();

        /*
         * Once the user has picked a transport, default to the data
         * dashboard — even if the link isn't up yet (data view shows
         * "—" placeholders until data flows). Only the never-picked
         * case lands on Status so the auto-pushed picker is the user's
         * very first interaction.
         */
        var initialPage = type.equals(ConnectionType.NONE)
            ? VIEWLOOP_PAGE_STATUS
            : VIEWLOOP_PAGE_DATA;
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
