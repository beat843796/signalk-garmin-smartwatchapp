/*
 * AutopilotView.mc
 * Autopilot control screen. Pushed on top of VesselDataView when the user
 * presses the select/enter key. Shows current heading/target, a rudder-angle
 * bar, and the current AP state. Key bindings let the user adjust the target
 * heading (±1°/±10°) and, via a Menu2, switch modes (standby/auto/wind).
 *
 * Contains three classes:
 *   AutopilotView           — the View renderer
 *   AutopilotDelegate       — BehaviorDelegate for heading-change + mode menu
 *   AutopilotMenuDelegate   — Menu2InputDelegate for the mode-select popup
 */

using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;
using Toybox.Lang;
using Toybox.System;
using Toybox.Attention;

using Utilities as Utils;

/*
 * Global state shared between AutopilotView (rendering) and AutopilotDelegate
 * (input handling). Kept module-level so both classes can see the same value
 * without threading it through constructors.
 */
var changeHeading = 0;
var changeHeadingMode = false;

/*
 * Renders either the normal autopilot dashboard (current heading, rudder bar,
 * AP state) or the "change heading" edit screen when the user has started
 * adjusting the target with the up/down/clock/menu keys.
 */
class AutopilotView extends WatchUi.View {

    var rudderHeight = 26;
    var width;
    var height;

    function initialize() {
        View.initialize();
    }

    /*
     * Refresh status on entry so canSendCommands() reflects the latest
     * transport state. For BLE this also subscribes to the AP
     * characteristic — autopilot state, current/target headings,
     * rudder angle, trip/log. AWA is NOT in AP, so the wind arrow is
     * no longer drawn here. Both calls are no-ops for transports that
     * don't apply.
     */
    function onShow() as Void {
        if (vessel != null) {
            vessel.refreshStatus();
            vessel.beginDataStreaming(BleCharUuids.AP);
        }
    }

    function onUpdate(dc) {

        View.onUpdate(dc);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        width = dc.getWidth();
        height = dc.getHeight();

        if (changeHeadingMode) {
            drawChangeHeading(dc);
        } else {
            drawValues(dc);
        }
    }

    /*
     * Edit-mode overlay: shown while the user is dialing in a ±N° delta
     * before committing it with the select key. Two-row layout —
     * "Change Heading" label centred in the top half, the pending delta
     * centred in the bottom half.
     */
    function drawChangeHeading(dc) {

        var labelFont = Graphics.FONT_SYSTEM_TINY;
        var valueFont = Graphics.FONT_NUMBER_THAI_HOT;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        dc.drawText(
            width / 2,
            height / 4,
            labelFont,
            "Change\nHeading",
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));

        dc.drawText(
            width / 2,
            (height / 2) + 30,
            valueFont,
            changeHeading,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
    }

    /*
     * Main autopilot screen — two equal rows:
     *   top half: heading label + value (label small above, value big
     *             centred)
     *   bottom half: state name centred
     *
     * Rudder-angle bar drawn on the boundary between the two rows so
     * it doesn't compete with either text block.
     */
    function drawValues(dc) {

        var valueToDraw = "---";
        var labelText = "";
        var stateName = vessel.getNameForActiveState();

        // Which heading to show depends on the current AP mode.
        switch (vessel.autopilotState) {
            case ApStates.STANDBY:
                valueToDraw = vessel.getHeadingMagneticDegreeString();
                labelText = "HDG";
                break;
            case ApStates.AUTO:
                valueToDraw = vessel.getTargetHeadingMagneticDegreeString();
                labelText = "HDG";
                break;
            case ApStates.WIND:
                valueToDraw = vessel.getTargetHeadingWindAppearantDegreeString();
                labelText = "AWA";
                break;
            case ApStates.ROUTE:
                valueToDraw = "---";
                labelText = "DTW";
                break;
        }

        // Top row: heading display centred at height/4.
        drawHeadingCell(dc, width / 2, height / 4, labelText, valueToDraw);

        // Bottom row: state name centred at 3*height/4. Standby is
        // neutral (grey); active modes use red so the running state
        // is visually distinct.
        var stateColor = vessel.autopilotState.equals(ApStates.STANDBY)
            ? Graphics.COLOR_LT_GRAY
            : Graphics.COLOR_RED;
        dc.setColor(stateColor, Graphics.COLOR_BLACK);
        dc.drawText(
            width / 2,
            (height * 3) / 4,
            Graphics.FONT_SYSTEM_MEDIUM,
            stateName,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));

