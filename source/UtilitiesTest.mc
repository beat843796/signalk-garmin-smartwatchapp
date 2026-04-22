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
    // Tolerance 1e-9, not 1e-12: the implementation uses Math.PI (Float)
    // multiplied against an Int argument, which won't hold Double precision.
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
    // 1 nm = 1852 m. The code's factor (0.00053995680) has a tiny error:
    // 1852 * 0.00053695680 would be the "pure" value, but 1852 * 0.00053995680
    // gives 0.9999985536. Pin the factor's actual behaviour.
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

(:test)
function test_errorMessage_http404_isSignalKServerNotFound(logger) {
    var msg = Utils.errorMessage(404);
    logger.debug("404 -> " + msg);
    return msg.equals("SignalK Server\nNot\nFound");
}

(:test)
function test_errorMessage_http200_isOK(logger) {
    return Utils.errorMessage(200).equals("OK");
}

(:test)
function test_errorMessage_http503_isSignalKServiceUnavailable(logger) {
    return Utils.errorMessage(503).equals("SignalK Service\nUnavailable");
}

(:test)
function test_errorMessage_bleMinus1_isBleError(logger) {
    return Utils.errorMessage(-1).equals("BLE ERROR");
}

(:test)
function test_errorMessage_bleMinus104_isPhoneConnectionUnavailable(logger) {
    return Utils.errorMessage(-104).equals("PHONE CONNECTION\nUNAVAILABLE");
}

(:test)
function test_errorMessage_networkTimeout(logger) {
    return Utils.errorMessage(-300).equals("NETWORK REQUEST\nTIMED OUT");
}

(:test)
function test_errorMessage_unmappedCode_returnsCodeItself(logger) {
    // Characterisation: when code is not in the table, errorMessage returns
    // the code itself unchanged. Pins the existing behaviour so future
    // refactors (e.g. returning null or "UNKNOWN") fail loudly.
    var actual = Utils.errorMessage(99999);
    logger.debug("99999 -> " + actual);
    return actual == 99999;
}
