/*
 * Utilities.mc
 * Pure unit-conversion helpers (knots/m-s, nautical miles, radians/degrees,
 * Kelvin/Celsius), the wind-arrow rendering primitive shared by the main view
 * and the autopilot view, and the HTTP/BLE error-code → display-string table.
 * Everything here is side-effect-free and unit-tested in UtilitiesTest.mc.
 */

using Toybox.Math;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Cryptography;

module Utilities {

    // Exact m/s → knots factor: 1 m/s = 3600/1852 kn = 1.943844 kn.
    const FACTOR_MS_TO_KNOTS = 1.943844d;
    // Depth readings above this threshold are rendered as "---" (sentinel
    // for invalid / no reading). Matches the historical VesselModel rule.
    const MAX_VALID_DEPTH_M = 500.0d;

    /*
     * Synthetic error code for "data plugin not installed on the SignalK
     * server". Outside the HTTP and Communications.* ranges to avoid any
     * collision; mapped to "MISSING\nPLUGIN" in errorMessages so ErrorView
     * renders it without any per-code branching.
     */
    const ERR_MISSING_PLUGIN = -2000;

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
     * ================== Display formatters ==================
     * Pure, side-effect-free string formatters used by VesselModel's
     * getters. Extracted so they can be unit-tested without constructing
     * a VesselModel. The naming convention: `format{Quantity}{Unit}`.
     */

    // m/s → "1.2" (knots, one decimal, no unit suffix).
    function formatSpeedKnots(metersPerSecond) {
        return meterPerSecondToKnots(metersPerSecond).format("%.1f");
    }

    /*
     * Depth in meters → "1.5m" below MAX_VALID_DEPTH_M; "---" at/above
     * that threshold. SignalK transducers report a large sentinel value
     * when they can't get a bottom echo; we hide that rather than
     * rendering nonsense.
     */
    function formatDepthMeters(meters) {
        if (meters >= MAX_VALID_DEPTH_M) {
            return "---";
        }
        return meters.format("%.1f") + "m";
    }

    // Kelvin → "23.4°C".
    function formatTemperatureCelsius(kelvin) {
        return kelvinToCelsius(kelvin).format("%.1f") + "°C";
    }

    // Meters → "5.3nm".
    function formatTripNauticalMiles(meters) {
        return metersToNauticalMiles(meters).format("%.1f") + "nm";
    }

    /*
     * ================== Configuration helpers ==================
     */

    /*
     * Base-URL sanitiser. Returns null for null / non-string / empty
     * input; otherwise strips a single trailing slash so URL composition
     * (`baseURL + "/signalk/..."`) stays canonical. Extracted from
     * VesselModel.configureSignalK to enable unit testing.
     */
    function normalizeBaseUrl(raw) {
        if (raw == null || !(raw instanceof Lang.String) || raw.length() == 0) {
            return null;
        }
        if (raw.substring(raw.length() - 1, raw.length()).equals("/")) {
            return raw.substring(0, raw.length() - 1);
        }
        return raw;
    }

    /*
     * Computes the initial AUTH_* state from persisted inputs. Pure so
     * the 8 input combinations can be unit-tested without setting up
     * Application.Storage. Precedence: URL missing > token present >
     * pending href > nothing.
     */
    function deriveInitialAuthState(baseURL, token, accessRequestHref) {
        if (baseURL == null) {
            return AUTH_NO_URL;
        }
        if (token != null) {
            return AUTH_CONNECTED;
        }
        if (accessRequestHref != null) {
            return AUTH_PENDING;
        }
        return AUTH_NEEDS_REQUEST;
    }