        // Rudder bar straddles the row boundary. Skip when no rudder
        // reading is available.
        if (vessel.rudderAngle != null) {
            drawRudderAngle(dc, Utils.radiansToDegrees(vessel.rudderAngle));
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.setPenWidth(2);

        var xOffsetTens = width / 8;
        for (var i = 1; i < 8; i += 1) {
            dc.drawLine(xOffsetTens * i, height / 2 - rudderHeight / 2, xOffsetTens * i, height / 2 + rudderHeight / 2);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.setPenWidth(4);
        dc.drawLine(0, height / 2 - rudderHeight / 2, width, height / 2 - rudderHeight / 2);
        dc.drawLine(0, height / 2 + rudderHeight / 2, width, height / 2 + rudderHeight / 2);
        dc.drawLine(width / 2, height / 2 - rudderHeight / 2, width / 2, height / 2 + rudderHeight / 2);
    }

    /*
     * Heading display cell — label small, value big, both centred
     * vertically as a pair around (cx, cy). Title sits a real
     * font-derived gap above the value so it isn't clipped by the
     * value's ascender.
     */
    function drawHeadingCell(dc, cx, cy, labelText, valueText) {
        var labelFont = Graphics.FONT_SYSTEM_XTINY;
        var valueFont = Graphics.FONT_NUMBER_HOT;
        var labelH = dc.getFontHeight(labelFont);
        var valueH = dc.getFontHeight(valueFont);
        var gap = -25;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            cx,
            cy - valueH / 2 - labelH / 2 - gap,
            labelFont,
            labelText,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            cx,
            cy+15,
            valueFont,
            sanitizeForNumberFont(valueText),
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
    }

    /*
     * FONT_NUMBER_HOT is a number-only font: digits and a few
     * punctuation glyphs only. The degree symbol "°" and the em-dash
     * "—" used in our model formatters render as missing-glyph boxes.
     * Substitute them with safe characters here so the heading display
     * stays legible. The label ("HDG"/"AWA") already implies degrees.
     */
    function sanitizeForNumberFont(value) {
        if (value == null) {
            return "---";
        }
        if (value.equals("—")) {
            return "---";
        }
        var len = value.length();
        if (len > 0 && value.substring(len - 1, len).equals("°")) {
            return value.substring(0, len - 1);
        }
        return value;
    }

    /*
     * Rudder-angle indicator: a red (port) / green (starboard) filled bar
     * extending from the centreline by a fraction of the half-width
     * proportional to the rudder angle (clamped at ±40°).
     */
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
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_BLACK);
        } else {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
        }

        var xOffset = 0;
        if (rudderAngle < 0.0d) {
            xOffset = width/2*percentage;
        }

        dc.fillRectangle(width/2-xOffset, height/2-rudderHeight/2, width/2*percentage, rudderHeight);
    }
}

/*
 * Input delegate for the autopilot screen. Maps keys to heading adjustments
 * (up/down/clock/menu) and opens the mode-select Menu2 on the select key.
 * Stops the 100 ms data poll while a menu or edit is open so inbound updates
 * don't overwrite the user's in-progress changes.
 */
class AutopilotDelegate extends WatchUi.BehaviorDelegate {

    /*
     * Press timestamps (ms since boot) for long-press detection on
     * UP/DOWN. Garmin's hardware mapping fires KEY_MENU on long-press
     * UP, but there's no equivalent for long-press DOWN — we have to
     * detect duration ourselves via onKeyPressed/onKeyReleased.
     */
    private var downPressedAt = null;
    private var upPressedAt = null;
    private const longPressMs = 500;

    function initialize() {
        BehaviorDelegate.initialize();
    }

