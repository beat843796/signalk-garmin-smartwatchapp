/*
 * Json.mc
 * Minimal recursive-descent JSON parser. Exists because CIQ's built-in
 * auto-parse via Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON swallows
 * the real HTTP status code on parse failure (replacing it with -400).
 * By requesting TEXT_PLAIN and parsing manually, the transport layer
 * keeps real status codes for proper error classification.
 *
 * Scope: top-level must be an object; supports nested objects, strings
 * with the common escapes, numbers (int/decimal/scientific/negative),
 * true/false/null. No arrays. No \uXXXX escapes. Both are easy to add
 * if real payloads start using them.
 *
 * On any malformed input, throws Json.ParseError with a position hint.
 */

using Toybox.Lang;

module Json {

    /*
     * Thrown for any parse failure. Callers catch by `instanceof`.
     * Field is `mMsg` (not `mMessage`) to avoid collision with the
     * protected variable of the same name on Lang.Exception.
     */
    class ParseError extends Lang.Exception {
        var mMsg;

        function initialize(message as Lang.String) {
            Exception.initialize();
            mMsg = message;
        }

        function getErrorMessage() as Lang.String or Null {
            return mMsg;
        }
    }

    /*
     * Parses `body` as a JSON object. Returns the resulting Dictionary or
     * throws ParseError. Top-level must be an object — top-level arrays,
     * strings, numbers, etc. all throw.
     */
    function parse(body as Lang.String) as Lang.Dictionary {
        var p = new Parser(body);
        p.skipWs();
        var result = p.readValue();
        p.skipWs();
        if (!p.isEnd()) {
            throw new ParseError("trailing data at " + p.pos);
        }
        if (!(result instanceof Lang.Dictionary)) {
            throw new ParseError("top-level must be an object");
        }
        return result;
    }

    /*
     * Internal mutable parser state. One instance per parse() call.
     */
    class Parser {
        var src;     // Lang.String — original body, used for substring extraction
        var chars;   // Lang.Char[] — random access for cheap peek/advance
        var pos;     // Lang.Number — current index into chars
        var len;     // Lang.Number — chars.size()

        function initialize(s as Lang.String) {
            src = s;
            chars = s.toCharArray();
            pos = 0;
            len = chars.size();
        }

        function isEnd() as Lang.Boolean {
            return pos >= len;
        }

        function peek() as Lang.Char {
            return chars[pos];
        }

        function skipWs() as Void {
            while (pos < len) {
                var c = chars[pos];
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                    pos += 1;
                } else {
                    return;
                }
            }
        }

        function readValue() {
            skipWs();
            if (pos >= len) {
                throw new ParseError("unexpected end of input");
            }
            var c = chars[pos];
            if (c == '{') { return readObject(); }
            if (c == '"') { return readString(); }
            if (c == 't' || c == 'f') { return readBool(); }
            if (c == 'n') { return readNull(); }
            if (c == '-' || (c >= '0' && c <= '9')) { return readNumber(); }
            throw new ParseError("unexpected '" + c.toString() + "' at " + pos);
            // strict type checker doesn't recognise throw as terminating
            return null;
        }

        function readObject() as Lang.Dictionary {
            pos += 1; // consume '{'
            var dict = {};
            skipWs();
            if (pos < len && chars[pos] == '}') {
                pos += 1;
                return dict;
            }
            var done = false;
            while (!done) {
                skipWs();
                if (pos >= len || chars[pos] != '"') {
                    throw new ParseError("expected string key at " + pos);
                }
                var key = readString();
                skipWs();
                if (pos >= len || chars[pos] != ':') {
                    throw new ParseError("expected ':' at " + pos);
                }
                pos += 1;
                var value = readValue();
                dict.put(key, value);
                skipWs();
                if (pos >= len) {
                    throw new ParseError("unterminated object");
                }
                var c = chars[pos];
                if (c == ',') {
                    pos += 1;
                } else if (c == '}') {
                    pos += 1;
                    done = true;
                } else {
                    throw new ParseError("expected ',' or '}' at " + pos);
                }
            }
            return dict;
        }

        function readString() as Lang.String {
            pos += 1; // consume opening '"'
            var s = "";
            while (pos < len) {
                var c = chars[pos];
                pos += 1;
                if (c == '"') {
                    return s;
                }
                if (c == '\\') {
                    if (pos >= len) {
                        throw new ParseError("dangling escape at " + pos);
                    }
                    var e = chars[pos];
                    pos += 1;
                    if      (e == '"')  { s += "\""; }
                    else if (e == '\\') { s += "\\"; }
                    else if (e == '/')  { s += "/";  }
                    else if (e == 'n')  { s += "\n"; }
                    else if (e == 't')  { s += "\t"; }
                    else if (e == 'r')  { s += "\r"; }
                    else if (e == 'b')  { s += ""; }
                    else if (e == 'f')  { s += ""; }
                    else {
                        throw new ParseError("unsupported escape \\" + e.toString());
                    }
                } else {
                    s += c.toString();
                }
            }
            throw new ParseError("unterminated string");
        }

        function readBool() as Lang.Boolean {
            if (pos + 4 <= len && src.substring(pos, pos + 4).equals("true")) {
                pos += 4;
                return true;
            }
            if (pos + 5 <= len && src.substring(pos, pos + 5).equals("false")) {
                pos += 5;
                return false;
            }
            throw new ParseError("invalid literal at " + pos);
        }

        function readNull() {
            if (pos + 4 <= len && src.substring(pos, pos + 4).equals("null")) {
                pos += 4;
                return null;
            }
            throw new ParseError("invalid literal at " + pos);
        }

        /*
         * Reads a JSON number. Returns Lang.Number for integer-shaped
         * tokens, Lang.Float for any token containing '.', 'e', or 'E'.
         * Float chosen over Double to match the precision CIQ's
         * Communications layer used to deliver — vessel-data fields are
         * single-precision on the wire.
         */
        function readNumber() {
            var start = pos;
            if (chars[pos] == '-') {
                pos += 1;
            }
            var isFloat = false;
            while (pos < len) {
                var c = chars[pos];
                if (c >= '0' && c <= '9') {
                    pos += 1;
                } else if (c == '.' || c == 'e' || c == 'E') {
                    isFloat = true;
                    pos += 1;
                } else if (c == '+' || c == '-') {
                    // exponent sign — only valid right after e/E. Don't
                    // bother validating here; toFloat() will reject if so.
                    pos += 1;
                } else {
                    break;
                }
            }
            var token = src.substring(start, pos);
            if (isFloat) {
                var f = token.toFloat();
                if (f == null) {
                    throw new ParseError("invalid number '" + token + "'");
                }
                return f;
            }
            var n = token.toNumber();
            if (n == null) {
                throw new ParseError("invalid number '" + token + "'");
            }
            return n;
        }
    }
}