    /*
     * Derives the user-visible CONN_* connectivity state by combining all
     * inputs the transport / auth layers produce. Pure — every (input
     * tuple) → state transition is deterministic and unit-tested.
     *
     * Inputs:
     *   baseURL       — Lang.String? configured server URL
     *   hasToken      — Lang.Boolean — JWT acquired?
     *   hasHref       — Lang.Boolean — access-request submitted, awaiting
     *                   admin approval?
     *   lastNetCode   — Lang.Number? — most recent HTTP / CIQ code from
     *                   any request to baseURL. null = nothing observed
     *                   yet (fresh launch).
     *   probeOk       — Lang.Boolean? — most recent /signalk discovery
     *                   probe outcome. Only consulted when lastNetCode
     *                   is in the ambiguous range (404/400) — distinguishes
     *                   "server is up, plugin route missing" (probe=true)
     *                   from "server is down, the 404 is from a captive
     *                   portal or similar" (probe=false). null = haven't
     *                   probed yet.
     *
     * Precedence (top wins):
     *   1. NO_URL       — empty/missing URL
     *   2. NO_HTTPS     — last request returned -1001 (Garmin's HTTPS
     *                     enforcement). Surfaces from any request, including
     *                     the access-request POST.
     *   3. NOT_AUTH     — no token, no pending request
     *   4. PENDING      — no token, but request submitted
     *   5. CONNECTED    — token + (no poll yet OR last poll 200)
     *   6. NOT_AUTH     — token + last poll 401/403 (token revoked)
     *   7. MISSING_PLUGIN / NOT_REACHABLE — token + last poll 404/400,
     *                     disambiguated by probe
     *   8. NOT_REACHABLE — token + any other failure (-300 timeout, 5xx,
     *                     unknown)
     */
    function deriveConnectivity(baseURL, hasToken, hasHref, lastNetCode, probeOk) {
        if (baseURL == null || baseURL.length() == 0) {
            return CONN_NO_URL;
        }
        if (lastNetCode != null && lastNetCode == -1001) {
            return CONN_NO_HTTPS;
        }
        if (!hasToken) {
            if (hasHref) {
                return CONN_PENDING;
            }
            return CONN_NOT_AUTH;
        }
        // hasToken — branch on data-poll outcome
        if (lastNetCode == null || lastNetCode == 200) {
            return CONN_CONNECTED;
        }
        if (lastNetCode == 401 || lastNetCode == 403) {
            return CONN_NOT_AUTH;
        }
        if (lastNetCode == 404 || lastNetCode == 400) {
            if (probeOk == false) {
                return CONN_NOT_REACHABLE;
            }
            return CONN_MISSING_PLUGIN;
        }
        return CONN_NOT_REACHABLE;
    }

    /*
     * ================== UUID v4 ==================
     */

    /*
     * Generates a RFC 4122 version-4 UUID as a lowercase hex string with
     * dashes, e.g. "550e8400-e29b-41d4-a716-446655440000". Uses the CIQ
     * cryptographic RNG for the 16 random bytes. Moved here from
     * VesselModel so the format can be validated with unit tests without
     * wiring up a full model.
     */
    function generateUuidV4() {
        var bytes = Cryptography.randomBytes(16);

        // Force the version and variant bits per RFC 4122 §4.4.
        bytes[6] = (bytes[6] & 0x0F) | 0x40;  // version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80;  // variant 10xxxxxx

        var hex = "0123456789abcdef";
        var out = "";
        for (var i = 0; i < 16; i++) {
            if (i == 4 || i == 6 || i == 8 || i == 10) {
                out += "-";
            }
            var b = bytes[i] & 0xFF;
            out += hex.substring((b >> 4) & 0x0F, ((b >> 4) & 0x0F) + 1);
            out += hex.substring(b & 0x0F, (b & 0x0F) + 1);
        }
        return out;
    }

    /*
     * Draws a small orange arrow along the edge of a circular display,
     * pointing outward in the direction given by `angle` (radians). Used
     * to render apparent-wind direction on VesselDataView and
     * AutopilotView. `width` is the diameter of the drawing area in
     * pixels; the arrow sits just outside it.
     */
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

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
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
         511 => "Network\nAuthentication Required",

         // Synthetic — see ERR_MISSING_PLUGIN above.
        -2000 => "MISSING\nPLUGIN"
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
