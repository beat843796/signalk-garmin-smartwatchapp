// AutopilotView.mc
// Autopilot control screen. Pushed on top of VesselDataView when the user
// presses the select/enter key. Shows current heading/target, a rudder-angle
// bar, and the current AP state. Key bindings let the user adjust the target
// heading (±1°/±10°) and, via a Menu2, switch modes (standby/auto/wind).
//
// Contains three classes:
//   AutopilotView           — the View renderer
//   AutopilotDelegate       — BehaviorDelegate for heading-change + mode menu
//   AutopilotMenuDelegate   — Menu2InputDelegate for the mode-select popup

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;
using Toybox.Lang;

using Utilities as Utils;

// Global state shared between AutopilotView (rendering) and AutopilotDelegate
// (input handling). Kept module-level so both classes can see the same value
// without threading it through constructors.
var changeHeading = 0;
var changeHeadingMode = false;

// Renders either the normal autopilot dashboard (current heading, rudder bar,
// AP state) or the "change heading" edit screen when the user has started
// adjusting the target with the up/down/clock/menu keys.
class AutopilotView extends WatchUi.View {

    var rudderHeight = 26;
    var width;
    var height;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {

        View.onUpdate(dc);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        width = dc.getWidth();
        height = dc.getHeight();

        if (changeHeadingMode) {
            drawChangeHeading(dc);
        } else {
            drawValues(dc);
        }
    }

    // Edit-mode overlay: shown while the user is dialing in a ±N° delta
    // before committing it with the select key.
    function drawChangeHeading(dc) {

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);

