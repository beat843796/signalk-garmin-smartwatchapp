/*
 * StatusView.mc
 * The "config" page in the ViewLoop. Always-on dashboard for the
 * SignalK connection state — title is "SignalK", subtitle is the
 * current CONN_* state's user-facing label. Server URL footer.
 *
 * Select / menu opens a Menu2 ("Config") with:
 *   - "SignalK / Request Access"  (only when CONN_NOT_AUTH; opens the
 *                                  device-access-request flow)
 *   - "BLE / Search devices"      (stub — logs only for now)
 *   - "Boat Type / Sailboat|Motor" (toggles + persists; later affects
 *                                  which fields VesselDataView shows)
 */

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;

class StatusView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);

        var conn = vessel.getConnectivity();
        var label = "SignalK";
        var subtitle;
        var color;

        if (conn == CONN_CONNECTED) {
            subtitle = "CONNECTED";
            color = Graphics.COLOR_GREEN;
        } else if (conn == CONN_NO_URL) {
            subtitle = "NO URL";
            color = Graphics.COLOR_LT_GRAY;
        } else if (conn == CONN_NO_HTTPS) {
            subtitle = "NO HTTPS";
            color = Graphics.COLOR_RED;
        } else if (conn == CONN_NOT_REACHABLE) {
            subtitle = "NOT REACHABLE";
            color = Graphics.COLOR_RED;
        } else if (conn == CONN_NOT_AUTH) {
            subtitle = "NOT AUTHENTICATED";
            color = Graphics.COLOR_RED;
        } else if (conn == CONN_PENDING) {
            subtitle = "PENDING";
            color = Graphics.COLOR_BLUE;
        } else if (conn == CONN_MISSING_PLUGIN) {
            subtitle = "PLUGIN MISSING";
            color = Graphics.COLOR_RED;
        } else {
            subtitle = "UNKNOWN";
            color = Graphics.COLOR_LT_GRAY;
        }

        drawStatusScreen(dc, label, color, subtitle);
        drawServerUrlFooter(dc, vessel.getBaseURL());
    }

    /*
     * Title in the upper third (coloured per state), body in the
     * lower half (white). Black bg, sized proportionally so the
     * layout looks right across 240-454 px round watches.
     */
    private function drawStatusScreen(dc, title, titleColor, body) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(titleColor, Graphics.COLOR_BLACK);
        dc.drawText(
            w / 2,
            h * 0.2,
            Graphics.FONT_SYSTEM_MEDIUM,
            title,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2,
            h * 0.35,
            Graphics.FONT_SYSTEM_TINY,
            body,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
    }

    // Small grey URL line near the bottom. Null-safe.
    private function drawServerUrlFooter(dc, url) {
        if (url == null) {
            return;
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            dc.getWidth() / 2,
            dc.getHeight() / 2 - 20,
            Graphics.FONT_SYSTEM_XTINY,
            url,
            Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class StatusViewDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    /*
     * Both select and menu open the Config menu — same effect either
     * way so the user doesn't have to remember which button.
     */
    function onSelect() as Lang.Boolean {
        return openConfigMenu();
    }

    function onMenu() as Lang.Boolean {
        return openConfigMenu();
    }

    private function openConfigMenu() as Lang.Boolean {
        var menu = new WatchUi.Menu2({:title => "Config"});

        // Item 1: Request Access — only when actionable.
        if (vessel.getConnectivity() == CONN_NOT_AUTH) {
            menu.addItem(new WatchUi.MenuItem(
                "SignalK", "Request Access", :requestAccess, null));
        }

        // Item 2: BLE — stub for now.
        menu.addItem(new WatchUi.MenuItem(
            "BLE", "Search devices", :bleSearch, null));

        // Item 3: Boat Type — toggle Sailboat / Motor in place.
        menu.addItem(new WatchUi.MenuItem(
            "Boat Type",
            ConfigMenu.labelForBoatType(vessel.getBoatType()),
            :boatType,
            null));

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
            // Pop the menu first so the request-access view doesn't
            // stack on top of it.
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            // If we're recovering from DENIED, the server has the
            // clientId burned — wipe it so a fresh one is generated
            // on the upcoming requestAccess() call.
            if (vessel.getAuthState() == AUTH_DENIED) {
                vessel.resetAccessRequest();
            }
            // Fire the request *before* pushing the view so the view
            // opens with the spinner already in flight (no flash of
            // a "tap to start" prompt).
            vessel.requestAccess();
            WatchUi.pushView(
                new RequestAccessView(),
                new WatchUi.BehaviorDelegate(),
                WatchUi.SLIDE_LEFT);
        } else if (id == :bleSearch) {
            // Stub — will hook into BLEVesselConnect when that's wired
            // up. Logging only for now so we can see it on the simulator.
            System.println("[Config] BLE search devices — not implemented");
        } else if (id == :boatType) {
            var current = vessel.getBoatType();
            var next = current.equals(BoatType.SAIL) ? BoatType.MOTOR : BoatType.SAIL;
            vessel.setBoatType(next);
            item.setSubLabel(ConfigMenu.labelForBoatType(next));
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

/*
 * Small helpers for the Config menu — kept here (close to the menu
 * code) rather than in Utilities since they're not pure unit-conversion
 * primitives.
 */
module ConfigMenu {
    function labelForBoatType(type as Lang.String) as Lang.String {
        if (type.equals(BoatType.MOTOR)) {
            return "Motor";
        }
        return "Sailboat";
    }
}
