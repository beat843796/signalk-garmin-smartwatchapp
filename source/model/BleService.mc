/*
 * BleService.mc
 * Owns the BLE peripheral connection lifecycle and the per-view
 * read loop. Wrapped by BleVesselConnect (the VesselConnect facade);
 * views never touch BleService directly — they go through
 * vessel.connect.{startConnect,cancelConnect,disconnect,...}.
 *
 * Connection model — match by service UUID:
 *   1. On startConnect(): scan for advertisements.
 *   2. On a result whose advertised service UUIDs include the SignalK
 *      Vessel Data UUID (5b9a0001-…), pair it.
 *   3. CIQ fires onConnectedStateChanged(CONNECTED) once the GATT link
 *      is up; we flip state to BLE_CONNECTED and fire the optional
 *      success callback.
 *
 * Why service-UUID matching, not name matching: bleno on the Pi parks
 * the local-name field in the SCAN_RSP (not the ADV) when a 128-bit
 * service UUID consumes the 31-byte ADV budget. CIQ on this device
 * doesn't merge SCAN_RSP into ScanResult, so getDeviceName() comes back
 * null. The service UUID is custom and unique to the plugin, so any
 * device advertising it is by construction a SignalK peripheral.
 *
 * Data delivery model — read-after-completion, ONE characteristic at
 * a time:
 *   The plugin exposes three characteristics (NAV / ENV / AP) each
 *   carrying the data displayed by exactly one watch view. Each view's
 *   onShow calls beginDataStreaming(charUuidStr) with its own
 *   characteristic; only that characteristic is read. While
 *   streaming, we keep one read on the wire at a time;
 *   onCharacteristicRead applies the payload via the matching
 *   per-char applyXxxData() and immediately fires the next read.
 *
 *   Why per-characteristic reads: CIQ does not implement long reads
 *   and does not expose MTU negotiation, so the default 22-byte read
 *   ceiling is hard. The plugin's three characteristics are sized
 *   below that ceiling so each can be read in a single ATT exchange.
 *   Reading only the active view's characteristic also saves radio
 *   time (and therefore battery) and matches the bandwidth shape of
 *   the data: NAV updates fast, ENV slowly, AP changes when the user
 *   is on the autopilot screen.
 *
 * Scan keepalive — purely event-driven via onScanStateChange. The
 * scan duty cycle is owned by CIQ; we just declare the intent to be
 * scanning via wantToScan. If CIQ ever reports the scanner dropped
 * to OFF while we still want it (state==CONNECTING), we re-arm it.
 * No fixed-period timer — periodically restarting an already-running
 * scan only burns scan-window time on the radio.
 *
 * Singleton ownership of Ble.setDelegate(self) — only one BLE delegate
 * can be active in CIQ at any time.
 */

using Toybox.BluetoothLowEnergy as Ble;
using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

class BleService extends Ble.BleDelegate {

    /*
     * SignalK Vessel Data service / characteristics — see plugin's
     * ble.js. Char UUID strings live in BleCharUuids (Constants.mc) so
     * views can pass them to beginDataStreaming.
     */

    /*
     * VesselModel reference for data write-back (applyNavData /
     * applyEnvData / applyApData). Was previously read from a global;
     * passed in explicitly now so BleService doesn't depend on global
     * state and can be tested in isolation.
     */
    private var vessel = null;

    /*
     * Link-state observer — typically the BleVesselConnect facade.
     * Notified on CONNECTED / DISCONNECTED transitions so the facade
     * can do facade-y things (status redraw, glance snapshot fragment)
     * without coupling BleService to view-layer concerns.
     */
    private var linkObserver = null;

    private const READ_RECOVERY_INTERVAL_MS = 500;

    private var state = BLE_DISCONNECTED;

    /*
     * Set to the advertised name on successful pair when CIQ surfaces
     * it. May remain null when neither the ScanResult nor the post-pair
     * device.getName() exposes a name (CIQ on this platform parks the
     * local name in SCAN_RSP rather than ADV — see file header). Views
     * render "Connected" / "Not Connected" when null rather than
     * pretending a name we don't actually have.
     */
    private var connectedDeviceName = null;

