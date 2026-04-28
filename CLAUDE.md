# CLAUDE.md

Guidance for future Claude Code sessions working on this repository.

## What this project is

A Connect IQ **watch-app** for Garmin smartwatches that displays SignalK
marine data and controls a Raymarine-compatible autopilot. Talks HTTP to a
SignalK node server on the user's boat LAN (typically a Raspberry Pi), and
relies on two server-side plugins:

- `signalk-raymarine-autopilot` — autopilot commands (sibling repo)
- `signalk-minimalvesseldata-plugin` — the vessel-data REST endpoint (sibling repo)
- `signalk-autopilot-deltasim` — optional: emits fake autopilot deltas for local dev (sibling repo)

**Authentication:** the app uses SignalK's *device access request* flow.
No credentials ever typed on the watch. On first launch the app POSTs a
one-time request to `/signalk/v1/access/requests`; an admin approves it
via the SignalK admin UI; the resulting JWT is stored and used as a
`Bearer` token for subsequent calls.

**Plugin endpoints are under `/signalk/v1/api/...`** (NOT `/plugins/...`).
signalk-server's tokensecurity hardcodes `/plugins/*` as admin-only, but
`/signalk/v1/api/*` accepts readwrite tokens (for GETs) and readwrite+admin
(for PUTs). Both plugins register their routes via `signalKApiRoutes` to
land in the more permissive namespace — see `signalk-raymarine-autopilot/index.js`
and `signalk-minimalvesseldata-plugin/index.js`.

The watch requests the **readwrite** permission level. Admin is not
needed or wanted.

## Relevant Documentation

Use websearch if necessary for research to get details on documentation for the various SDKs, Services and APIs used in this project. Especially the forum might be useful to find special workarounds or best practises. But as a key reference for best practises always refer to the offical garmin documentation

### Garmin



## SignalK

- SignalK (including API): https://signalk.org/specification/1.8.2/doc/
- SignalK node server github repo: https://github.com/SignalK/signalk-server
- Minimal Vesseldata plugin: https://github.com/beat843796/signalk-minimalvesseldata-plugin
- Autopilot pligin: https://github.com/beat843796/signalk-raymarine-autopilot

## Toolchain

| Piece | Location |
| --- | --- |
| Connect IQ SDK 9.1.0 | `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b` |
| Developer key | `~/Documents/Development/keys/garmin_developer/developer_key` |
| VS Code extension | `garmin.monkey-c` (official) |
| JRE | 11+ required by the Monkey C extension |
| Node.js (for sibling plugins) | 18+ via nvm or Homebrew |

VS Code has `monkeyC.developerKeyPath` pointing at the key above in user
settings. `.vscode/launch.json` is auto-generated on first run and
gitignored. `.vscode/tasks.json` IS committed — see Build workflow below.

## API level


`minApiLevel = 5.2.0`. Legacy devices (fenix5/6/7, fr645/935) were dropped
in the 2026 modernization. The `resources-icon-{40,60,65}/drawables/`
folders hold per-size launcher icons; `monkey.jungle` maps each device to
the right folder via `resourcePath` overrides.

`type = "watch-app"` (not "widget"). System-5+ Garmin devices removed the
legacy widget carousel. The app appears in the glance carousel via
`SignalKGlanceView`.



### build run test rom the CLI

```sh
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b"
KEY="$HOME/Documents/Development/keys/garmin_developer/developer_key"

# Production build
"$SDK/bin/monkeyc" -o bin/signalk-connect.prg -f monkey.jungle -y "$KEY" -d epix2pro42mm

# Run in sim (start sim first: "$SDK/bin/connectiq" &)
"$SDK/bin/monkeydo" bin/signalk-connect.prg epix2pro42mm

# Unit tests
"$SDK/bin/monkeyc" -o bin/signalk-connect-test.prg -f monkey.jungle -y "$KEY" -d epix2pro42mm --unit-test
"$SDK/bin/monkeydo" bin/signalk-connect-test.prg epix2pro42mm -t
```

