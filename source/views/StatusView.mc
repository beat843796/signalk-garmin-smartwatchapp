/*
 * StatusView.mc
 * The "config" page in the ViewLoop. Reflects exactly the picked
 * transport — REST or BLE, never both. The label/colour combination
 * comes straight off the active VesselConnect:
 *
 *   title    = vessel.connect.getDisplayTitle()  ("SignalK Server" / "BLE")
 *   subtitle = vessel.connect.getStatusLabel()   (URL / device name / state)
 *
 * Subtitle colour is derived from getStatusKind():
 *   CONNECTED     → green
 *   CONNECTING    → white
 *   PENDING       → blue
 *   anything else → red
 *
 * On first launch (ConnectionType == NONE) onShow auto-pushes the
 * connection-type picker so the user can't reach an empty StatusView.
 *
 * Select / menu opens the Config menu with state-driven items:
 *   - SignalK / Request Access      (REST + CONN_NOT_AUTH)
 *   - BLE / Connect | Cancel | Disconnect (BLE, label depends on state)
 *   - Change Connection Type        (always)
 */

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;

class StatusView extends WatchUi.View {

    /*
     * Set true when onShow has already auto-pushed the first-launch
     * picker so we don't push it again on every redraw / re-entry.
     */
    private var pickerPushed = false;

    function initialize() {
        View.initialize();
    }

    /*
     * Stop both transports' data flow while the user is on the
     * connection-management screen — there's nothing rendered here
     * that needs live data, and continuing to poll burns the radio
     * for no reason. The displayed status label uses the last-known
     * state from the transport. Also auto-opens the connection-type
     * picker on first launch.
     */
    function onShow() as Void {
        if (vessel == null) {
            return;
        }
        vessel.pausePolling();
        vessel.endDataStreaming();

        if (!pickerPushed
                && TransportFactory.getStoredType().equals(ConnectionType.NONE)) {
            pickerPushed = true;
            ConnectionTypePicker.push(true);
        }
    }

    /*
     * Resume the recurring data flow when the user navigates away
     * (swipe to data view, push Config menu, push picker, ...). The
     * data views call beginDataStreaming themselves on their own
     * onShow, so BLE picks up where it left off; REST's recurring
     * poll re-arms via vessel.resumePolling().
     */
    function onHide() as Void {
        if (vessel != null) {
            vessel.resumePolling();
        }
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        var kind = vessel.getStatusKind();
        if (kind == CONN_NONE) {
            /*
             * Picker is pushed on top — render nothing meaningful here;
             * the picker covers the screen anyway.
             */
            return;
        }

        var title = vessel.connect.getDisplayTitle();
        var subtitle = vessel.connect.getStatusLabel();
        var subtitleColor = colorForStatus(kind);

        /*
         * Long URLs need a smaller font to fit the round display; the
         * rest of the labels are short enough for FONT_SYSTEM_TINY.
         */
        var subtitleFont = (kind == CONN_CONNECTED && subtitle.length() > 16)
            ? Graphics.FONT_SYSTEM_XTINY
            : Graphics.FONT_SYSTEM_TINY;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2,
            h * 0.40,
            Graphics.FONT_SYSTEM_TINY,
            title,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));

        dc.setColor(subtitleColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2,
            h * 0.58,
            subtitleFont,
            subtitle,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
    }

    /*
     * Maps the unified CONN_* status onto the subtitle colour. Green
     * for healthy, blue for in-progress, red for everything else (errors
     * + idle states); gray for the "not configured" cases that aren't
     * really errors.
     */
    private function colorForStatus(kind as Lang.Number) as Lang.Number {
        if (kind == CONN_CONNECTED)    { return Graphics.COLOR_GREEN; }
        if (kind == CONN_CONNECTING)   { return Graphics.COLOR_WHITE; }
        if (kind == CONN_PENDING)      { return Graphics.COLOR_BLUE; }
        if (kind == CONN_NO_URL)       { return Graphics.COLOR_LT_GRAY; }
        if (kind == CONN_DISCONNECTED) { return Graphics.COLOR_RED; }
        return Graphics.COLOR_RED;
    }
}

class StatusViewDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Lang.Boolean {
        return openConfigMenu();
    }

    function onMenu() as Lang.Boolean {
        return openConfigMenu();
    }

    /*
     * Builds and pushes the Config menu. Items are filtered by the
     * active transport and its current state so the user only sees
     * actionable options.
     */
    private function openConfigMenu() as Lang.Boolean {
        /*
         * Don't allow opening the config menu before the user has
         * picked a connection type — the picker has the floor.
         */
        if (TransportFactory.getStoredType().equals(ConnectionType.NONE)) {
            ConnectionTypePicker.push(true);
            return true;
        }

        var menu = new WatchUi.Menu2({:title => Rez.Strings.MenuConfig});
        var connect = vessel.connect;

        // REST: "Request Access" only when actionable.
        if (connect instanceof RESTVesselConnect
                && vessel.getStatusKind() == CONN_NOT_AUTH) {
            menu.addItem(new WatchUi.MenuItem(
                Rez.Strings.MenuItemSignalK, Rez.Strings.MenuActionRequestAccess, :requestAccess, null));
        }

        /*
         * BLE: state-driven item label. CONNECTING shows "Cancel" so
         * the user can stop a silent autoconnect scan; the action is
         * the same disconnect handler, which clears the sticky flag.
         */
        if (connect instanceof BleVesselConnect) {
            var kind = vessel.getStatusKind();
            if (kind == CONN_CONNECTED) {
                menu.addItem(new WatchUi.MenuItem(
                    Rez.Strings.TitleBle, Rez.Strings.MenuActionDisconnect, :bleDisconnect, null));
            } else if (kind == CONN_CONNECTING) {
                menu.addItem(new WatchUi.MenuItem(
                    Rez.Strings.TitleBle, Rez.Strings.MenuActionCancel, :bleDisconnect, null));
            } else {
                menu.addItem(new WatchUi.MenuItem(
                    Rez.Strings.TitleBle, Rez.Strings.MenuActionConnect, :bleConnect, null));
            }
        }

        /*
         * Menu only opens when a type is already set (the NONE case is
         * intercepted above and routes to the picker), so the label is
         * always "Change..." here, never "Set...".
         */
        menu.addItem(new WatchUi.MenuItem(
            Rez.Strings.MenuItemChangeConnectionType, null, :setConnectionType, null));

        menu.addItem(new WatchUi.MenuItem(
            Rez.Strings.MenuItemHelp, null, :help, null));

        WatchUi.pushView(menu, new ConfigMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
}

/*
 * Menu2 input delegate for the Config menu. Each item ID maps to a
 * specific action; back closes the menu without side effects.
 */
class ConfigMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :requestAccess) {
            /*
             * Pop the menu first so the request-access view doesn't
             * stack on top of it.
             */
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            /*
             * Recovering from DENIED: the server has the clientId
             * burned — wipe local state so a fresh one is generated
             * on the upcoming requestAccess() call.
             */
            if (vessel.getAuthState() == AUTH_DENIED) {
                vessel.resetAccessRequest();
            }
            /*
             * Fire the request *before* pushing the view so the view
             * opens with the spinner already in flight (no flash of
             * a "tap to start" prompt).
             */
            vessel.requestAccess();
            WatchUi.pushView(
                new RequestAccessView(),
                new WatchUi.BehaviorDelegate(),
                WatchUi.SLIDE_LEFT);
        } else if (id == :bleConnect) {
            // Pop the menu first so the spinner view replaces it cleanly.
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.pushView(
                new BleConnectView(),
                new BleConnectViewDelegate(),
                WatchUi.SLIDE_LEFT);
        } else if (id == :bleDisconnect) {
            System.println("[BLE] menu disconnect");
            vessel.connect.disconnect();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :setConnectionType) {
            /*
             * Pop the Config menu first so the picker sits directly on
             * top of StatusView. After picking, the picker pops itself
             * and the user lands back on StatusView immediately —
             * without an extra back-press through a stale Config menu.
             */
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            ConnectionTypePicker.push(false);
        } else if (id == :help) {
            /*
             * Push HelpView ON TOP of the Config menu so back from
             * HelpView returns to the menu (per UX spec). The Config
             * menu is preserved underneath.
             */
            WatchUi.pushView(
                new HelpView(),
                new HelpViewDelegate(),
                WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