    // Ble.Device handle once CONNECTION_STATE_CONNECTED arrives.
    private var pairedDevice = null;

    // One-shot success callback registered by the spinner view.
    private var onConnectedCallback = null;

    private var profileRegistered = false;

    /*
     * True between startScan() and stopScan() — i.e. while we want
     * the CIQ scanner to be running. Read by onScanStateChange to
     * tell a deliberate stop (we set this false right before calling
     * setScanState(OFF)) from a CIQ-side stop we should recover from.
     */
    private var wantToScan = false;

    /*
     * View-driven streaming target. Set by beginDataStreaming(uuidStr)
     * with the UUID of the characteristic the active view wants to
     * read; cleared (back to null) by endDataStreaming(). Non-null
     * means "loop is desired" — keeps one read on the wire at a time
     * targeting that UUID. Switching the UUID transitions the loop
     * onto a new char on the next read.
     *
     * `streamingCharUuid` caches the matching Ble.Uuid object so the
     * read-loop hot path doesn't re-parse it on every iteration.
     */
    private var streamingCharUuidStr = null;
    private var streamingCharUuid = null;

    /*
     * True between requestRead() and the matching onCharacteristicRead;
     * gates the next requestRead so we never have two reads outstanding.
     */
    private var readInFlight = false;

    /*
     * True between requestWrite() on the CMD char and the matching
     * onCharacteristicWrite. CIQ serializes the BLE radio — issuing a
     * write while a read is in flight (or vice versa) throws
     * "Operation already in Progress". The read loop and writeCmd
     * both check this so they never trip over each other.
     */
    private var writeInFlight = false;

    /*
     * Single-slot pending-CMD queue. While a read or write is in
     * flight, sendAutopilotXxx stashes its payload here instead of
     * calling requestWrite directly; the next onCharacteristicRead /
     * onCharacteristicWrite drains the queue before firing the next
     * read. Last-press-wins: a second sendAutopilotXxx that arrives
     * before the first has dispatched replaces the earlier payload.
     * That matches the user's intent for autopilot taps (the latest
     * adjustment is what they want).
     */
    private var pendingCmdPayload = null;
    private var pendingCmdLabel = null;

    private var readRecoveryTimer = null;

    /*
     * Pre-built Uuid objects for the service + four characteristics.
     * Set in initialize() so the read loop and dispatch don't allocate
     * a Uuid on every read response or read iteration. CMD is
     * write-only — it isn't part of the read loop, but we keep its
     * Uuid handy for sendAutopilotCommand.
     */
    private var serviceUuid = null;
    private var navCharUuid = null;
    private var envCharUuid = null;
    private var apCharUuid  = null;
    private var cmdCharUuid = null;

    /*
     * Diagnostic counters for the [BLE] logs — confirm that the read
     * pipeline is actually delivering, not just that the link is up.
     */
    private var readCount = 0;
    private var lastReadLogAt = 0;

    function initialize(vesselRef, observer) {
        BleDelegate.initialize();
        vessel = vesselRef;
        linkObserver = observer;
        Ble.setDelegate(self);
        serviceUuid = Ble.stringToUuid(BleCharUuids.SERVICE);
        navCharUuid = Ble.stringToUuid(BleCharUuids.NAV);
        envCharUuid = Ble.stringToUuid(BleCharUuids.ENV);
        apCharUuid  = Ble.stringToUuid(BleCharUuids.AP);
        cmdCharUuid = Ble.stringToUuid(BleCharUuids.CMD);
        registerProfileOnce();
        System.println("[BLE] service initialised");
    }

    function getState() as Lang.Number {
        return state;
    }

    function isConnected() as Lang.Boolean {
        return state == BLE_CONNECTED;
    }

    function getConnectedDeviceName() as Lang.String or Null {
        return connectedDeviceName;
    }