## Source layout

Files are organised into `source/{model,views,util}/` (the app entry and
`Constants.mc` stay at `source/` root). `monkey.jungle` uses the default
`source/**.mc` glob so the structure recurses automatically.

| File | Purpose |
| --- | --- |
| `source/VesselConnectApp.mc` | App entry. Lazily constructs the global `vessel` in `getInitialView` (NOT `initialize` — that runs in the glance slice too and crashes on `new VesselModel()`). Reads `ConnectionType` from storage and attaches the matching transport via `TransportFactory`. `getGlanceView` is `(:glance)`-annotated and returns the glance tile. |
| `source/Constants.mc` | Shared constants for both main-app and glance slices: `StorageKeys`, `ConnectionType` (user pick: NONE/REST/BLE), `ApStates`, `AUTH_*` (internal REST auth FSM), `AP_STATE_*`, `CONN_*` (unified connectivity enum), `BLE_*` (internal BLE link state), `BleCharUuids`, `BleCmdAction`. |
| `source/model/VesselModel.mc` | Transport-agnostic vessel face. Data fields, formatters, glance writer, command surface (`changeHeading`, `setAutopilotState`) that delegates to `connect`. Holds the active `VesselConnect` (REST / BLE / Null). `attachTransport()` swaps it cleanly. |
| `source/model/VesselConnect.mc` | Abstract base for transports. All methods have safe no-op defaults so views can call any of them without branching on transport flavour. |
| `source/model/RESTVesselConnect.mc` | REST-over-HTTP impl. Owns baseURL/token/clientId/href, all timers, all HTTP. Auth FSM, data poll, autopilot PUT, access-request POST + polling, `/signalk` discovery probe. `lastNetCode`/`probeOk` live here (REST-only). Maps internal state to `CONN_*` via `Utilities.deriveConnectivity`. |
| `source/model/BLEVesselConnect.mc` | Thin VesselConnect facade wrapping a BleService. Maps internal `BLE_*` to unified `CONN_*`. Routes start/stop/connect/disconnect/streaming/commands to the underlying service. Receives link-state callbacks via `onLinkConnected/onLinkDisconnected`. |
| `source/model/BleService.mc` | Owns the BLE peripheral connection lifecycle and the per-view read loop. Constructed by `BLEVesselConnect`; never touched by views directly. Notifies its facade on link transitions. |
| `source/model/NullVesselConnect.mc` | No-op transport assigned to `vessel.connect` when `ConnectionType == NONE`. Returns `CONN_NONE` so StatusView can detect "user hasn't picked yet" and auto-push the picker. |
| `source/model/TransportFactory.mc` | Single point of construction. `getStoredType()` / `setStoredType(t)` wraps the `signalk-connection-type` storage key; `build(type, vessel)` returns the matching VesselConnect impl. |
| `source/model/NetworkErrorPresenter.mc` | Holds the legacy `ErrorView` push/pop API. **Currently unused** — the StatusView subtitle carries error state. Kept on disk in case we re-introduce a full-screen error overlay. |
| `source/views/VesselDataView.mc` | Main 3-row data dashboard (SOG / AWA+AWS / DBT). Shows `—` placeholders when `vessel.hasDataConnection()` is false. Select pushes AutopilotView. Calls `vessel.beginDataStreaming(NAV)` on show (no-op for REST). |
| `source/views/TempView.mc` | Water-temperature page. Same `—` treatment. Calls `vessel.beginDataStreaming(ENV)` on show. |
| `source/views/StatusView.mc` | "Config" page in the loop. Renders `vessel.connect.getDisplayTitle()` + `getStatusLabel()` — single transport, no split layout. Auto-pushes the connection-type picker on first launch (`ConnectionType == NONE`). Select opens the Config menu (state-driven items: Request Access for REST when NOT_AUTH, Connect/Cancel/Disconnect for BLE, Set Connection Type, Debug Probe for REST). |
| `source/views/ConnectionTypePicker.mc` | Menu2 + delegate for picking REST or BLE. Pushed on first launch (back exits the app per UX requirement) and from the Config menu's "Set Connection Type" item (back pops normally). On selection, calls `TransportFactory.setStoredType` + `vessel.attachTransport`. |
| `source/views/AuthConfigView.mc` | Hosts `RequestAccessView` (despite the filename). Pushed on top of the loop when the user opts to start the REST device-access-request. Spinner during POST + polling → auto-pop on approval, toast + pop on denial. |
| `source/views/BleConnectView.mc` | Spinner view shown during BLE pairing. Calls `vessel.connect.startConnect/cancelConnect`. Only ever pushed when the active transport is BLE. |
| `source/views/NoRestConnectionView.mc` | Full-screen error pushed by AutopilotView when an autopilot command is attempted but the active transport is not in CONN_CONNECTED. Wording is transport-agnostic ("to vessel"). |
| `source/views/AutopilotView.mc` | Autopilot control UI. UP/DOWN/CLOCK/MENU adjust target heading (±1°/±10°); select opens the mode menu. Gates command keys on `vessel.canSendCommands()` (== CONN_CONNECTED). Pushes `NoRestConnectionView` when blocked. |
| `source/views/VesselViewLoopFactory.mc` | The 3-page ViewLoop: VesselData / Temp / Status. `VesselViewLoop.build(initialPage)` is the canonical constructor; used by app launch and by `RESTVesselConnect.redirectToConfigPage`/`redirectToDataPage` for ViewLoop redirects. |
| `source/views/ErrorView.mc` | Full-screen error overlay class. **Not currently pushed** but kept for potential future use. |
| `source/views/SignalKGlanceView.mc` | Glance-carousel tile. `(:glance)` annotated; reads last-known state from `Application.Storage` only. Branches on `signalk-connection-type`: NONE → "NOT CONFIGURED"; REST → "SignalK Server" + URL; BLE → "BLE" + device name. |
| `source/util/Utilities.mc` | Pure helpers: unit conversions, display formatters, `normalizeBaseUrl`, `deriveInitialAuthState`, `deriveConnectivity`, `generateUuidV4`, wind-arrow drawer, error-code table. Side-effect-free; unit-tested. |
| `source/util/UtilitiesTest.mc` | Run-No-Evil tests for `Utilities` (incl. the full `deriveConnectivity` state matrix). Stripped from release builds by `(:test)` annotation. |
| `source/util/Json.mc` | Recursive-descent JSON parser. Top-level must be an object; supports nested objects, strings (basic escapes), numbers (int/decimal/scientific/negative), `true`/`false`/`null`. No arrays, no `\uXXXX`. Throws `Json.ParseError` on malformed input. |
| `source/util/JsonTest.mc` | 30 Run-No-Evil tests for `Json`. |
| `resources/strings/strings.xml` | `AppName`. |
| `resources-icon-{40,60,65}/drawables/` | Per-launcher-slot-size icon variants. |
| `resources/properties.xml` | Settings UI — `baseurl_prop` only. |
| `manifest.xml` | `minApiLevel="5.2.0"`, `type="watch-app"`. |
| `monkey.jungle` | Build config. |
| `.vscode/tasks.json` | Committed. The build/deploy/test tasks above. |

