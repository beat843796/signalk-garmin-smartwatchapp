/*
 * JsonTest.mc
 * Run-No-Evil tests for the Json module. Stripped from release builds
 * by the (:test) annotation. Coverage:
 *   - happy path: empty object, primitives, escapes, nesting, whitespace,
 *     real signalk payload shapes
 *   - error path: malformed input, non-object top-level, truncated input,
 *     missing punctuation
 */

using Toybox.Test;
using Toybox.Lang;

(:test)
function test_json_emptyObject(logger) {
    var d = Json.parse("{}");
    return d instanceof Lang.Dictionary && d.size() == 0;
}

(:test)
function test_json_singleStringField(logger) {
    var d = Json.parse("{\"a\":\"hello\"}");
    return d.get("a").equals("hello");
}

(:test)
function test_json_singleIntField(logger) {
    var d = Json.parse("{\"n\":42}");
    return d.get("n") == 42;
}

(:test)
function test_json_negativeInt(logger) {
    var d = Json.parse("{\"n\":-7}");
    return d.get("n") == -7;
}

(:test)
function test_json_singleFloatField(logger) {
    var d = Json.parse("{\"x\":1.5}");
    var v = d.get("x");
    if (!(v instanceof Lang.Float)) { return false; }
    return v > 1.49 && v < 1.51;
}

(:test)
function test_json_negativeFloat(logger) {
    var d = Json.parse("{\"x\":-3.14}");
    var v = d.get("x");
    if (!(v instanceof Lang.Float)) { return false; }
    return v > -3.15 && v < -3.13;
}

(:test)
function test_json_scientificNotation(logger) {
    var d = Json.parse("{\"x\":1.5e-3}");
    var v = d.get("x");
    if (!(v instanceof Lang.Float)) { return false; }
    return v > 0.00149 && v < 0.00151;
}

(:test)
function test_json_nullValue(logger) {
    var d = Json.parse("{\"a\":null}");
    return d.hasKey("a") && d.get("a") == null;
}

(:test)
function test_json_trueAndFalse(logger) {
    var d = Json.parse("{\"a\":true,\"b\":false}");
    return d.get("a") == true && d.get("b") == false;
}

(:test)
function test_json_nestedObject(logger) {
    var d = Json.parse("{\"outer\":{\"inner\":42}}");
    var inner = d.get("outer");
    return inner instanceof Lang.Dictionary && inner.get("inner") == 42;
}

(:test)
function test_json_multipleFields(logger) {
    var d = Json.parse("{\"a\":1,\"b\":2,\"c\":3}");
    return d.get("a") == 1 && d.get("b") == 2 && d.get("c") == 3;
}

(:test)
function test_json_whitespaceTolerated(logger) {
    var d = Json.parse("  {  \"a\"  :  1  ,  \"b\"  :  2  }  ");
    return d.get("a") == 1 && d.get("b") == 2;
}

(:test)
function test_json_escapedQuoteInString(logger) {
    var d = Json.parse("{\"msg\":\"he said \\\"hi\\\"\"}");
    return d.get("msg").equals("he said \"hi\"");
}

(:test)
function test_json_escapedBackslash(logger) {
    var d = Json.parse("{\"path\":\"\\\\srv\\\\boat\"}");
    return d.get("path").equals("\\srv\\boat");
}

(:test)
function test_json_escapedNewlineAndTab(logger) {
    var d = Json.parse("{\"a\":\"x\\ny\\tz\"}");
    return d.get("a").equals("x\ny\tz");
}

/*
 * Real signalk-server access-poll response shapes. These are the ones
 * we have to handle in production — keep them as canaries.
 */

(:test)
function test_json_signalkAccessPollPending(logger) {
    var d = Json.parse("{\"state\":\"PENDING\"}");
    return d.get("state").equals("PENDING");
}