    /*
     * Begins the connect flow. Idempotent — repeated calls while already
     * CONNECTING or CONNECTED are no-ops. The success callback fires
     * exactly once on transition to CONNECTED, then is cleared.
     */
    function startConnect(onConnectedCb) as Void {
        if (state == BLE_CONNECTED) {
            System.println("[BLE] startConnect ignored — already connected");
            return;
        }
        if (state == BLE_CONNECTING) {
            System.println("[BLE] startConnect ignored — already connecting");
            // Replace the callback in case a second view is awaiting it.
            onConnectedCallback = onConnectedCb;
            return;
        }
        registerProfileOnce();
        onConnectedCallback = onConnectedCb;
        state = BLE_CONNECTING;
        System.println("[BLE] startConnect — scanning for SignalK service UUID");
        startScan();
    }

    /*
     * Called once at app start. If the user has previously paired at
     * least once and not subsequently hit Disconnect, kicks a
     * background scan for the SignalK service — same machinery as
     * startConnect, but with no spinner view, no completion callback,
     * and no user interaction. The data views simply transition from
     * "—" to live values once the peripheral is found and paired.
     *
     * Returns true if the autoconnect flag was set (i.e. we kicked a
     * scan), so the caller can pick the right initial view: with
     * autoconnect on, landing on the data view makes sense even
     * though BLE is still pre-CONNECTED at this exact instant.
     */
    function tryAutoconnect() as Lang.Boolean {
        var stored = Storage.getValue(StorageKeys.BLE_AUTOCONNECT);
        if (stored != true) {
            return false;
        }
        if (state != BLE_DISCONNECTED) {
            return false;
        }
        System.println("[BLE] tryAutoconnect — sticky flag set, kicking silent scan");
        startConnect(null);
        return true;
    }

    function cancelConnect() as Void {
        System.println("[BLE] cancelConnect");
        stopScan();
        if (pairedDevice != null) {
            try {
                Ble.unpairDevice(pairedDevice);
            } catch (e) {
                System.println("[BLE] unpair on cancel failed: " + e.getErrorMessage());
            }
        }
        pairedDevice = null;
        connectedDeviceName = null;
        onConnectedCallback = null;
        if (state != BLE_CONNECTED) {
            state = BLE_DISCONNECTED;
        }
    }

    /*
     * Called by data-displaying views (VesselDataView / TempView /
     * AutopilotView) in onShow with the characteristic UUID their view
     * cares about. Only that characteristic is read; the other two
     * remain idle. Switching characteristics (user navigates from
     * VesselDataView to TempView) just calls beginDataStreaming with
     * the new UUID — the read loop transitions on the next iteration.
     */
    function beginDataStreaming(charUuidStr as Lang.String) as Void {
        if (streamingCharUuidStr != null && streamingCharUuidStr.equals(charUuidStr)) {
            return;
        }
        System.println("[BLE] beginDataStreaming uuid=" + charUuidStr);
        streamingCharUuidStr = charUuidStr;
        streamingCharUuid = uuidObjectForCharStr(charUuidStr);
        if (state == BLE_CONNECTED && !readInFlight) {
            fireRead();
        }
    }

    /*
     * Called by StatusView.onShow (or anywhere else that wants to
     * stop pulling data over BLE). Lets the in-flight read complete
     * and then idles — the loop self-terminates because the next
     * fireRead bails on the null streaming UUID. Idempotent.
     *
     * Critically does NOT stop the read-recovery timer: page
     * transitions can fire endDataStreaming → beginDataStreaming in
     * quick succession (faster than RECOVERY_INTERVAL_MS), and if we
     * killed the recovery timer here, post-pair service discovery
     * would never get its 500 ms slot to retry. The timer fires
     * harmlessly when streamingCharUuid is null (fireRead returns
     * early without rescheduling), so leaving it armed is safe and
     * lets discovery actually complete.
     */
    function endDataStreaming() as Void {
        if (streamingCharUuidStr == null) {
            return;
        }
        System.println("[BLE] endDataStreaming");
        streamingCharUuidStr = null;
        streamingCharUuid = null;
    }

    /*
     * Maps the public char-UUID string to the cached Ble.Uuid object,
     * so the read loop never has to allocate one. Returns null on an
     * unknown string (e.g. a CMD UUID accidentally passed to the
     * read-driven streaming API).
     */
    private function uuidObjectForCharStr(s as Lang.String) as Ble.Uuid or Null {
        if (s.equals(BleCharUuids.NAV)) { return navCharUuid; }
        if (s.equals(BleCharUuids.ENV)) { return envCharUuid; }
        if (s.equals(BleCharUuids.AP))  { return apCharUuid;  }
        return null;
    }

