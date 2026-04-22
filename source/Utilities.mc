/*
 * Utilities.mc
 * Pure unit-conversion helpers (knots/m-s, nautical miles, radians/degrees,
 * Kelvin/Celsius), the wind-arrow rendering primitive shared by the main view
 * and the autopilot view, and the HTTP/BLE error-code → display-string table.
 * Everything here is side-effect-free and unit-tested in UtilitiesTest.mc.
 */

using Toybox.Math;
using Toybox.Graphics;

module Utilities {

    // Exact m/s → knots factor: 1 m/s = 3600/1852 kn = 1.943844 kn.
    const FACTOR_MS_TO_KNOTS = 1.943844d;

    function meterPerSecondToKnots(metersPerSecond) {
        return metersPerSecond * FACTOR_MS_TO_KNOTS;
    }

    function degreesToRadians(degrees) {
        return degrees * Math.PI / 180.0d;
    }

    function metersToNauticalMiles(meters) {
        /*
         * Historical factor — slightly different from the pure 1/1852 (see
         * UtilitiesTest.mc test_metersToNm_oneNauticalMile for the tolerance).
         */
        return meters * 0.00053995680d;
    }

    function radiansToDegrees(radians) {
        return radians * 180.0d / Math.PI;
    }

    function kelvinToCelsius(kelvin) {
        return kelvin - 273.15d;
    }

    /*
     * Draws a small orange arrow along the edge of a circular display,
     * pointing outward in the direction given by `angle` (radians). Used to
     * render apparent-wind direction on VesselDataView and AutopilotView.
     * `width` is the diameter of the drawing area in pixels; the arrow sits
     * just outside it.
     * Renders a centred title + body pair on an otherwise blank screen.
     * Used by AuthConfigView (per-authState variants) and ErrorView;
     * extracted so those views stay short and the visual style stays
     * consistent.
     *
     * Title sits in the upper third, body in the lower half. Proportional
     * offsets keep them from overlapping on tall multi-line bodies across
     * every target display size (240px watches up to 454px round).
     */
    function drawStatusScreen(dc, title, titleColor, body) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(titleColor, Graphics.COLOR_WHITE);
        dc.drawText(
            w/2,
            h * 0.3,
            Graphics.FONT_SYSTEM_MEDIUM,
            title,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.drawText(
            w/2,
            h * 0.6,
            Graphics.FONT_SYSTEM_TINY,
            body,
            (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
    }

    function drawWindAngle(dc, angle, width) {

        /*
         * 0 rad on the compass means north (12 o'clock); trig functions put 0
         * at the 3 o'clock position, so subtract 90° to compensate.
         */
        var correctedAngleDegrees = radiansToDegrees(angle) - 90.0d;
        var radians =  degreesToRadians(correctedAngleDegrees);

        var arrowLength = 20;

        var xA = width/2 + (width/2-arrowLength) * Math.cos(radians);
        var yA = width/2 + (width/2-arrowLength) * Math.sin(radians);

        var xB = width/2 + (width/2+5) * Math.cos(radians+0.15d);
        var yB = width/2 + (width/2+5) * Math.sin(radians+0.15d);

        var xC = width/2 + (width/2+5) * Math.cos(radians-0.15d);
        var yC = width/2 + (width/2+5) * Math.sin(radians-0.15d);

        var pointA = [xA,yA];
        var pointB = [xB,yB];
        var pointC = [xC,yC];

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_WHITE);
        dc.fillPolygon([pointA, pointB, pointC]);
    }

    /*
     * Maps Connect IQ Communications response codes (both positive HTTP and
     * negative Communications.* constants) to short multi-line labels the
     * views can render directly. Keyed by code for O(1) lookup in
     * errorMessage() and to keep the type checker happy.
     */
    var errorMessages as Toybox.Lang.Dictionary<Toybox.Lang.Number, Toybox.Lang.String> = {
         0   => "UNKNOWN ERROR",
        -1   => "BLE ERROR",
        -2   => "BLE HOST\nTIMEOUT",
        -3   => "BLE SERVER\nTIMEOUT",
        -4   => "BLE NO DATA",
        -5   => "BLE REQUEST\nCANCELLED",
        -101 => "BLE QUEUE\nFULL",
        -102 => "BLE REQUEST\nTOO LARGE",
        -103 => "BLE UNKNOWN\nSEND ERROR",
        -104 => "PHONE CONNECTION\nUNAVAILABLE",
        -200 => "INVALID HTTP\nHEADER FIELDS\nIN REQUEST",
        -201 => "INVALID HTTP\nBODY IN REQUEST",
        -202 => "INVALID HTTP\nMETHOD IN REQUEST",
        /*
         * Timeout, malformed-response, unparseable-body, oversized-body all
         * mean "we got nothing useful from the server" — collapse to one
         * user-friendly label. Raw codes still appear in System.println logs.
         */
        -300 => "Server not\nfound",
        -400 => "Server not\nfound",
        -401 => "Server not\nfound",
        -402 => "Server not\nfound",
        -403 => "NETWORK RESPONSE\nOUT OF MEMORY",
        -1001 => "HTTPS\nREQUIRED",
        -1002 => "UNSUPPORTED\nCONTENT TYPE",

         100 => "Continue",
         101 => "Switching Protocol",
         200 => "OK",
         201 => "Created",
         202 => "Accepted",
         203 => "Non-Authoritative\nInformation",
         204 => "No Content",
         205 => "Reset Content",
         206 => "Partial Content",
         300 => "Multiple Choices",
         301 => "Moved Permanently",
         302 => "Found",
         303 => "See Other",
         304 => "Not Modified",
         307 => "Temporary\nRedirect",
         308 => "Permanent\nRedirect",
         400 => "Bad Request",
         401 => "Unauthorized",
         403 => "Forbidden",
         404 => "Server not\nfound",
         405 => "Method\nNot Allowed",
         406 => "Not Acceptable",
         407 => "Proxy Authentication\nRequired",
         408 => "Request Timeout",
         409 => "Conflict",
         410 => "Gone",
         411 => "Length Required",
         412 => "Precondition\nFailed",
         413 => "Payload\nToo Large",
         414 => "URI Too Long",
         415 => "Unsupported\nMedia Type",
         416 => "Range Not\nSatisfiable",
         417 => "Expectation Failed",
         426 => "Upgrade\nRequired",
         428 => "Precondition\nRequired",
         429 => "Too Many\nRequests",
         431 => "Request Header\nFields Too Large",
         451 => "Unavailable For\nLegal Reasons",
         500 => "Internal\nServer Error",
         501 => "Not Implemented",
         502 => "Bad Gateway",
         503 => "SignalK Service\nUnavailable",
         504 => "Gateway Timeout",
         505 => "HTTP Version\nNot Supported",
         511 => "Network\nAuthentication Required"
    };

    /*
     * Returns a short label for a Communications response code, or the raw
     * code itself when unmapped (so unknown errors still surface a number
     * the developer can look up).
     */
    function errorMessage(code as Toybox.Lang.Number) {
        var mapped = errorMessages[code];
        if (mapped != null) {
            return mapped;
        }
        return code;
    }

}