## Architecture — one transport at a time

One global `vessel` (a `VesselModel`) declared in `VesselConnectApp.mc`.
Every view reads from it. `VesselModel` is transport-agnostic — the
active transport lives on `vessel.connect` and is exactly ONE of
`RESTVesselConnect`, `BLEVesselConnect`, or `NullVesselConnect`. The
user picks REST or BLE on first launch (and can switch later via the
Config menu's "Set Connection Type"). Both data flow and autopilot
commands ride that single picked transport — there's no fallback or
parallel operation.

`TransportFactory` is the single point of construction. It reads
`signalk-connection-type` from storage (string: `"none"` / `"rest"` /
`"ble"`) and returns the matching VesselConnect; `setStoredType(t)`
persists the user's pick. `VesselModel.attachTransport(newConnect)`
cleanly stops the previous transport and installs the new one. Token
and BLE_AUTOCONNECT survive the swap so users can switch back later
without re-authing or re-pairing.

`VesselConnect` is the abstract base. Every method has a safe no-op
default; subclasses override the ones they care about. This means
views can call `vessel.connect.requestAccess()` or
`vessel.connect.startConnect(cb)` unconditionally — irrelevant calls
silently do nothing on the wrong transport. The Config menu still
filters items by transport so the user never sees inapplicable
actions.

The UI is a single `WatchUi.ViewLoop` with three pages: VesselData,
Temp, Status. On a REST data-poll failure transition (`OK → not OK`),
`RESTVesselConnect.redirectToConfigPage()` constructs a fresh ViewLoop
with `:page => VIEWLOOP_PAGE_STATUS`. The ViewLoop API has no
programmatic `setPage` — recreate-and-switch is the only way to land
on a non-zero page after init.

`StatusView` auto-pushes the `ConnectionTypePicker` Menu2 on first
launch when no transport is picked. Back from the picker in that
context exits the app — the user MUST pick a transport. Subsequent
invocations from the Config menu are normal (back pops to the menu).

`RequestAccessView` is pushed on top of the ViewLoop only when the
user deliberately starts the REST access-request flow. It auto-pops
on approval (no ack screen), toasts + pops on denial.

## Connectivity model — unified status

`vessel.getStatusKind()` returns one of the unified `CONN_*` values
(see `Constants.mc`). Each transport maps its internal state onto the
unified enum:

| `CONN_*` | REST | BLE | Null |
| --- | --- | --- | --- |
| `CONN_NONE` | — | — | always |
| `CONN_NO_URL` | `baseurl_prop` missing | — | — |
| `CONN_NO_HTTPS` | last code -1001 | — | — |
| `CONN_NOT_AUTH` | no token, or 401/403 | — | — |
| `CONN_PENDING` | access request submitted | — | — |
| `CONN_NOT_REACHABLE` | timeout, 5xx, unknown | — | — |
| `CONN_MISSING_PLUGIN` | 404/400 + probe ok | — | — |
| `CONN_DISCONNECTED` | — | not paired | — |
| `CONN_CONNECTING` | — | scanning / pairing | — |
| `CONN_CONNECTED` | token + last poll 200 | GATT link up | — |

REST's mapping is implemented by `Utilities.deriveConnectivity(...)` —
unit-tested in `UtilitiesTest.mc`. BLE's mapping is the trivial 3:3
table inside `BLEVesselConnect.getStatusKind()`.

`vessel.connect.getStatusLabel()` returns the subtitle string for the
StatusView: URL when REST is CONNECTED, device name when BLE is
CONNECTED, or a state name (`"NOT REACHABLE"`, `"Connecting..."`, …)
otherwise. `getDisplayTitle()` returns the per-transport title
(`"SignalK Server"` for REST, `"BLE"` for BLE).

## Auth state machine (internal — REST-specific, lives on `RESTVesselConnect`)

```
NO_URL         ─user sets baseurl_prop─►  NEEDS_REQUEST
NEEDS_REQUEST  ─tap request─►             PENDING (on 202)
PENDING        ─poll APPROVED─►           CONNECTED (data poll auto-starts)
PENDING        ─poll DENIED──►            DENIED  (toast + pop request view)
DENIED         ─tap reset────►            NEEDS_REQUEST (fresh clientId)
```

`authState` is not persisted. On launch, `RESTVesselConnect.configureSignalK`
re-derives it via `Utilities.deriveInitialAuthState(baseURL, token,
accessRequestHref)` (pure function, unit-tested). Views should read
`vessel.getStatusKind()` for user-facing state — `AUTH_*` is internal
to the REST flow (only `RequestAccessView` checks it directly).

### Persisted in `Application.Storage` (keys in `Constants.StorageKeys`)

- `signalk-connection-type` — `"none"` / `"rest"` / `"ble"`. Single
  source of truth for which transport is active. Read by
  `TransportFactory.getStoredType()`.
- `signalk-client-id` — v4 UUID generated once per install; sticks across
  launches and re-requests against the same server. (REST.)
- `signalk-access-href` — polling URL returned by the server on submit.
  (REST.)
- `signalk-token` — `"Bearer <JWT>"` once approved. (REST.)
- `signalk-ble-autoconnect` — sticky boolean: set on first successful
  BLE pair, cleared on explicit Disconnect. While set, the app silently
  rescans for the SignalK service on each launch.
- `signalk-glance` — combined dict `{connectionType, url, bleDeviceName,
  sog, aws, ap}` written every ~5 s while connected; read by the glance
  view. Single key (not multiple) to cut flash writes.

## HTTP request shape — TEXT_PLAIN, not JSON

All requests use `:responseType => HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN`.
CIQ's auto-parse with `HTTP_RESPONSE_CONTENT_TYPE_JSON` swallows the real
HTTP status code on parse failure (replaces with -400), which hides auth
failures behind "missing plugin" because signalk-server returns plain-text
"Unauthorized" bodies for 401. With TEXT_PLAIN we always get the real
status code and parse JSON ourselves via `Json.parse`.

The `/signalk` discovery probe disambiguates 404/400 ambiguity (server up
+ plugin route missing vs. server down). Fired only on the first ambiguous
error per episode; result resets when data resumes flowing.

## Robustness features (worth knowing before touching)

- **Access-request timeout**: 3 s. Longer than that and
  `Communications.cancelAllRequests` kills the POST.
- **Spinner delay**: 250 ms. The spinner only appears if the POST is
  slow enough to warrant feedback. Fast responses never flash. Once
  set, the spinner stays through the entire access flow (POST + polling)
  and only stops at terminal state (CONNECTED / DENIED / hard error).
- **Duplicate-tap dedup**: `accessRequestInFlight` flag blocks repeated
  taps from queueing BLE QUEUE FULL errors.
- **Late-response guard**: if the timeout fires first, a late callback
  arriving afterwards is detected and ignored.
- **Loop-redirect-on-error**: `RESTVesselConnect` tracks `lastDataPollOk`
  and only triggers `redirectToConfigPage` on the OK→fail transition,
  not on every retry tick. Otherwise the user's loop position would be
  trampled at the data-poll cadence.
- **Invalid-timer bug fix**: `invalidateTimer(t)` returns `null` and
  callers reassign — Monkey C passes refs by value, so `timer = null`
  inside the function did nothing before.
- **Transport switch preserves state**: `attachTransport(newConnect)`
  stops the old transport but does NOT delete REST tokens or
  `BLE_AUTOCONNECT`. Switching REST → BLE → REST round-trips without
  re-authing.
- **First-launch picker enforcement**: back from the picker exits the
  app rather than dropping the user onto an empty StatusView. The
  picker is auto-pushed in `StatusView.onShow` whenever
  `ConnectionType == NONE`.

## Code style


- **Comments**: `/* ... */` for multi-line blocks (2+ lines);
  `//` for single-line and inline. Document *why* / *when*, not *what*.
  File-header, class-header, and function-purpose comments expected.
- **Units** on physical-quantity fields are inline comments
  (`// radians`, `// meter/second`).
- **Strict type-check is ON**. Timer targets need `as Void` return.
  `Communications.makeWebRequest` callbacks need
  `(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null) as Void`.
  `BehaviorDelegate.onKey` returns `Lang.Boolean`.

## Monkey C quirks discovered during the 2026 refactor

- `Lang.Exception` reserves `mMessage` as a protected field. Subclasses
  must use a different name (e.g. `mMsg`).
- The strict type checker doesn't recognise `throw` as terminating
  control flow. Use a flag-and-explicit-return pattern in loops, or a
  `return null;` sentinel after a terminal throw.
- `Lang.Dictionary.get(key)` returns `Object?`. Use `instanceof` guards
  (`if (!(v instanceof Lang.Float)) return false;`) to narrow before
  arithmetic.
- `WatchUi.ViewLoop` has no programmatic `setPage` / `jumpTo`. Only
  `changeView(:next | :previous)` and the `:page` initial-index option
  in `initialize`. Recreate-and-switch to land on a specific page.



# TODO / refactoring roadmap

Ordered by value-per-effort. Each item is independently actionable —
pick any, skip the rest.

## High value, low risk

1. **Gate `System.println`** behind `Debug.ENABLED` flag in `Constants.mc`.
   40+ prints currently run in release builds (harmless but wasteful).
   Simpler than the `(:debug)` annotation dance that was tried and
   deferred.

2. **Replace raw AP state strings in `AutopilotView.mc`** (8+ occurrences
   of `"standby"` / `"auto"` / `"wind"` / `"route"`) with
   `ApStates.STANDBY` / `AUTO` / `WIND` / `ROUTE` constants already
   defined in `Constants.mc`. Cosmetic but catches typos.

3. **Hoist hot-path allocations** in
   `RESTVesselConnect.updateVesselDataFromServer`. The headers/options
   dicts are rebuilt every 1 s tick — move them to fields initialised
   once in `initialize()`. Memory-pressure win at zero behaviour change.

4. **Fix `AutopilotView` module-level mutable state** (`changeHeading`,
   `changeHeadingMode` at file scope). These leak between AutopilotView
   lifetimes. Move to `AutopilotDelegate` fields.

5. **`using Toybox.X` → `import Toybox.X`** across all `.mc` files. The
   modern CIQ idiom lets the strict type checker resolve `Number`,
   `Dictionary`, `Boolean` etc. without the `Lang.` prefix. No
   functional change.

## Medium value, medium risk

6. **Older device support**. Adding fenix6/7 or FR255/265 is
   straightforward (they're watch-app-capable) but needs rendering
   validation on smaller/rect screens — the current layouts assume
   ≥240×240 round.

7. **SignalK Autopilot API v2 migration**. The autopilot commands still
   go through the custom `/signalk/v1/api/raymarineautopilotfork/command`
   endpoint. SignalK has a v2 REST API
   (`PUT /signalk/v2/api/vessels/self/autopilots/_default/target/adjust`)
   which would let this app work with any v2-compatible provider plugin,
   not just our fork. Blocked on: the raymarine plugin supporting the
   v2 provider interface — no work has started there.

8. **Delete `NetworkErrorPresenter` + `ErrorView` + `BleScanner` +
   `BLEScanView`**. All four are dead code — the StatusView subtitle
   carries error state, and BLE scanning is now driven by `BleService`.
   Removing them tightens the source tree.

## Low priority / nice-to-have

9. **Battery-friendly polling**. `updateInterval = 1000` ms still hammers
   the server. Options: (a) reduce to 2–3 s; (b) only poll while the
   data view is foregrounded; (c) adaptive cadence based on last-change
   detection. No user demand yet.

10. **Refresh screenshots in `doc/`**. Current `sc1.jpg` / `sc2.jpg` /
    `sc3.jpg` are from the pre-2026 UI. Regenerate after a successful
    sideload on a real fenix 8 / epix Pro to capture the
    ConnectionTypePicker / single-method StatusView / glance.

11. **Server-side cleanup for orphaned pending requests**. If the user
    resets during PENDING, the server-side request stays PENDING until
    an admin denies it. No SignalK-spec DELETE endpoint exists (verified
    against 2.x server source). Would need either a client-side
    re-submission of approved state or a change to signalk-server itself.