    /*
     * ============== Autopilot command write surface ==============
     * Used by VesselModel when BLE is the active transport for AP
     * commands. Each method binary-encodes the action (per
     * Constants.BleCmdAction) and writes it to the CMD characteristic
     * with a Write Request (ATT-acked via onCharacteristicWrite).
     *
     * Returns true if the write was successfully queued; the caller
     * fires-and-forgets — successful submission means CIQ accepted the
     * write into its queue, the actual ATT ACK comes back later via
     * onCharacteristicWrite. False from these methods means the link
     * isn't ready (not CONNECTED, char not yet discovered, queue full).
     */

    function sendAutopilotSetState(stateName as Lang.String) as Lang.Boolean {
        var code = stateNameToCode(stateName);
        if (code == 0) {
            System.println("[BLE] CMD setState rejected — unknown state '" + stateName + "'");
            return false;
        }
        var payload = [BleCmdAction.SET_STATE, code]b;
        return writeCmd(payload, "setState(" + stateName + ")");
    }

    function sendAutopilotChangeHeading(degrees as Lang.Number) as Lang.Boolean {
        var d = degrees;
        if (d < -180) { d = -180; }
        if (d >  180) { d =  180; }
        var lo = d & 0xFF;
        var hi = (d >> 8) & 0xFF;
        var payload = [BleCmdAction.CHANGE_HEADING, lo, hi]b;
        return writeCmd(payload, "changeHeading(" + d + ")");
    }

    /*
     * Public entry point for command writes. If the BLE radio is
     * busy (read or write in flight), queues the payload — last-press
     * wins — and returns true. Otherwise dispatches immediately.
     * Returns false only on a hard precondition fail (not connected,
     * service/char not discovered) — caller can fall back to REST.
     */
    private function writeCmd(payload as Lang.ByteArray, label as Lang.String) as Lang.Boolean {
        if (state != BLE_CONNECTED || pairedDevice == null) {
            System.println("[BLE] CMD " + label + " skipped — not connected");
            return false;
        }
        if (readInFlight || writeInFlight) {
            if (pendingCmdPayload != null) {
                System.println("[BLE] CMD pending replaced (was: " + pendingCmdLabel + ")");
            }
            pendingCmdPayload = payload;
            pendingCmdLabel = label;
            System.println("[BLE] CMD " + label + " queued behind in-flight op");
            return true;
        }
        return dispatchCmd(payload, label);
    }

    /*
     * Actually issues the requestWrite on the CMD characteristic.
     * Caller must guarantee no other op is in flight. Sets
     * writeInFlight on success so the read loop pauses until the
     * matching onCharacteristicWrite fires.
     */
    private function dispatchCmd(payload as Lang.ByteArray, label as Lang.String) as Lang.Boolean {
        try {
            var service = pairedDevice.getService(serviceUuid);
            if (service == null) {
                System.println("[BLE] CMD " + label + " skipped — service not discovered");
                return false;
            }
            var ch = service.getCharacteristic(cmdCharUuid);
            if (ch == null) {
                System.println("[BLE] CMD " + label + " skipped — CMD char not discovered");
                return false;
            }
            ch.requestWrite(payload, { :writeType => Ble.WRITE_TYPE_WITH_RESPONSE });
            writeInFlight = true;
            System.println("[BLE] CMD " + label + " sent (" + payload.size() + " bytes)");
            return true;
        } catch (e) {
            System.println("[BLE] CMD " + label + " threw: " + e.getErrorMessage());
            return false;
        }
    }

    /*
     * If a CMD has been queued behind the just-completed read/write,
     * dispatch it now. Returns true when the queue was drained — caller
     * should NOT fire the next read in that case (let the write
     * complete first). Returns false when the queue was empty.
     */
    private function drainPendingCmd() as Lang.Boolean {
        if (pendingCmdPayload == null) { return false; }
        if (state != BLE_CONNECTED) { return false; }
        var p = pendingCmdPayload;
        var l = pendingCmdLabel;
        pendingCmdPayload = null;
        pendingCmdLabel = null;
        dispatchCmd(p, l);
        return true;
    }

