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

- Developer Forum: https://forums.garmin.com/developer/connect-iq/f/discussion
- API Documentation: https://developer.garmin.com/connect-iq/api-docs/
- SDK Doc: https://developer.garmin.com/connect-iq/overview/

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
| `source/VesselConnectApp.mc` | App entry. Lazily constructs the global `vessel` in `getInitialView` (NOT `initialize` — that runs in the glance slice too and crashes on `new VesselModel()`). Always returns the ViewLoop; initial page = data dashboard if connected, status page otherwise. `getGlanceView` is `(:glance)`-annotated and returns the glance tile. |
| `source/Constants.mc` | Shared constants for both main-app and glance slices: `StorageKeys`, `ApStates`, `AUTH_*` (internal auth FSM), `AP_STATE_*`, `CONN_*` (user-facing connectivity enum). |
| `source/model/VesselModel.mc` | Transport-agnostic vessel face. ~310 LOC. Vessel data fields, formatters, glance writer, command surface (`changeHeading`, `setAutopilotState`) that delegates to `connect`, `applyVesselDataDict(dict)` callback, `getConnectivity()` getter. |
| `source/model/VesselConnect.mc` | Abstract base for transports. Holds shared `lastNetCode` / `probeOk` state. Subclasses implement `start/stop/setAutopilotState/changeHeading`. |
| `source/model/RESTVesselConnect.mc` | REST-over-HTTP impl. ~780 LOC. Owns baseURL/token/clientId/href, all timers, all HTTP. Auth state machine, data poll, autopilot PUT, access-request POST + polling, `/signalk` discovery probe. Uses TEXT_PLAIN responseType + `Json.parse` to preserve real status codes. |
| `source/model/BLEVesselConnect.mc` | Stub for a future BLE GATT transport. All methods throw today; documents the seam for whoever wires it up. |
| `source/model/NetworkErrorPresenter.mc` | Holds the legacy `ErrorView` push/pop API. **Currently unused** — the post-2d UX surfaces errors via the StatusView subtitle instead. Kept on disk in case we re-introduce a full-screen error overlay. |
| `source/views/VesselDataView.mc` | Main 3-row data dashboard (SOG / AWA+AWS / DBT). Shows `—` placeholders when `getConnectivity() != CONN_CONNECTED`. Select pushes AutopilotView. |
| `source/views/TempView.mc` | Water-temperature page. Same `—` treatment when not connected. |
| `source/views/StatusView.mc` | "Config" page in the loop. Title "SignalK", subtitle = current CONN_* label (NO URL / NO HTTPS / NOT REACHABLE / NOT AUTHENTICATED / PENDING / PLUGIN MISSING / CONNECTED). Select/menu opens RequestAccessView only when state is NOT_AUTHENTICATED. |
| `source/views/AuthConfigView.mc` | Hosts `RequestAccessView` (despite the filename — kept to minimise churn). Pushed on top of the loop when the user opts to start the device-access-request. Shows a "Tap to request" prompt → spinner during POST + polling → auto-pop on approval, toast + pop on denial. |
| `source/views/AutopilotView.mc` | Autopilot control UI. UP/DOWN/CLOCK/MENU adjust target heading (±1°/±10°); select opens the mode menu. Disabled when not CONNECTED. |
| `source/views/VesselViewLoopFactory.mc` | The 3-page ViewLoop: VesselData / Temp / Status. `VesselViewLoop.build(initialPage)` is the canonical constructor; called by `VesselConnectApp.getInitialView` and by `RESTVesselConnect.redirectToConfigPage` to re-create the loop landing on the status page. Page-index constants `VIEWLOOP_PAGE_DATA / TEMP / STATUS` live in this file. |
| `source/views/ErrorView.mc` | Full-screen error overlay class. **Not currently pushed** by anything (NetworkErrorPresenter is a no-op caller) but the file is preserved for potential future use. |
| `source/views/SignalKGlanceView.mc` | Glance-carousel tile. `(:glance)` annotated; reads last-known state from `Application.Storage` only. Has zero dependency on VesselModel (can't — glance slice is memory-restricted). |
| `source/util/Utilities.mc` | Pure helpers: unit conversions (kn/nm/rad/deg/K→°C), display formatters (`formatSpeedKnots`, `formatDepthMeters`, …), `normalizeBaseUrl`, `deriveInitialAuthState`, `deriveConnectivity`, `generateUuidV4`, wind-arrow drawer, HTTP/BLE error-code table, `drawStatusScreen` helper. All side-effect-free; all unit-tested. |
| `source/util/UtilitiesTest.mc` | Run-No-Evil tests for `Utilities` (incl. the full `deriveConnectivity` state matrix). Stripped from release builds by `(:test)` annotation. |
| `source/util/Json.mc` | Recursive-descent JSON parser. Top-level must be an object; supports nested objects, strings (basic escapes), numbers (int/decimal/scientific/negative), `true`/`false`/`null`. No arrays, no `\uXXXX`. Throws `Json.ParseError` on malformed input. |
| `source/util/JsonTest.mc` | 30 Run-No-Evil tests for `Json`: happy path + escape handling + real signalk payload shapes + 11 malformed-input cases. |
| `resources/strings/strings.xml` | `AppName`. |
| `resources-icon-{40,60,65}/drawables/` | Per-launcher-slot-size icon variants. |
| `resources/properties.xml` | Settings UI — `baseurl_prop` only. |
| `manifest.xml` | `minApiLevel="5.2.0"`, `type="watch-app"`. |
| `monkey.jungle` | Build config. |
| `.vscode/tasks.json` | Committed. The build/deploy/test tasks above. |

## Architecture — model + transport, view-loop-driven UI

One global `vessel` (a `VesselModel`) declared in `VesselConnectApp.mc`.
Every view reads from it. `VesselModel` is transport-agnostic — the
actual networking lives on its `connect` (a `VesselConnect` subclass).
Today that's `RESTVesselConnect`; swap to `BLEVesselConnect` in
`VesselModel.initialize` to switch transports.

The UI is a single `WatchUi.ViewLoop` with three pages: VesselData,
Temp, Status. The Status page is the always-on connectivity dashboard.
On any data-poll failure transition (`OK → not OK`), the transport
calls `redirectToConfigPage()` which constructs a fresh ViewLoop with
`:page => VIEWLOOP_PAGE_STATUS` and `WatchUi.switchToView`s to it. The
ViewLoop API has no programmatic `setPage` — recreate-and-switch is the
only way to land on a non-zero page after init.

`RequestAccessView` is pushed on top of the ViewLoop only when the user
deliberately starts the access-request flow (select on Status when in
`CONN_NOT_AUTH`). It auto-pops on approval (no ack screen), toasts +
pops on denial.

## Connectivity model

`vessel.getConnectivity()` returns the current `CONN_*` state by calling
the pure `Utilities.deriveConnectivity(baseURL, hasToken, hasHref,
lastNetCode, probeOk)`. Precedence (top wins):

1. `CONN_NO_URL` — no `baseurl_prop` configured
2. `CONN_NO_HTTPS` — last request returned -1001 (Garmin's HTTPS-required policy)
3. `CONN_PENDING` — no token but access request submitted
4. `CONN_NOT_AUTH` — no token (and no pending request)
5. `CONN_CONNECTED` — token + (no poll yet OR last poll 200)
6. `CONN_NOT_AUTH` — token + last poll 401/403 (token revoked server-side)
7. `CONN_MISSING_PLUGIN` / `CONN_NOT_REACHABLE` — token + last poll 404/400, disambiguated by `/signalk` discovery probe (probe ok → MISSING_PLUGIN, probe fail → NOT_REACHABLE)
8. `CONN_NOT_REACHABLE` — token + any other failure (-300 timeout, 5xx, unknown)

Every cell of this table is unit-tested in `UtilitiesTest.mc`.

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
`vessel.getConnectivity()` for user-facing state — the AUTH_* enum is
internal to the REST flow.

### Persisted in `Application.Storage` (keys in `Constants.StorageKeys`)

- `signalk-client-id` — v4 UUID generated once per install; sticks across
  launches and re-requests against the same server.
- `signalk-access-href` — polling URL returned by the server on submit
  (persisted so a mid-pending restart can resume without re-submitting).
- `signalk-token` — `"Bearer <JWT>"` once approved.
- `signalk-glance` — combined dict `{sog, aws, ap}` written every ~5 s
  while connected; read by the glance view. Single key (not three) to
  cut flash writes 3×.

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

8. **Decide the fate of `NetworkErrorPresenter` + `ErrorView`**. Both
   are dead code after the 2d UX rework — the StatusView subtitle now
   carries error state. Either delete both or revive them for a
   specific subset of cases (e.g. modal-style toasts beyond the
   `WatchUi.showToast` capabilities).

## Low priority / nice-to-have

9. **Battery-friendly polling**. `updateInterval = 1000` ms still hammers
   the server. Options: (a) reduce to 2–3 s; (b) only poll while the
   data view is foregrounded; (c) adaptive cadence based on last-change
   detection. No user demand yet.

10. **Refresh screenshots in `doc/`**. Current `sc1.jpg` / `sc2.jpg` /
    `sc3.jpg` are from the pre-2026 UI — they show the old
    username/password data view, not the current RequestAccessView /
    glance / StatusView flow. Regenerate after a successful sideload on
    a real fenix 8 / epix Pro.

11. **Server-side cleanup for orphaned pending requests**. If the user
    resets during PENDING, the server-side request stays PENDING until
    an admin denies it. No SignalK-spec DELETE endpoint exists (verified
    against 2.x server source). Would need either a client-side
    re-submission of approved state or a change to signalk-server itself.

12. **Wire up `BLEVesselConnect`**. Stub today. Requires designing the
    BLE GATT service shape on the server side too (signalk-server has
    no BLE bridge in core; would need a sibling plugin). Big project,
    no concrete pull yet.
