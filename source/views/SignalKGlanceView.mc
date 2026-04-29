/*
 * SignalKGlanceView.mc
 * Glance-carousel tile shown on the watch's glance screen. Layout is
 * driven by the persisted ConnectionType:
 *
 *   NONE  →  "NOT CONFIGURED" (gray)
 *   REST  →  "SignalK HTTPs" + last-known autopilot mode
 *   BLE   →  "SignalK BLE"  + last-known autopilot mode
 *
 * The (:glance) annotation restricts this class to the glance compile
 * slice — no VesselModel, no BluetoothLowEnergy. Inputs come from
 * Application.Storage (snapshot dict written by VesselModel).
 *
 * Strings are inlined here rather than loaded from Rez.Strings — the
 * resource table for the glance slice on SDK 9.1 / fenix8-class devices
 * crashes with "Illegal Access (Out of Bounds): Could not access symbol
 * 'Rez'" on every Rez.Strings.* lookup. The glance only renders English
 * literals, so this trades localization on the tile for a working tile.
 */

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Application.Storage;

(:glance)
class SignalKGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var h = dc.getHeight();

        var type = readConnectionType();

        if (type == null || type.equals(ConnectionType.NONE)) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(
                5,
                h * 0.5,
                Graphics.FONT_SYSTEM_TINY,
                "NOT CONFIGURED",
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var titleText;
        if (type.equals(ConnectionType.REST)) {
            titleText = "SignalK HTTPs";
        } else if (type.equals(ConnectionType.BLE)) {
            titleText = "SignalK BLE";
        } else {
            titleText = type;
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(
            5,
            h * 0.15,
            Graphics.FONT_SYSTEM_TINY,
            titleText,
            Graphics.TEXT_JUSTIFY_LEFT);

        dc.drawText(
            5,
            h * 0.55,
            Graphics.FONT_SYSTEM_XTINY,
            readAutopilotMode(),
            Graphics.TEXT_JUSTIFY_LEFT);
    }

    /*
     * Reads the persisted connection type. Works without loading
     * VesselModel / TransportFactory (both of which are excluded from
     * the glance slice). Returns the raw string or null.
     */
    private function readConnectionType() {
        var raw = Storage.getValue(StorageKeys.CONNECTION_TYPE);
        if (raw instanceof Lang.String) {
            return raw;
        }
        return null;
    }

    /*
     * Subtitle: name of the last-known autopilot mode. The snapshot
     * stores the raw signalk state name (lowercase); we map it to the
     * same wording used by the autopilot mode-select menu in main app.
     */
    private function readAutopilotMode() as Lang.String {
        var snapshot = Storage.getValue(StorageKeys.GLANCE_SNAPSHOT);
        if (snapshot instanceof Lang.Dictionary) {
            var ap = snapshot["ap"];
            if (ap instanceof Lang.String) {
                if (ap.equals(ApStates.STANDBY)) { return "Standby"; }
                if (ap.equals(ApStates.AUTO))    { return "Auto"; }
                if (ap.equals(ApStates.WIND))    { return "Wind"; }
                if (ap.equals(ApStates.ROUTE))   { return "Track"; }
            }
        }
        return "—";
    }
}
