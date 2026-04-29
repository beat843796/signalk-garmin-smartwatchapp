using Toybox.Test;
using Toybox.Math;

using Utilities as Utils;

function almostEqual(a, b, eps) {
    var diff = a - b;
    if (diff < 0.0d) { diff = -diff; }
    return diff < eps;
}

(:test)
function test_mpsToKnots_oneMps_isKnotsConstant(logger) {
    var actual = Utils.meterPerSecondToKnots(1.0d);
    logger.debug("1 m/s -> " + actual + " kn");
    return almostEqual(actual, 1.943844d, 1.0e-9d);
}

(:test)
function test_mpsToKnots_zero_isZero(logger) {
    return almostEqual(Utils.meterPerSecondToKnots(0.0d), 0.0d, 1.0e-12d);
}

(:test)
function test_mpsToKnots_tenMps(logger) {
    var actual = Utils.meterPerSecondToKnots(10.0d);
    logger.debug("10 m/s -> " + actual + " kn");
    return almostEqual(actual, 19.43844d, 1.0e-9d);
}

(:test)
function test_degToRad_halfTurn_isPi(logger) {
    /*
     * Tolerance 1e-9, not 1e-12: the implementation uses Math.PI (Float)
     * multiplied against an Int argument, which won't hold Double precision.
     */
    var actual = Utils.degreesToRadians(180.0d);
    logger.debug("180 deg -> " + actual + " rad");
    return almostEqual(actual, Math.PI, 1.0e-9d);
}

(:test)
function test_degToRad_zero_isZero(logger) {
    return almostEqual(Utils.degreesToRadians(0.0d), 0.0d, 1.0e-12d);
}

(:test)
function test_degToRad_fullTurn_isTwoPi(logger) {
    var actual = Utils.degreesToRadians(360.0d);
    return almostEqual(actual, 2.0d * Math.PI, 1.0e-9d);
}

(:test)
function test_radToDeg_pi_is180(logger) {
    var actual = Utils.radiansToDegrees(Math.PI);
    logger.debug("PI rad -> " + actual + " deg");
    return almostEqual(actual, 180.0d, 1.0e-9d);
}

(:test)
function test_radToDeg_zero_isZero(logger) {
    return almostEqual(Utils.radiansToDegrees(0.0d), 0.0d, 1.0e-12d);
}

(:test)
function test_radToDeg_roundTrip(logger) {
    var original = 42.0d;
    var roundTrip = Utils.radiansToDegrees(Utils.degreesToRadians(original));
    logger.debug("42 deg -> rad -> deg = " + roundTrip);
    return almostEqual(roundTrip, original, 1.0e-9d);
}

(:test)
function test_metersToNm_oneNauticalMile(logger) {
    /*
     * 1 nm = 1852 m. The code's factor (0.00053995680) has a tiny error:
     * 1852 * 0.00053695680 would be the "pure" value, but 1852 * 0.00053995680
     * gives 0.9999985536. Pin the factor's actual behaviour.
     */
    var actual = Utils.metersToNauticalMiles(1852.0d);
    logger.debug("1852 m -> " + actual + " nm");
    return almostEqual(actual, 1852.0d * 0.00053995680d, 1.0e-12d);
}

(:test)
function test_metersToNm_zero_isZero(logger) {
    return almostEqual(Utils.metersToNauticalMiles(0.0d), 0.0d, 1.0e-12d);
}

(:test)
function test_kelvinToCelsius_freezingPoint(logger) {
    var actual = Utils.kelvinToCelsius(273.15d);
    logger.debug("273.15 K -> " + actual + " C");
    return almostEqual(actual, 0.0d, 1.0e-12d);
}

(:test)
function test_kelvinToCelsius_boilingPoint(logger) {
    var actual = Utils.kelvinToCelsius(373.15d);
    return almostEqual(actual, 100.0d, 1.0e-12d);
}

/*
 * ================== UUID v4 format ==================
 * Catches regressions where the version / variant bit-forcing or the
 * dash placement breaks. Values are random so we validate shape, not
 * content.
 */

(:test)
function test_generateUuidV4_length_is_36(logger) {
    var uuid = Utils.generateUuidV4();
    logger.debug("uuid=" + uuid);
    return uuid.length() == 36;
}

(:test)
function test_generateUuidV4_dashes_at_8_13_18_23(logger) {
    var uuid = Utils.generateUuidV4();
    return uuid.substring(8, 9).equals("-")
        && uuid.substring(13, 14).equals("-")
        && uuid.substring(18, 19).equals("-")
        && uuid.substring(23, 24).equals("-");
}

(:test)
function test_generateUuidV4_versionNibble_is_4(logger) {
    // Per RFC 4122: the 13th character (index 14) must be '4' for v4.
    var uuid = Utils.generateUuidV4();
    logger.debug("version nibble = " + uuid.substring(14, 15));
    return uuid.substring(14, 15).equals("4");
}

