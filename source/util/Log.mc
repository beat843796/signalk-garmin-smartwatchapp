/*
 * Log.mc
 * Tiny logging facade. Debug builds forward to System.println; release
 * builds compile to a no-op stub so the println calls and their string
 * concatenations no longer execute on device. The argument expression
 * is still evaluated at the call site (Monkey C annotations operate at
 * function/class granularity, not statement), but the println syscall
 * and its overhead are stripped.
 *
 * Build wiring lives in monkey.jungle:
 *   base.excludeAnnotations = release
 * Default builds (monkeyc) drop the (:release) stub and keep the real
 * one. Release builds must invoke monkeyc with `-r -x debug` so the
 * (:debug) version is excluded and the (:release) no-op takes over.
 */

using Toybox.System;
using Toybox.Lang;

module Log {

    (:debug)
    function d(msg as Lang.String) as Void {
        System.println(msg);
    }

    (:release)
    function d(msg as Lang.String) as Void {
    }
}