    /*
     * Select key: either commit a pending heading change, or open the
     * mode-select menu. No-op while the model is in an error state.
     */
    function onSelect() as Lang.Boolean {

        if (!ensureCommandTransport()) {
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
            case ApStates.STANDBY:
                focus = 0;
                break;
            case ApStates.AUTO:
                autoItem.setSubLabel("Active");
                focus = 1;
                break;
            case ApStates.WIND:
                windItem.setSubLabel("Active");
                focus = 2;
                break;
            case ApStates.ROUTE:
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

    /*
     * Directional keys adjust the pending heading delta. UP/DOWN are
     * handled by the press/release pair below for long-press support.
     * KEY_MENU fires on hardware long-press UP (Garmin convention) and
     * also gives +10. KEY_CLOCK gives -10 for parity. ESC exits edit
     * mode or pops the view.
     */
    function onKey(keyEvent as WatchUi.KeyEvent) as Lang.Boolean {

        var key = keyEvent.getKey();
        if (key == KEY_CLOCK || key == KEY_MENU) {
            if (!ensureCommandTransport()) {
                return true;
            }
        }
        switch (key) {
            case KEY_CLOCK:
                applyDelta(-10);
                break;
            case KEY_MENU:
                applyDelta(+10);
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

    /*
     * Press/release pair for KEY_UP and KEY_DOWN. Returning true from
     * onKeyPressed stops CIQ from synthesising the higher-level onKey
     * event for the same key, so we don't double-fire. Other keys are
     * passed through to the default mapping via super().
     */
    function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Lang.Boolean {
        var key = keyEvent.getKey();
        if (key == KEY_DOWN) {
            if (!ensureCommandTransport()) {
                return true;
            }
            downPressedAt = System.getTimer();
            return true;
        }
        if (key == KEY_UP) {
            if (!ensureCommandTransport()) {
                return true;
            }
            upPressedAt = System.getTimer();
            return true;
        }
        return BehaviorDelegate.onKeyPressed(keyEvent);
    }

    function onKeyReleased(keyEvent as WatchUi.KeyEvent) as Lang.Boolean {
        var key = keyEvent.getKey();
        if (key == KEY_DOWN && downPressedAt != null) {
            var heldMs = System.getTimer() - downPressedAt;
            downPressedAt = null;
            applyDelta(heldMs >= longPressMs ? -10 : -1);
            return true;
        }
        if (key == KEY_UP && upPressedAt != null) {
            var heldMs = System.getTimer() - upPressedAt;
            upPressedAt = null;
            applyDelta(heldMs >= longPressMs ? +10 : +1);
            return true;
        }
        // Release without a stored press = the press itself was blocked
        // by the REST guard. Swallow so the default release handler
        // doesn't re-trigger a delta.
        if (key == KEY_DOWN || key == KEY_UP) {
            return true;
        }
        return BehaviorDelegate.onKeyReleased(keyEvent);
    }

    /*
     * Pre-flight guard for any key that initiates an autopilot command.
     * Returns true when REST is in CONN_CONNECTED so the caller may
     * proceed; returns false (and pushes NoRestConnectionView) otherwise.
     * Called from onSelect, onKey (CLOCK/MENU), and onKeyPressed (UP/DOWN).
     * BLE-only data is read-only by design; commands always need REST.
     */
    private function ensureCommandTransport() as Lang.Boolean {
        if (vessel.canSendCommands()) {
            return true;
        }
        System.println("[AP] command blocked — neither REST nor BLE connected");
        WatchUi.pushView(
            new NoRestConnectionView(),
            new NoRestConnectionViewDelegate(),
            WatchUi.SLIDE_LEFT);
        return false;
    }

    /*
     * Applies a heading delta. Beeps on the ±10 coarse step so the
     * user gets audible confirmation of the long-press detection.
     */
    private function applyDelta(delta) {
        if (delta == 10 || delta == -10) {
            if (Attention has :playTone) {
                Attention.playTone(Attention.TONE_KEY);
            }
        }
        updateHeading(delta);
    }

    /*
     * Accumulate a pending heading delta, enter edit mode, and suspend the
     * data poll so incoming server updates don't stomp on the user's edit.
     */
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

/*
 * Delegate for the mode-select Menu2 opened from AutopilotDelegate.onSelect.
 * Dispatches the chosen mode to VesselModel, resumes data polling, pops the
 * menu.
 */
class AutopilotMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {

        if (!vessel.canSendCommands()) {
            System.println("[AP] mode change blocked — REST not connected");
            WatchUi.pushView(
                new NoRestConnectionView(),
                new NoRestConnectionViewDelegate(),
                WatchUi.SLIDE_LEFT);
            return;
        }

        switch (item.getId()) {
            case AP_STATE_STANDBY:
                vessel.setAutopilotState(ApStates.STANDBY);
                break;
            case AP_STATE_AUTO:
                vessel.setAutopilotState(ApStates.AUTO);
                break;
            case AP_STATE_WIND:
                vessel.setAutopilotState(ApStates.WIND);
                break;
            case AP_STATE_TRACK:
                vessel.setAutopilotState(ApStates.ROUTE);
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
