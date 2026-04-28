/*
 * BleVesselDataDecoderTest.mc
 * Run-No-Evil tests for BleVesselDataDecoder. Stripped from release
 * builds via (:test). Coverage: per-characteristic happy paths,
 * sentinels, sign extension, AP state byte, and structural validation
 * (wrong size, null input).
 */

using Toybox.Test;
using Toybox.Lang;

/*
 * Build a fresh sentinel-filled buffer for a given characteristic. Any
 * byte not explicitly overwritten remains 0xFF, which decodes to a
 * typed sentinel for u16/i16/u32 and to "AP state unknown" for the AP
 * state byte (which we reset to 0 below — its sentinel is 0, not 0xFF).
 */
function bvd_makeBuf(size as Lang.Number) as Lang.ByteArray {
    var buf = new [size]b;
    for (var i = 0; i < size; i++) {
        buf[i] = 0xFF;
    }
    return buf;
}

function bvd_makeNavSentinels() as Lang.ByteArray {
    return bvd_makeBuf(BleVesselDataDecoder.NAV_SIZE);
}

function bvd_makeEnvSentinels() as Lang.ByteArray {
    return bvd_makeBuf(BleVesselDataDecoder.ENV_SIZE);
}

function bvd_makeApSentinels() as Lang.ByteArray {
    var buf = bvd_makeBuf(BleVesselDataDecoder.AP_SIZE);
    // AP-state byte uses 0 (not 0xFF) for "unknown".
    buf[0] = 0x00;
    return buf;
}

function bvd_writeU16LE(buf, offset, value) {
    buf[offset]     = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
}

function bvd_writeI16LE(buf, offset, value) {
    if (value < 0) {
        value = value + 0x10000;
    }
    buf[offset]     = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
}

function bvd_writeU24LE(buf, offset, value) {
    buf[offset]     = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
    buf[offset + 2] = (value >> 16) & 0xFF;
}

function bvd_writeU32LE(buf, offset, value) {
    buf[offset]     = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
    buf[offset + 2] = (value >> 16) & 0xFF;
    buf[offset + 3] = (value >> 24) & 0xFF;
}

/*
 * Returns d.get(key) as a Float, or null if absent or not a Float.
 */
function bvd_getFloat(d as Lang.Dictionary, key as Lang.String) as Lang.Float or Null {
    var v = d.get(key);
    if (v instanceof Lang.Float) {
        return v;
    }
    return null;
}

// ============== NAV characteristic ==============

(:test)
function test_bvd_navAllSentinelsDecodesToNulls(logger) {
    var d = BleVesselDataDecoder.decodeNav(bvd_makeNavSentinels());
    if (d == null) { return false; }
    if (d.get("speedOverGround")      != null) { return false; }
    if (d.get("speedThroughWater")    != null) { return false; }
    if (d.get("depthBelowTransducer") != null) { return false; }
    if (d.get("windAngleApparent")    != null) { return false; }
    if (d.get("windSpeedApparent")    != null) { return false; }
    if (d.get("windSpeedTrue")        != null) { return false; }
    return true;
}

(:test)
function test_bvd_navSpeedOverGround(logger) {
    var buf = bvd_makeNavSentinels();
    bvd_writeU16LE(buf, 0, 521);
    var d = BleVesselDataDecoder.decodeNav(buf);
    if (d == null) { return false; }
    var v = bvd_getFloat(d, "speedOverGround");
    if (v == null) { return false; }
    return v > 5.20 && v < 5.22;
}

(:test)
function test_bvd_navSpeedThroughWater(logger) {
    var buf = bvd_makeNavSentinels();
    bvd_writeU16LE(buf, 2, 410);
    var d = BleVesselDataDecoder.decodeNav(buf);
    if (d == null) { return false; }
    var v = bvd_getFloat(d, "speedThroughWater");
    if (v == null) { return false; }
    return v > 4.09 && v < 4.11;
}

(:test)
function test_bvd_navDepth(logger) {
    var buf = bvd_makeNavSentinels();
    bvd_writeU16LE(buf, 4, 203);
    var d = BleVesselDataDecoder.decodeNav(buf);
    if (d == null) { return false; }
    var v = bvd_getFloat(d, "depthBelowTransducer");
    if (v == null) { return false; }
    return v > 20.29 && v < 20.31;
}

(:test)
function test_bvd_navNegativeWindAngle(logger) {
    var buf = bvd_makeNavSentinels();
    bvd_writeI16LE(buf, 6, -768);
    var d = BleVesselDataDecoder.decodeNav(buf);
    if (d == null) { return false; }
    var v = bvd_getFloat(d, "windAngleApparent");
    if (v == null) { return false; }
    return v > -0.769 && v < -0.767;
}

(:test)
function test_bvd_navWindSpeedTrue(logger) {
    var buf = bvd_makeNavSentinels();
    bvd_writeU16LE(buf, 10, 412);
    var d = BleVesselDataDecoder.decodeNav(buf);
    if (d == null) { return false; }
    var v = bvd_getFloat(d, "windSpeedTrue");
    if (v == null) { return false; }
    return v > 4.11 && v < 4.13;
}

(:test)
function test_bvd_navRejectsTooSmall(logger) {
    return BleVesselDataDecoder.decodeNav(new [4]b) == null;
}

(:test)
function test_bvd_navRejectsNull(logger) {
    return BleVesselDataDecoder.decodeNav(null) == null;
}

