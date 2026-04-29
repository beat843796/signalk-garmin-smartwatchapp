/*
 * ConnectionTypePicker.mc
 * Menu2 + delegate for the "pick connection type" UI. Two contexts:
 *
 *   1. First-launch enforcement: StatusView.onShow auto-pushes this
 *      menu when the persisted ConnectionType is NONE. Back in this
 *      mode exits the app (per UX requirement — the user MUST pick).
 *
 *   2. User-initiated change: pushed from the StatusView Config menu
 *      via the "Set Connection Type" item. Back here pops back to the
 *      Config menu / StatusView.
 *
 * The two contexts share the same Menu2 — the delegate's `firstLaunch`
 * flag flips the back behaviour. Selecting an item swaps the active
 * transport via TransportFactory + VesselModel.attachTransport, then
 * pops the menu (and any wrapping Config menu) so the user lands on a
 * StatusView reflecting the new pick.
 */

using Toybox.WatchUi;
using Toybox.Lang;
using Toybox.System;

module ConnectionTypePicker {

    /*
     * Pushes the picker on top of the current view. `firstLaunch`
     * controls back behaviour:
     *   true  — ConnectionType is currently NONE and the user must
     *           pick; back exits the app.
     *   false — user opened it from the Config menu to change their
     *           pick; back pops normally.
     */
    function push(firstLaunch as Lang.Boolean) as Void {
        var menu = new WatchUi.Menu2({:title => Rez.Strings.MenuConnection});
        var current = TransportFactory.getStoredType();
        var restSubtitle = current.equals(ConnectionType.REST) ? Rez.Strings.LabelActive : null;
        var bleSubtitle = current.equals(ConnectionType.BLE) ? Rez.Strings.LabelActive : null;
        menu.addItem(new WatchUi.MenuItem(
            Rez.Strings.TitleSignalKHttps, restSubtitle, :pickRest, null));
        menu.addItem(new WatchUi.MenuItem(
            Rez.Strings.TitleSignalKBle, bleSubtitle, :pickBle, null));
        WatchUi.pushView(
            menu,
            new ConnectionTypePickerDelegate(firstLaunch),
            WatchUi.SLIDE_UP);
    }
}

class ConnectionTypePickerDelegate extends WatchUi.Menu2InputDelegate {

    private var firstLaunch;

    function initialize(firstLaunchArg as Lang.Boolean) {
        Menu2InputDelegate.initialize();
        firstLaunch = firstLaunchArg;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var newType;
        if (id == :pickRest) {
            newType = ConnectionType.REST;
        } else if (id == :pickBle) {
            newType = ConnectionType.BLE;
        } else {
            return;
        }

        Log.d("[Picker] user selected " + newType);

        var current = TransportFactory.getStoredType();
        if (!current.equals(newType)) {
            TransportFactory.setStoredType(newType);
            vessel.attachTransport(TransportFactory.build(newType, vessel));
            vessel.persistGlanceSnapshot();

            /*
             * Switching TO BLE: always route through the foreground
             * spinner so the user sees the connect attempt and lands
             * on the data view on success (BleConnectView.onConnected
             * switchToViews to it). Dropping back to a "BLE Not
             * Connected" StatusView would force the user to open the
             * Config menu and tap Connect anyway — pointless extra
             * step. Works for both previously-paired devices (scan
             * finds them quickly) and first-time pairings.
             */
            if (newType.equals(ConnectionType.BLE)) {
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                WatchUi.pushView(
                    new BleConnectView(),
                    new BleConnectViewDelegate(),
                    WatchUi.SLIDE_LEFT);
                return;
            }

            vessel.startUpdatingData();

            /*
             * Switching TO REST with valid URL + token: land directly
             * on the data view. getStatusKind == CONN_CONNECTED at this
             * moment means baseURL is set and a token is persisted; the
             * data view shows last-known fields (currently "—" after
             * resetVesselData) until the first poll lands. If the
             * token turns out to be stale, the standard 401/403
             * redirect bounces the user to Status.
             */
            if (newType.equals(ConnectionType.REST)
                    && vessel.getStatusKind() == CONN_CONNECTED) {
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                var pair = VesselViewLoop.build(VIEWLOOP_PAGE_DATA);
                WatchUi.switchToView(pair[0], pair[1], WatchUi.SLIDE_RIGHT);
                return;
            }
        }

        /*
         * Same type re-picked, or new type isn't yet usable (no token
         * / no saved pairing) — pop back to whatever was below the
         * picker (StatusView, or the Config menu).
         */
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
    }

    /*
     * First-launch back: nothing is configured yet, the user has been
     * told they must pick. Exit the app rather than dropping them onto
     * a StatusView with no transport.
     *
     * Subsequent invocations (user changing their pick): regular pop.
     */
    function onBack() as Void {
        if (firstLaunch) {
            Log.d("[Picker] first-launch back — exiting app");
            System.exit();
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
