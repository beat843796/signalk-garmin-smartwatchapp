/*
 * BleVesselDataDecoder.mc
 * Pure decoders for the three Vessel Data BLE characteristics
 * (NAV / ENV / AP) exposed by the signalk-garmin-smartwatchapp-companion plugin.
 * Wire formats and offsets mirror `ble.js`'s CHARACTERISTICS table
 * and the plugin README's per-characteristic offset tables.
 *
 * Each `decodeXxx` takes a ByteArray (the characteristic value the
 * peripheral returned) and produces a *partial* dict of
 * VesselModel-compatible keys: NAV decoder returns NAV-only keys, ENV
 * decoder returns the single ENV key, AP decoder returns AP-only keys.
 *
 * Per-type sentinels (u16=0xFFFF, i16=0x8000, u32=0xFFFFFFFF, AP-state=0)
 * decode to `null`/absent so missing values render as "—" just like a
 * missing REST field. Any malformed input returns `null` from the
 * matching decoder so the caller can drop the packet.
 *
 * The dict keys match VesselModel's per-characteristic apply methods
 * (applyNavData / applyEnvData / applyApData). Keys absent from the
 * dict mean "don't touch the corresponding model field"; explicit
 * null values mean "the wire said this field is absent now."
 */

using Toybox.Lang;

module BleVesselDataDecoder {

    const NAV_SIZE = 12;
    const ENV_SIZE = 2;
    const AP_SIZE  = 20;

    /*
     * Autopilot state byte → SignalK state string. Order must match
     * AP_STATE_CODES in the plugin's ble.js. Index 0 = unknown/unset.
     */
    const AP_STATE_NAMES = [null, ApStates.STANDBY, ApStates.AUTO, ApStates.WIND, ApStates.ROUTE];

    /*
     * Decodes a 12-byte NAV characteristic value:
     *   off 0  u16  speedOverGround        m/s × 100
     *   off 2  u16  speedThroughWater      m/s × 100
     *   off 4  u16  depthBelowTransducer   m × 10
     *   off 6  i16  windAngleApparent      rad × 1000 (±π)
     *   off 8  u16  windSpeedApparent      m/s × 100
     *   off 10 u16  windSpeedTrue          m/s × 100
     */
    function decodeNav(buf as Lang.ByteArray or Null) as Lang.Dictionary or Null {
        if (buf == null || !(buf instanceof Lang.ByteArray)) {
            return null;
        }
        if (buf.size() < NAV_SIZE) {
            return null;
        }
        var dict = {};
        dict["speedOverGround"]      = readU16(buf,  0,  100.0f);
        dict["speedThroughWater"]    = readU16(buf,  2,  100.0f);
        dict["depthBelowTransducer"] = readU16(buf,  4,   10.0f);
        dict["windAngleApparent"]    = readI16(buf,  6, 1000.0f);
        dict["windSpeedApparent"]    = readU16(buf,  8,  100.0f);
        dict["windSpeedTrue"]        = readU16(buf, 10,  100.0f);
        return dict;
    }

    /*
     * Decodes a 2-byte ENV characteristic value:
     *   off 0  u16  waterTemperature       K × 10
     */
    function decodeEnv(buf as Lang.ByteArray or Null) as Lang.Dictionary or Null {
        if (buf == null || !(buf instanceof Lang.ByteArray)) {
            return null;
        }
        if (buf.size() < ENV_SIZE) {
            return null;
        }
        var dict = {};
        dict["waterTemperature"] = readU16(buf, 0, 10.0f);
        return dict;
    }

