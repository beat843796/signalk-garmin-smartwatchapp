/*
 * Log.mc
 * Tiny logging facade. Forwards to System.println in all builds.
 */

using Toybox.System;
using Toybox.Lang;

module Log {

    function d(msg as Lang.String) as Void {
        System.println(msg);
    }
}