    private function stateNameToCode(name as Lang.String) as Lang.Number {
        if (name.equals(ApStates.STANDBY)) { return 1; }
        if (name.equals(ApStates.AUTO))    { return 2; }
        if (name.equals(ApStates.WIND))    { return 3; }
        if (name.equals(ApStates.ROUTE))   { return 4; }
        return 0;
    }

    /*
     * Tears down the GATT link, scan, timers, and pending state. Does
     * NOT touch the sticky BLE_AUTOCONNECT flag — used by app-shutdown
     * (onStop) and transport-switch teardown, both of which must
     * preserve the sticky flag so a future launch / switch-back will
     * autoconnect.
     */
    function teardownLink() as Void {
        System.println("[BLE] teardownLink");
        var wasConnected = (state == BLE_CONNECTED);
        stopReadRecoveryTimer();
        stopScan();
        if (pairedDevice != null) {
            try {
                Ble.unpairDevice(pairedDevice);
            } catch (e) {
                System.println("[BLE] unpair failed: " + e.getErrorMessage());
            }
        }
        pairedDevice = null;
        connectedDeviceName = null;
        onConnectedCallback = null;
        readInFlight = false;
        writeInFlight = false;
        pendingCmdPayload = null;
        pendingCmdLabel = null;
        readCount = 0;
        state = BLE_DISCONNECTED;
        if (wasConnected && linkObserver != null) {
            linkObserver.onLinkDisconnected();
        }
    }

    /*
     * User-initiated opt-out — Config menu's Disconnect item. Clears
     * the sticky autoconnect flag so the next app launch does NOT
     * silently rescan, then tears down the link. The glance snapshot
     * is left alone — it's only rewritten on connection-type change
     * or when leaving AutopilotView.
     */
    function disconnect() as Void {
        System.println("[BLE] disconnect (user opt-out)");
        Storage.deleteValue(StorageKeys.BLE_AUTOCONNECT);
        teardownLink();
    }

    /*
     * ============== Internals ==============
     */

    private function registerProfileOnce() as Void {
        if (profileRegistered) {
            return;
        }
        try {
            /*
             * CIQ's registerProfile schema requires `:descriptors` to
             * be present (omitting the key crashes the runtime during
             * onProfileRegister dispatch). We pass an empty Uuid
             * array because we never touch any descriptors — reads
             * don't need them, writes don't need them, and we don't
             * subscribe via CCCD. Skipping the descriptor walk after
             * CONNECTED also shaves a few ATT round-trips off
             * GATT-discovery time before the first read can fire.
             */
            var noDescriptors = new [0];
            var profile = {
                :uuid => serviceUuid,
                :characteristics => [
                    { :uuid => navCharUuid, :descriptors => noDescriptors },
                    { :uuid => envCharUuid, :descriptors => noDescriptors },
                    { :uuid => apCharUuid,  :descriptors => noDescriptors },
                    { :uuid => cmdCharUuid, :descriptors => noDescriptors }
                ]
            };
            Ble.registerProfile(profile);
            profileRegistered = true;
            System.println("[BLE] profile registered (NAV/ENV/AP/CMD)");
        } catch (e) {
            /*
             * Already-registered errors aren't fatal — pairing can still
             * happen, we just won't get characteristic discovery.
             */
            System.println("[BLE] registerProfile failed: " + e.getErrorMessage());
        }
    }

    private function startScan() as Void {
        wantToScan = true;
        try {
            Ble.setScanState(Ble.SCAN_STATE_SCANNING);
        } catch (e) {
            System.println("[BLE] setScanState(SCANNING) failed: " + e.getErrorMessage());
        }
    }

    private function stopScan() as Void {
        wantToScan = false;
        try {
            Ble.setScanState(Ble.SCAN_STATE_OFF);
        } catch (e) {
            // Scan may already be off; not actionable.
        }
    }

    /*
     * ============== BleDelegate hooks ==============
     */