(:test)
function test_generateUuidV4_variantNibble_is_8_9_a_or_b(logger) {
    // Variant bits: 10xx → the nibble at index 19 must be one of 8/9/a/b.
    var uuid = Utils.generateUuidV4();
    var nibble = uuid.substring(19, 20);
    logger.debug("variant nibble = " + nibble);
    return nibble.equals("8") || nibble.equals("9")
        || nibble.equals("a") || nibble.equals("b");
}


/*
 * ================== Display formatters ==================
 */

(:test)
function test_formatSpeedKnots_zero_isZero(logger) {
    return Utils.formatSpeedKnots(0.0d).equals("0.0");
}

(:test)
function test_formatSpeedKnots_oneMps(logger) {
    // 1 m/s = 1.943844 kn → formatted with 1 decimal = "1.9".
    return Utils.formatSpeedKnots(1.0d).equals("1.9");
}

(:test)
function test_formatDepth_zero_isZeroPoint0m(logger) {
    return Utils.formatDepthMeters(0.0d).equals("0.0m");
}

(:test)
function test_formatDepth_underSentinel_formatted(logger) {
    return Utils.formatDepthMeters(12.34d).equals("12.3m");
}

(:test)
function test_formatDepth_exactlyMaxValid_isTripleDash(logger) {
    // Boundary: 500.0 triggers the sentinel (>= MAX_VALID_DEPTH_M).
    return Utils.formatDepthMeters(500.0d).equals("---");
}

(:test)
function test_formatDepth_aboveSentinel_isTripleDash(logger) {
    return Utils.formatDepthMeters(999.0d).equals("---");
}

(:test)
function test_formatTemperature_freezingPoint(logger) {
    return Utils.formatTemperatureCelsius(273.15d).equals("0.0°C");
}

(:test)
function test_formatTemperature_boilingPoint(logger) {
    return Utils.formatTemperatureCelsius(373.15d).equals("100.0°C");
}

(:test)
function test_formatTrip_oneNauticalMile(logger) {
    // 1852 m is effectively 1 nm (historical factor 0.00053995680 gives 1.0).
    var actual = Utils.formatTripNauticalMiles(1852.0d);
    logger.debug("1852m -> " + actual);
    return actual.equals("1.0nm");
}

(:test)
function test_formatTrip_zero_isZero(logger) {
    return Utils.formatTripNauticalMiles(0.0d).equals("0.0nm");
}


/*
 * ================== URL normalisation ==================
 */

(:test)
function test_normalizeBaseUrl_null_returnsNull(logger) {
    return Utils.normalizeBaseUrl(null) == null;
}

(:test)
function test_normalizeBaseUrl_empty_returnsNull(logger) {
    return Utils.normalizeBaseUrl("") == null;
}

(:test)
function test_normalizeBaseUrl_trailingSlash_stripped(logger) {
    var actual = Utils.normalizeBaseUrl("http://signalk.local:3000/");
    logger.debug("normalized -> " + actual);
    return actual.equals("http://signalk.local:3000");
}

(:test)
function test_normalizeBaseUrl_noTrailingSlash_unchanged(logger) {
    return Utils.normalizeBaseUrl("http://127.0.0.1:3000")
        .equals("http://127.0.0.1:3000");
}


/*
 * ================== deriveInitialAuthState ==================
 * Pure function from (baseURL, token, href) -> AUTH_* state. Hits every
 * reachable branch of the precedence rules.
 */

(:test)
function test_deriveInitialAuthState_noUrl_isNoUrl(logger) {
    // No URL wins over everything else.
    return Utils.deriveInitialAuthState(null, "Bearer xyz", "/href") == AUTH_NO_URL;
}

(:test)
function test_deriveInitialAuthState_url_noToken_noHref_isNeedsRequest(logger) {
    return Utils.deriveInitialAuthState("http://x", null, null) == AUTH_NEEDS_REQUEST;
}

(:test)
function test_deriveInitialAuthState_url_hasHref_noToken_isPending(logger) {
    return Utils.deriveInitialAuthState("http://x", null, "/signalk/v1/requests/abc") == AUTH_PENDING;
}

(:test)
function test_deriveInitialAuthState_url_hasToken_isConnected(logger) {
    return Utils.deriveInitialAuthState("http://x", "Bearer xyz", null) == AUTH_CONNECTED;
}

(:test)
function test_deriveInitialAuthState_url_hasTokenAndHref_tokenWins(logger) {
    // Token takes precedence over a lingering pending href.
    return Utils.deriveInitialAuthState("http://x", "Bearer xyz", "/href") == AUTH_CONNECTED;
}

/*
 * deriveConnectivity — full state-transition matrix. Combines URL
 * presence, auth state, last network code, and the discovery-probe
 * outcome into a single CONN_* value rendered on the config view.
 */