// ============== ENV characteristic ==============

(:test)
function test_bvd_envSentinel(logger) {
    var d = BleVesselDataDecoder.decodeEnv(bvd_makeEnvSentinels());
    if (d == null) { return false; }
    return d.get("waterTemperature") == null;
}

(:test)
function test_bvd_envWaterTemperature(logger) {
    var buf = bvd_makeEnvSentinels();
    bvd_writeU16LE(buf, 0, 3132);
    var d = BleVesselDataDecoder.decodeEnv(buf);
    if (d == null) { return false; }
    var v = bvd_getFloat(d, "waterTemperature");
    if (v == null) { return false; }
    return v > 313.19 && v < 313.21;
}

(:test)
function test_bvd_envRejectsTooSmall(logger) {
    return BleVesselDataDecoder.decodeEnv(new [1]b) == null;
}

// ============== AP characteristic ==============

(:test)
function test_bvd_apStateUnknownLeavesKeyAbsent(logger) {
    var d = BleVesselDataDecoder.decodeAp(bvd_makeApSentinels());
    if (d == null) { return false; }
    return !d.hasKey("autopilotState");
}

(:test)
function test_bvd_apStateStandby(logger) {
    var buf = bvd_makeApSentinels();
    buf[0] = 1;
    var d = BleVesselDataDecoder.decodeAp(buf);
    if (d == null) { return false; }
    var s = d.get("autopilotState");
    return s instanceof Lang.String && s.equals("standby");
}

(:test)
function test_bvd_apStateAuto(logger) {
    var buf = bvd_makeApSentinels();
    buf[0] = 2;
    var d = BleVesselDataDecoder.decodeAp(buf);
    if (d == null) { return false; }
    var s = d.get("autopilotState");
    return s instanceof Lang.String && s.equals("auto");
}

(:test)
function test_bvd_apStateWind(logger) {
    var buf = bvd_makeApSentinels();
    buf[0] = 3;
    var d = BleVesselDataDecoder.decodeAp(buf);
    if (d == null) { return false; }
    var s = d.get("autopilotState");
    return s instanceof Lang.String && s.equals("wind");
}

(:test)
function test_bvd_apStateRoute(logger) {
    var buf = bvd_makeApSentinels();
    buf[0] = 4;
    var d = BleVesselDataDecoder.decodeAp(buf);
    if (d == null) { return false; }
    var s = d.get("autopilotState");
    return s instanceof Lang.String && s.equals("route");
}

(:test)
function test_bvd_apStateOutOfRange(logger) {
    var buf = bvd_makeApSentinels();
    buf[0] = 99;
    var d = BleVesselDataDecoder.decodeAp(buf);
    if (d == null) { return false; }
    return !d.hasKey("autopilotState");
}

(:test)
function test_bvd_apCourseAndHeading(logger) {
    var buf = bvd_makeApSentinels();
    bvd_writeU16LE(buf, 1, 3452);
    bvd_writeU16LE(buf, 3, 3571);
    var d = BleVesselDataDecoder.decodeAp(buf);
    if (d == null) { return false; }
    var c = bvd_getFloat(d, "courseOverGroundTrue");
    var h = bvd_getFloat(d, "headingMagnetic");
    if (c == null || c < 3.451 || c > 3.453) { return false; }
    if (h == null || h < 3.570 || h > 3.572) { return false; }
    return true;
}

(:test)
function test_bvd_apTargetHeadings(logger) {
    var buf = bvd_makeApSentinels();
    bvd_writeU16LE(buf, 5, 3000);
    bvd_writeU16LE(buf, 7, 3100);
    bvd_writeI16LE(buf, 9, -231);
    var d = BleVesselDataDecoder.decodeAp(buf);
    if (d == null) { return false; }
    var m = bvd_getFloat(d, "autopilotTargetHeadingMagnetic");
    var t = bvd_getFloat(d, "autopilotTargetHeadingTrue");
    var w = bvd_getFloat(d, "autopilotTargetWindAngleApparent");
    if (m == null || m < 2.999 || m > 3.001) { return false; }
    if (t == null || t < 3.099 || t > 3.101) { return false; }
    if (w == null || w < -0.232 || w > -0.230) { return false; }
    return true;
}

(:test)
function test_bvd_apNegativeRudder(logger) {
    var buf = bvd_makeApSentinels();
    bvd_writeI16LE(buf, 11, -244);
    var d = BleVesselDataDecoder.decodeAp(buf);
    if (d == null) { return false; }
    var v = bvd_getFloat(d, "rudderAngle");
    if (v == null) { return false; }
    return v > -0.245 && v < -0.243;
}

(:test)
function test_bvd_apTripAndLog(logger) {
    var buf = bvd_makeApSentinels();
    bvd_writeU24LE(buf, 13, 12345);
    bvd_writeU32LE(buf, 16, 987654);
    var d = BleVesselDataDecoder.decodeAp(buf);
    if (d == null) { return false; }
    if (d.get("trip")      != 12345)  { return false; }
    if (d.get("log")       != 987654) { return false; }
    if (d.get("tripTotal") != 987654) { return false; }
    return true;
}

(:test)
function test_bvd_apRejectsTooSmall(logger) {
    return BleVesselDataDecoder.decodeAp(new [10]b) == null;
}

(:test)
function test_bvd_apRejectsNull(logger) {
    return BleVesselDataDecoder.decodeAp(null) == null;
}