    function onScanResults(scanResults as Ble.Iterator) as Void {
        var raw = scanResults.next();
        while (raw != null) {
            if (raw instanceof Ble.ScanResult) {
                if (state == BLE_CONNECTING && advertisesSignalKService(raw)) {
                    var advertisedName = raw.getDeviceName();
                    System.println("[BLE] match by service UUID — pairing '"
                        + (advertisedName != null ? advertisedName : "<no name>")
                        + "' rssi=" + raw.getRssi());
                    stopScan();
                    try {
                        Ble.pairDevice(raw);
                        /*
                         * Only assign when CIQ actually gave us a name.
                         * Otherwise leave null and try device.getName()
                         * post-pair in onConnectedStateChanged.
                         */
                        if (advertisedName != null && advertisedName.length() > 0) {
                            connectedDeviceName = advertisedName;
                        }
                    } catch (e) {
                        System.println("[BLE] pairDevice failed: " + e.getErrorMessage());
                        /*
                         * Pair throw never reaches onConnectedStateChanged,
                         * so the DISCONNECTED scan-resume path won't
                         * fire — kick the scanner back on here.
                         */
                        if (state == BLE_CONNECTING) {
                            startScan();
                        }
                    }
                    return;
                }
            }
            raw = scanResults.next();
        }
    }

    /*
     * Returns true iff the scan result advertises the SignalK Vessel
     * Data service UUID. Both the iterator entries and the constant we
     * compare against are Ble.Uuid instances; .equals() handles the
     * comparison.
     */
    private function advertisesSignalKService(sr as Ble.ScanResult) as Lang.Boolean {
        try {
            var iter = sr.getServiceUuids();
            if (iter == null) {
                return false;
            }
            var u = iter.next();
            while (u != null) {
                if (u.equals(serviceUuid)) {
                    return true;
                }
                u = iter.next();
            }
        } catch (e) {
            // Ignore — treat as no match.
        }
        return false;
    }

    function onConnectedStateChanged(device as Ble.Device, ciqState as Ble.ConnectionState) as Void {
        System.println("[BLE] connectedStateChanged state=" + ciqState);
        if (ciqState == Ble.CONNECTION_STATE_CONNECTED) {
            /*
             * Late-CONNECTED guard: if the user cancelled while a pair
             * was already in flight, BleService is now BLE_DISCONNECTED.
             * Don't promote a stale link to CONNECTED — unpair instead
             * so we don't keep an orphan radio link the user thinks
             * they cancelled.
             */
            if (state != BLE_CONNECTING) {
                System.println("[BLE] late CONNECTED in state=" + state + " — unpairing");
                try { Ble.unpairDevice(device); } catch (e) { /* ignore */ }
                return;
            }
            pairedDevice = device;
            if (connectedDeviceName == null && device != null) {
                try {
                    var dn = device.getName();
                    if (dn != null && dn.length() > 0) {
                        connectedDeviceName = dn;
                    }
                } catch (e) {
                    // Some CIQ versions throw if the name is not yet cached.
                }
            }
            /*
             * If still null, leave it that way — the UI renders
             * "Connected" rather than fabricating a name.
             */
            state = BLE_CONNECTED;
            stopScan();
            /*
             * Sticky autoconnect: now that we've paired at least
             * once, future app launches will auto-scan for this
             * service without the spinner. Cleared by disconnect().
             */
            Storage.setValue(StorageKeys.BLE_AUTOCONNECT, true);
            System.println("[BLE] connected to '" + connectedDeviceName + "'");

            /*
             * Notify the facade so it can redraw status views and
             * persist a glance snapshot fragment.
             */
            if (linkObserver != null) {
                linkObserver.onLinkConnected();
            }

            /*
             * Start the read loop only if a data view has asked for
             * streaming. If we just landed back on StatusView after
             * the connect spinner pop, streamingCharUuid is null and
             * we simply hold the GATT link idle.
             */
            if (streamingCharUuid != null) {
                fireRead();
            }

            if (onConnectedCallback != null) {
                var cb = onConnectedCallback;
                onConnectedCallback = null;
                try {
                    cb.invoke();
                } catch (e) {
                    System.println("[BLE] onConnected callback threw: " + e.getErrorMessage());
                }
            }
        } else if (ciqState == Ble.CONNECTION_STATE_DISCONNECTED) {
            var wasConnected = (state == BLE_CONNECTED);
            var wasConnecting = (state == BLE_CONNECTING);
            pairedDevice = null;
            connectedDeviceName = null;
            readInFlight = false;
            writeInFlight = false;
            pendingCmdPayload = null;
            pendingCmdLabel = null;
            stopReadRecoveryTimer();
            if (wasConnected) {
                state = BLE_DISCONNECTED;
                System.println("[BLE] peripheral dropped link — state=DISCONNECTED");
                if (linkObserver != null) {
                    linkObserver.onLinkDisconnected();
                }
                WatchUi.requestUpdate();
            } else if (wasConnecting) {
                /*
                 * Pair attempt never reached CONNECTED — keep state at
                 * BLE_CONNECTING and resume scanning so the next advert
                 * gives us another shot.
                 */
                System.println("[BLE] pair attempt failed — resuming scan");
                startScan();
            }
        }
    }