    /*
     * Decodes a 20-byte AP characteristic value:
     *   off 0   u8   autopilotState
     *   off 1   u16  courseOverGroundTrue              rad × 1000
     *   off 3   u16  headingMagnetic                   rad × 1000
     *   off 5   u16  autopilotTargetHeadingMagnetic    rad × 1000
     *   off 7   u16  autopilotTargetHeadingTrue        rad × 1000
     *   off 9   i16  autopilotTargetWindAngleApparent  rad × 1000
     *   off 11  i16  rudderAngle                       rad × 1000
     *   off 13  u24  trip                              meters
     *   off 16  u32  log                               meters
     *
     * trip is u24 (max ~9050 NM) instead of u32 so the whole AP payload
     * fits the 20-byte CIQ single-read ceiling. log stays u32.
     *
     * `tripTotal` alias is set to the decoded `log` value so VesselModel
     * (which reads tripTotal) gets it without a separate field.
     */
    function decodeAp(buf as Lang.ByteArray or Null) as Lang.Dictionary or Null {
        if (buf == null || !(buf instanceof Lang.ByteArray)) {
            return null;
        }
        if (buf.size() < AP_SIZE) {
            return null;
        }
        var dict = {};

        /*
         * AP state byte. Code 0 = unknown → leave key absent so the
         * partial-apply method doesn't clobber the existing state. Codes
         * outside the mapped range are also treated as unknown.
         */
        var apCode = buf[0] & 0xFF;
        if (apCode > 0 && apCode < AP_STATE_NAMES.size()) {
            var apName = AP_STATE_NAMES[apCode];
            if (apName != null) {
                dict["autopilotState"] = apName;
            }
        }

        dict["courseOverGroundTrue"]             = readU16(buf,  1, 1000.0f);
        dict["headingMagnetic"]                  = readU16(buf,  3, 1000.0f);
        dict["autopilotTargetHeadingMagnetic"]   = readU16(buf,  5, 1000.0f);
        dict["autopilotTargetHeadingTrue"]       = readU16(buf,  7, 1000.0f);
        dict["autopilotTargetWindAngleApparent"] = readI16(buf,  9, 1000.0f);
        dict["rudderAngle"]                      = readI16(buf, 11, 1000.0f);

        var trip = readU24(buf, 13);
        var log  = readU32(buf, 16);
        dict["trip"]      = trip;
        dict["log"]       = log;
        /*
         * VesselModel reads "tripTotal" — alias log → tripTotal so
         * existing formatters keep working without any extra wiring.
         */
        dict["tripTotal"] = log;

        return dict;
    }

    /*
     * Little-endian u16. Sentinel 0xFFFF → null. Otherwise returns
     * value / scale as a Float so downstream formatters get fractional
     * precision (e.g. m/s × 100 → 0.01 m/s resolution).
     */
    function readU16(buf as Lang.ByteArray, offset as Lang.Number, scale as Lang.Float) as Lang.Float or Null {
        var lo = buf[offset] & 0xFF;
        var hi = buf[offset + 1] & 0xFF;
        var v = (hi << 8) | lo;
        if (v == 0xFFFF) {
            return null;
        }
        return v.toFloat() / scale;
    }

    /*
     * Little-endian i16. Sentinel 0x8000 (= -32768) → null. Sign
     * extension: values with bit 15 set are interpreted as negative.
     */
    function readI16(buf as Lang.ByteArray, offset as Lang.Number, scale as Lang.Float) as Lang.Float or Null {
        var lo = buf[offset] & 0xFF;
        var hi = buf[offset + 1] & 0xFF;
        var v = (hi << 8) | lo;
        if (v == 0x8000) {
            return null;
        }
        if ((v & 0x8000) != 0) {
            v = v - 0x10000;
        }
        return v.toFloat() / scale;
    }

    /*
     * Little-endian u24 in meters. Sentinel 0xFFFFFF → null.
     */
    function readU24(buf as Lang.ByteArray, offset as Lang.Number) as Lang.Number or Null {
        var b0 = buf[offset]     & 0xFF;
        var b1 = buf[offset + 1] & 0xFF;
        var b2 = buf[offset + 2] & 0xFF;
        if (b0 == 0xFF && b1 == 0xFF && b2 == 0xFF) {
            return null;
        }
        return (b2 << 16) | (b1 << 8) | b0;
    }

    /*
     * Little-endian u32 in meters. Sentinel 0xFFFFFFFF → null.
     */
    function readU32(buf as Lang.ByteArray, offset as Lang.Number) as Lang.Number or Null {
        var b0 = buf[offset]     & 0xFF;
        var b1 = buf[offset + 1] & 0xFF;
        var b2 = buf[offset + 2] & 0xFF;
        var b3 = buf[offset + 3] & 0xFF;
        if (b0 == 0xFF && b1 == 0xFF && b2 == 0xFF && b3 == 0xFF) {
            return null;
        }
        return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0;
    }
}