        dc.drawText(
            width/2,
            45,
            Graphics.FONT_SYSTEM_TINY,
            "Change\nHeading",
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));

        dc.drawText(
            width/2,
            height/2,
            Graphics.FONT_NUMBER_THAI_HOT,
            changeHeading,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
    }

    // Main autopilot screen: label + current/target heading at the top,
    // rudder-angle bar across the middle, AP state name at the bottom.
    function drawValues(dc) {

        var valueToDraw = "---";
        var labelText = "";
        var stateName = vessel.getNameForActiveState();

        // Which heading to show depends on the current AP mode.
        switch (vessel.autopilotState) {
            case "standby":
                valueToDraw = vessel.getHeadingMagneticDegreeString();
                labelText = "HDG";
                break;
            case "auto":
                valueToDraw = vessel.getTargetHeadingMagneticDegreeString();
                labelText = "HDG";
                break;
            case "wind":
                valueToDraw = vessel.getTargetHeadingWindAppearantDegreeString();
                labelText = "AWA";
                break;
            case "route":
                valueToDraw = "---";
                labelText = "DTW";
                break;
        }

        drawDataText(dc, width/2, 10, labelText, valueToDraw);

        if (vessel.autopilotState.equals("standby")) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        } else {
            dc.setColor(Graphics.COLOR_DK_RED, Graphics.COLOR_WHITE);
        }

        // Errors are handled globally by ErrorView (pushed on top by
        // VesselModel). No inline error handling needed here.

        dc.drawText(
            width/2,
            165,
            Graphics.FONT_SYSTEM_MEDIUM,
            stateName,
            Graphics.TEXT_JUSTIFY_CENTER);

        // Rudder bar, tick marks, centreline.
        drawRudderAngle(dc, Utils.radiansToDegrees(vessel.rudderAngle));

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.setPenWidth(2);

        var xOffsetTens = width/8;
        for (var i = 1; i < 8; i += 1) {
            dc.drawLine(xOffsetTens*i, height/2-rudderHeight/2, xOffsetTens*i, height/2+rudderHeight/2);
        }

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.setPenWidth(4);
        dc.drawLine(0, height/2-rudderHeight/2, width, height/2-rudderHeight/2);
        dc.drawLine(0, height/2+rudderHeight/2, width, height/2+rudderHeight/2);
        dc.drawLine(width/2, height/2-rudderHeight/2, width/2, height/2+rudderHeight/2);

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_WHITE);
        Utils.drawWindAngle(dc, vessel.apparentWindAngle, width);
    }

    function drawDataText(dc, x, y, labelText, valueText) {
        dc.drawText(
            x,
            y-2,
            Graphics.FONT_SYSTEM_XTINY,
            labelText,
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(
            x,
            y+28,
            Graphics.FONT_NUMBER_HOT,
            valueText,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Rudder-angle indicator: a red (port) / green (starboard) filled bar
    // extending from the centreline by a fraction of the half-width
    // proportional to the rudder angle (clamped at ±40°).
    function drawRudderAngle(dc, rudderAngle) {

        if (rudderAngle == 0) {
            return;
        }

        var absRudderAngle = rudderAngle;
        if (rudderAngle < 0) {
            absRudderAngle = rudderAngle * -1;
        }

        var percentage = absRudderAngle / 40.0d;
        if (percentage > 1.0d) {
            percentage = 1.0;
        }

        if (rudderAngle < 0) {
            dc.setColor(Graphics.COLOR_DK_RED, Graphics.COLOR_WHITE);
        } else {
            dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_WHITE);
        }

        var xOffset = 0;
        if (rudderAngle < 0.0d) {
            xOffset = width/2*percentage;
        }

        dc.fillRectangle(width/2-xOffset, height/2-rudderHeight/2, width/2*percentage, rudderHeight);
    }
}

// Input delegate for the autopilot screen. Maps keys to heading adjustments
// (up/down/clock/menu) and opens the mode-select Menu2 on the select key.
// Stops the 100 ms data poll while a menu or edit is open so inbound updates
// don't overwrite the user's in-progress changes.
class AutopilotDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    // Select key: either commit a pending heading change, or open the
    // mode-select menu. No-op while the model is in an error state.
    function onSelect() as Lang.Boolean {

        if (vessel.errorCode != null) {
            return true;
        }

        if (changeHeadingMode) {
            vessel.changeHeading(changeHeading);
            changeHeading = 0;
            changeHeadingMode = false;
            WatchUi.requestUpdate();
            vessel.startUpdatingData();
            return false;
        }

        var standbyItem = new WatchUi.MenuItem("Standby", null, AP_STATE_STANDBY, null);
        var autoItem = new WatchUi.MenuItem("Auto", null, AP_STATE_AUTO, null);
        var windItem = new WatchUi.MenuItem("Wind", null, AP_STATE_WIND, null);
        var trackItem = new WatchUi.MenuItem("Track", null, AP_STATE_TRACK, null);

        var focus = 0;
        switch (vessel.autopilotState) {
            case "standby":
                focus = 0;
                break;
            case "auto":
                autoItem.setSubLabel("Active");
                focus = 1;
                break;
            case "wind":
                windItem.setSubLabel("Active");
                focus = 2;
                break;
            case "route":
                trackItem.setSubLabel("Active");
                focus = 3;
                break;
        }

        var menu = new WatchUi.Menu2({:title=>"SET MODE", :focus=>focus});
        menu.addItem(standbyItem);
        menu.addItem(autoItem);
        menu.addItem(windItem);
        // trackItem intentionally omitted — route mode isn't wired up end-to-end.

        WatchUi.pushView(menu, new AutopilotMenuDelegate(), WatchUi.SLIDE_UP);
        vessel.stopUpdatingData();
        return true;
    }

    // Directional keys adjust the pending heading delta. Clock / Menu keys
    // are wired for ±10° coarse steps since up/down are typically rocker keys
    // that auto-repeat slowly. ESC exits edit mode or pops the view.
    function onKey(keyEvent as WatchUi.KeyEvent) as Lang.Boolean {

        switch (keyEvent.getKey()) {
            case KEY_DOWN:
                updateHeading(-1);
                break;
            case KEY_UP:
                updateHeading(+1);
                break;
            case KEY_CLOCK:
                updateHeading(-10);
                break;
            case KEY_MENU:
                updateHeading(+10);
                break;
            case KEY_ESC:
                vessel.startUpdatingData();
                if (changeHeadingMode) {
                    changeHeadingMode = false;
                    WatchUi.requestUpdate();
                    changeHeading = 0;
                } else {
                    WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
                }
                break;
        }
        return true;
    }

    // Accumulate a pending heading delta, enter edit mode, and suspend the
    // data poll so incoming server updates don't stomp on the user's edit.
    function updateHeading(value) {
        vessel.stopUpdatingData();
        changeHeadingMode = true;
        changeHeading = changeHeading + value;
        if (changeHeading > 180) {
            changeHeading = 180;
        }
        if (changeHeading < -180) {
            changeHeading = -180;
        }
        WatchUi.requestUpdate();
    }
}

// Delegate for the mode-select Menu2 opened from AutopilotDelegate.onSelect.
// Dispatches the chosen mode to VesselModel, resumes data polling, pops the
// menu.
class AutopilotMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {

        if (vessel.errorCode != null) {
            return;
        }

        switch (item.getId()) {
            case AP_STATE_STANDBY:
                vessel.setAutopilotState("standby");
                break;
            case AP_STATE_AUTO:
                vessel.setAutopilotState("auto");
                break;
            case AP_STATE_WIND:
                vessel.setAutopilotState("wind");
                break;
            case AP_STATE_TRACK:
                vessel.setAutopilotState("route");
                break;
        }

        vessel.startUpdatingData();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        vessel.startUpdatingData();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