(:test)
function test_deriveConn_nullUrl_isNoUrl(logger) {
    return Utils.deriveConnectivity(null, true, true, 200, true) == CONN_NO_URL;
}

(:test)
function test_deriveConn_emptyUrl_isNoUrl(logger) {
    return Utils.deriveConnectivity("", false, false, null, null) == CONN_NO_URL;
}

(:test)
function test_deriveConn_minus1001_isNoHttps(logger) {
    /*
     * -1001 from any request → HTTPS-required policy hit. Wins over
     * every other state except NO_URL.
     */
    return Utils.deriveConnectivity("http://x", false, false, -1001, null) == CONN_NO_HTTPS;
}

(:test)
function test_deriveConn_minus1001_evenWithToken_isNoHttps(logger) {
    return Utils.deriveConnectivity("http://x", true, false, -1001, null) == CONN_NO_HTTPS;
}

(:test)
function test_deriveConn_url_noToken_noHref_isNotAuth(logger) {
    return Utils.deriveConnectivity("http://x", false, false, null, null) == CONN_NOT_AUTH;
}

(:test)
function test_deriveConn_url_noToken_hasHref_isPending(logger) {
    return Utils.deriveConnectivity("http://x", false, true, null, null) == CONN_PENDING;
}

(:test)
function test_deriveConn_url_token_noPollYet_isConnected(logger) {
    // Optimistic: assume connected until first poll says otherwise.
    return Utils.deriveConnectivity("http://x", true, false, null, null) == CONN_CONNECTED;
}

(:test)
function test_deriveConn_url_token_poll200_isConnected(logger) {
    return Utils.deriveConnectivity("http://x", true, false, 200, null) == CONN_CONNECTED;
}

(:test)
function test_deriveConn_url_token_poll401_isNotAuth(logger) {
    /*
     * Token revoked / expired — even though hasToken is still true at
     * the storage layer, the server says no.
     */
    return Utils.deriveConnectivity("http://x", true, false, 401, null) == CONN_NOT_AUTH;
}

(:test)
function test_deriveConn_url_token_poll403_isNotAuth(logger) {
    return Utils.deriveConnectivity("http://x", true, false, 403, null) == CONN_NOT_AUTH;
}

(:test)
function test_deriveConn_url_token_pollMinus300_isNotReachable(logger) {
    // -300 = NETWORK_REQUEST_TIMED_OUT
    return Utils.deriveConnectivity("http://x", true, false, -300, null) == CONN_NOT_REACHABLE;
}

(:test)
function test_deriveConn_url_token_poll503_isNotReachable(logger) {
    return Utils.deriveConnectivity("http://x", true, false, 503, null) == CONN_NOT_REACHABLE;
}

(:test)
function test_deriveConn_url_token_poll404_probeOk_isMissingPlugin(logger) {
    // Server is alive but plugin route doesn't exist.
    return Utils.deriveConnectivity("http://x", true, false, 404, true) == CONN_MISSING_PLUGIN;
}

(:test)
function test_deriveConn_url_token_poll404_probeFail_isNotReachable(logger) {
    /*
     * The 404 actually came from somewhere that isn't the SignalK server
     * (captive portal, wrong port, etc).
     */
    return Utils.deriveConnectivity("http://x", true, false, 404, false) == CONN_NOT_REACHABLE;
}

(:test)
function test_deriveConn_url_token_poll404_probeNull_isMissingPlugin(logger) {
    /*
     * No probe yet — assume MISSING_PLUGIN as the more common case;
     * the probe (if it later runs) can demote to NOT_REACHABLE.
     */
    return Utils.deriveConnectivity("http://x", true, false, 404, null) == CONN_MISSING_PLUGIN;
}

(:test)
function test_deriveConn_url_token_poll400_probeOk_isMissingPlugin(logger) {
    return Utils.deriveConnectivity("http://x", true, false, 400, true) == CONN_MISSING_PLUGIN;
}

(:test)
function test_deriveConn_url_token_poll400_probeFail_isNotReachable(logger) {
    return Utils.deriveConnectivity("http://x", true, false, 400, false) == CONN_NOT_REACHABLE;
}

(:test)
function test_deriveConn_url_token_pollUnknown_isNotReachable(logger) {
    // Defensive default for unmapped codes.
    return Utils.deriveConnectivity("http://x", true, false, 999, null) == CONN_NOT_REACHABLE;
}

(:test)
function test_deriveConn_noHttpsTakesPrecedenceOverPending(logger) {
    /*
     * If somehow we have a pending href but the URL is bad, the actionable
     * state is NO_HTTPS — fixing the URL is the only way out.
     */
    return Utils.deriveConnectivity("http://x", false, true, -1001, null) == CONN_NO_HTTPS;
}