(:test)
function test_json_signalkAccessPollApproved(logger) {
    var body = "{\"state\":\"COMPLETED\",\"accessRequest\":{\"permission\":\"APPROVED\",\"token\":\"abc.def.ghi\"}}";
    var d = Json.parse(body);
    var ar = d.get("accessRequest");
    if (!(ar instanceof Lang.Dictionary)) { return false; }
    return d.get("state").equals("COMPLETED")
        && ar.get("permission").equals("APPROVED")
        && ar.get("token").equals("abc.def.ghi");
}

(:test)
function test_json_signalkAccessPollDenied(logger) {
    var body = "{\"state\":\"COMPLETED\",\"accessRequest\":{\"permission\":\"DENIED\"}}";
    var d = Json.parse(body);
    var ar = d.get("accessRequest");
    if (!(ar instanceof Lang.Dictionary)) { return false; }
    return ar.get("permission").equals("DENIED");
}

/*
 * Real vessel-data plugin response — flat dict of numeric fields plus a
 * string for autopilotState. This is the hot-path payload, parsed every
 * 1s while CONNECTED.
 */
(:test)
function test_json_signalkVesselData(logger) {
    var body = "{\"speedOverGround\":5.2,\"depthBelowTransducer\":12.34,\"windSpeedApparent\":7.1,\"autopilotState\":\"auto\"}";
    var d = Json.parse(body);
    var sog = d.get("speedOverGround");
    if (!(sog instanceof Lang.Float)) { return false; }
    return sog > 5.19 && sog < 5.21
        && d.get("autopilotState").equals("auto");
}

/*
 * Error path — every malformed input must raise ParseError. The tests
 * assert that ParseError specifically is caught (not just any exception
 * — a NullPointer or whatever would indicate a parser bug, not the
 * intended rejection path).
 */

(:test)
function test_json_emptyString_throws(logger) {
    try {
        Json.parse("");
        return false;
    } catch (e instanceof Json.ParseError) {
        return true;
    }
}

(:test)
function test_json_topLevelArray_throws(logger) {
    try {
        Json.parse("[1,2,3]");
        return false;
    } catch (e instanceof Json.ParseError) {
        return true;
    }
}

(:test)
function test_json_topLevelString_throws(logger) {
    try {
        Json.parse("\"hello\"");
        return false;
    } catch (e instanceof Json.ParseError) {
        return true;
    }
}

(:test)
function test_json_topLevelNumber_throws(logger) {
    try {
        Json.parse("42");
        return false;
    } catch (e instanceof Json.ParseError) {
        return true;
    }
}

(:test)
function test_json_unterminatedObject_throws(logger) {
    try {
        Json.parse("{");
        return false;
    } catch (e instanceof Json.ParseError) {
        return true;
    }
}

(:test)
function test_json_unterminatedString_throws(logger) {
    try {
        Json.parse("{\"a\":\"hi");
        return false;
    } catch (e instanceof Json.ParseError) {
        return true;
    }
}

(:test)
function test_json_missingColon_throws(logger) {
    try {
        Json.parse("{\"a\"}");
        return false;
    } catch (e instanceof Json.ParseError) {
        return true;
    }
}

(:test)
function test_json_missingValue_throws(logger) {
    try {
        Json.parse("{\"a\":}");
        return false;
    } catch (e instanceof Json.ParseError) {
        return true;
    }
}

(:test)
function test_json_garbage_throws(logger) {
    try {
        Json.parse("not json");
        return false;
    } catch (e instanceof Json.ParseError) {
        return true;
    }
}

(:test)
function test_json_trailingData_throws(logger) {
    try {
        Json.parse("{} extra");
        return false;
    } catch (e instanceof Json.ParseError) {
        return true;
    }
}

(:test)
function test_json_unsupportedEscape_throws(logger) {
    try {
        Json.parse("{\"a\":\"\\q\"}");
        return false;
    } catch (e instanceof Json.ParseError) {
        return true;
    }
}
