/*
 * SignalKGlanceView.mc
 * Glance-carousel tile shown on the watch's glance screen. Layout is
 * driven by the persisted ConnectionType:
 *
 *   NONE  →  "NOT CONFIGURED" (gray)
 *   REST  →  "SignalK Server" + the configured baseurl_prop
 *   BLE   →  "BLE" + the last-known BLE device name (from the
 *            glance snapshot dict written by VesselModel)
 *
 * The (:glance) annotation restricts this class to the glance compile
 * slice — no VesselModel, no BluetoothLowEnergy. Inputs come from
 * Application.Storage (snapshot dict) and Application.Properties
 * (baseurl_prop).
 */

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Application.Storage;
using Toybox.Application.Properties;

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

        /*
         * NOT CONFIGURED: render a single line vertically centred —
         * there's nothing else useful to display until the user
         * launches the app and picks a transport.
         */
        if (type == null || type.equals("none")) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(
                5,
                h * 0.5,
                Graphics.FONT_SYSTEM_TINY,
                WatchUi.loadResource(Rez.Strings.GlanceNotConfigured) as Lang.String,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var titleText;
        var subtitleText;
        if (type.equals("rest")) {
            titleText = WatchUi.loadResource(Rez.Strings.TitleSignalKServer) as Lang.String;
            subtitleText = readRestUrl();
        } else if (type.equals("ble")) {
            titleText = WatchUi.loadResource(Rez.Strings.TitleBle) as Lang.String;
            subtitleText = readBleDeviceName();
        } else {
            titleText = type;
            subtitleText = "";
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
            subtitleText,
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
     * Subtitle for REST mode — the configured baseurl_prop, trimmed
     * of any trailing slash so the line stays tidy.
     */
    private function readRestUrl() as Lang.String {
        var rawUrl = Properties.getValue("baseurl_prop");
        if (rawUrl != null && rawUrl instanceof Lang.String && rawUrl.length() > 0) {
            if (rawUrl.substring(rawUrl.length() - 1, rawUrl.length()).equals("/")) {
                return rawUrl.substring(0, rawUrl.length() - 1);
            }
            return rawUrl;
        }
        return WatchUi.loadResource(Rez.Strings.GlanceMissingUrl) as Lang.String;
    }

    /*
     * Subtitle for BLE mode — the last-known device name from the
     * glance snapshot. Falls back to "Not Connected" if the snapshot
     * doesn't carry one (i.e. we've never paired in this install).
     */
    private function readBleDeviceName() as Lang.String {
        var snapshot = Storage.getValue(StorageKeys.GLANCE_SNAPSHOT);
        if (snapshot instanceof Lang.Dictionary) {
            var name = snapshot["bleDeviceName"];
            if (name instanceof Lang.String && name.length() > 0) {
                return name;
            }
        }
        return WatchUi.loadResource(Rez.Strings.BleStatusNotConnected) as Lang.String;
    }
}