    /*
     * Service discovery completion. CIQ fires this once the GATT services
     * registered via registerProfile have been discovered on the paired
     * device. Kicks the read loop in case fireRead() at CONNECTED time
     * found a null service (race between CONNECTED and discovery).
     */
    function onProfileRegister(uuid as Ble.Uuid, status as Ble.Status) as Void {
        System.println("[BLE] onProfileRegister status=" + status);
        if (state == BLE_CONNECTED && streamingCharUuid != null && !readInFlight) {
            fireRead();
        }
    }

    /*
     * Scan-state keepalive. CIQ owns when scan windows actually run;
     * occasionally it drops the scanner back to OFF on its own (long
     * idle, internal radio scheduling). If that happens while we still
     * want to be scanning (state==CONNECTING and stopScan() wasn't
     * called), re-arm it. Deliberate stops (scan→pair, connect, cancel,
     * teardown) all clear wantToScan first, so this branch leaves
     * those alone.
     */
    function onScanStateChange(scanState as Ble.ScanState, status as Ble.Status) as Void {
        System.println("[BLE] scanState=" + scanState + " status=" + status);
        if (scanState == Ble.SCAN_STATE_OFF
                && wantToScan
                && state == BLE_CONNECTING) {
            System.println("[BLE] scan dropped while we still want it — re-arming");
            startScan();
        }
    }

    /*
     * Write completion for the CMD characteristic. Drains the next
     * queued command (if any), otherwise resumes the read loop.
     */
    function onCharacteristicWrite(characteristic as Ble.Characteristic, status as Ble.Status) as Void {
        writeInFlight = false;
        if (status == Ble.STATUS_SUCCESS) {
            System.println("[BLE] CMD write ACKed");
        } else {
            System.println("[BLE] CMD write failed status=" + status);
        }
        if (drainPendingCmd()) {
            return;
        }
        if (streamingCharUuid != null && state == BLE_CONNECTED) {
            fireRead();
        }
    }

    /*
     * ============== Read loop ==============
     */

    /*
     * Issues one requestRead() on the currently-active characteristic
     * (streamingCharUuid). No-op if no view has asked for streaming,
     * a read is already in flight, the link isn't CONNECTED, or
     * service discovery hasn't surfaced the characteristic yet.
     * Schedules a recovery tick on transient failures so the loop
     * self-heals.
     */
    private function fireRead() as Void {
        if (streamingCharUuid == null) {
            return;
        }
        if (readInFlight || writeInFlight) {
            return;
        }
        if (state != BLE_CONNECTED || pairedDevice == null) {
            return;
        }
        try {
            var service = pairedDevice.getService(serviceUuid);
            if (service == null) {
                System.println("[BLE] fireRead: service not yet discovered — retrying");
                scheduleReadRetry();
                return;
            }
            var ch = service.getCharacteristic(streamingCharUuid);
            if (ch == null) {
                System.println("[BLE] fireRead: characteristic " + streamingCharUuidStr
                    + " missing on service — retrying");
                scheduleReadRetry();
                return;
            }
            ch.requestRead();
            readInFlight = true;
        } catch (e) {
            /*
             * Most commonly Ble.BLE_QUEUE_FULL when the radio is busy.
             * Don't crash the loop — schedule a retry tick.
             */
            System.println("[BLE] requestRead threw: " + e.getErrorMessage());
            readInFlight = false;
            scheduleReadRetry();
        }
    }

    private function scheduleReadRetry() as Void {
        if (readRecoveryTimer != null) {
            return;  // already scheduled
        }
        readRecoveryTimer = new Timer.Timer();
        readRecoveryTimer.start(method(:onReadRecoveryTick), READ_RECOVERY_INTERVAL_MS, false);
    }

    private function stopReadRecoveryTimer() as Void {
        if (readRecoveryTimer != null) {
            readRecoveryTimer.stop();
            readRecoveryTimer = null;
        }
    }

    function onReadRecoveryTick() as Void {
        readRecoveryTimer = null;
        fireRead();
    }

    /*
     * Read completion. status==SUCCESS + a non-null payload → decode
     * via the per-char decoder + apply via the matching VesselModel
     * partial-apply method + fire the next read. Any other outcome
     * schedules a retry as long as a view is still asking for the
     * stream.
     */
    function onCharacteristicRead(characteristic as Ble.Characteristic, status as Ble.Status, value as Lang.ByteArray) as Void {
        readInFlight = false;

        if (status != Ble.STATUS_SUCCESS) {
            System.println("[BLE] read failed status=" + status);
            if (streamingCharUuid != null) {
                scheduleReadRetry();
            }
            return;
        }
        if (value == null) {
            System.println("[BLE] read got null payload");
            if (streamingCharUuid != null) {
                scheduleReadRetry();
            }
            return;
        }

        readCount += 1;
        var now = System.getTimer();
        if (now - lastReadLogAt > 1000) {
            System.println("[BLE] reads=" + readCount);
            lastReadLogAt = now;
        }

        if (vessel != null) {
            applyForCharacteristic(characteristic, value);
            WatchUi.requestUpdate();
        }

        /*
         * If a CMD piled up while this read was in flight, dispatch
         * it now and let the read loop resume from
         * onCharacteristicWrite. Otherwise self-pace: fire the next
         * read immediately. If streamingCharUuid changed since this
         * read was issued (e.g. user swiped to another data view),
         * the next read automatically targets the new char.
         */
        if (drainPendingCmd()) {
            return;
        }
        if (streamingCharUuid != null && state == BLE_CONNECTED) {
            fireRead();
        }
    }

    /*
     * Dispatch the decoded payload to the matching VesselModel
     * partial-apply method based on which characteristic carried it.
     * Each apply method only touches the fields owned by its char,
     * so an in-flight read for an old char (after the user swiped
     * to a new view) doesn't clobber the new view's fields.
     */
    private function applyForCharacteristic(characteristic as Ble.Characteristic, value as Lang.ByteArray) as Void {
        var u = null;
        try {
            u = characteristic.getUuid();
        } catch (e) {
            System.println("[BLE] characteristic.getUuid() threw: " + e.getErrorMessage());
            return;
        }
        if (u == null) {
            return;
        }

        if (u.equals(navCharUuid)) {
            var d = BleVesselDataDecoder.decodeNav(value);
            if (d == null) {
                System.println("[BLE] NAV decode failed (size=" + value.size() + ")");
                return;
            }
            vessel.applyNavData(d);
        } else if (u.equals(envCharUuid)) {
            var d = BleVesselDataDecoder.decodeEnv(value);
            if (d == null) {
                System.println("[BLE] ENV decode failed (size=" + value.size() + ")");
                return;
            }
            vessel.applyEnvData(d);
        } else if (u.equals(apCharUuid)) {
            var d = BleVesselDataDecoder.decodeAp(value);
            if (d == null) {
                System.println("[BLE] AP decode failed (size=" + value.size() + ")");
                return;
            }
            vessel.applyApData(d);
        } else {
            System.println("[BLE] read response for unknown char uuid=" + u);
        }
    }
}
