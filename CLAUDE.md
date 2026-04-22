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

## Target devices & API level

From `manifest.xml`:

- **Fenix 8:** `fenix843mm`, `fenix847mm`, `fenix8pro47mm`, `fenix8solar47mm`, `fenix8solar51mm` (API 6.0)
- **Epix Pro Gen 2:** `epix2pro42mm`, `epix2pro47mm`, `epix2pro51mm` (API 5.2)
- **Forerunner:** `fr970` (API 6.0), `fr965` (API 5.2)

`minApiLevel = 5.2.0`. Legacy devices (fenix5/6/7, fr645/935) were dropped
in the 2026 modernization. The `resources-icon-{40,60,65}/drawables/`
folders hold per-size launcher icons; `monkey.jungle` maps each device to
the right folder via `resourcePath` overrides.

`type = "watch-app"` (not "widget"). System-5+ Garmin devices removed the
legacy widget carousel. The app appears in the glance carousel via
`SignalKGlanceView`.

## Build, run, test

### VS Code tasks (committed `.vscode/tasks.json`)

Available from `Cmd+Shift+P → Tasks: Run Task`, or bind to hotkeys:

- **`sk: build + run on epix2pro42mm`** — default build task. Kills any
  stale `monkeydo`, auto-launches the sim if not already running (waits on
  port 1966 for readiness), builds, deploys. Bound to `Cmd+R` in the
  suggested keybinding.
- **`sk: reset simulator`** — kills the sim + monkeydo, relaunches sim
  detached via `nohup`, waits for port.
- **`sk: hard reset + build + run`** — composes the two above. `Cmd+Shift+R`.
- **`sk: run unit tests`** — builds `--unit-test` and runs. `Cmd+Shift+T`.

These bypass the Monkey C extension's debug adapter (which is flaky on
re-runs) and shell out directly to `monkeyc` / `monkeydo`.

### Why not `Ctrl+F5` from the extension?
The Monkey C extension's built-in Run-Without-Debugging intermittently
leaves the sim's IPC socket wedged between runs (especially if you exit
the app inside the sim with back). The terminal-based tasks don't have
this problem. Ctrl+F5 still works — use it when you want debugger
attached.

### From the CLI

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

| File | Purpose |
| --- | --- |
| `source/VesselConnectApp.mc` | App entry. Lazily constructs the global `vessel` in `getInitialView` (NOT `initialize` — that runs in the glance slice too and crashes on `new VesselModel()`). `getGlanceView` is `(:glance)`-annotated and returns the glance tile. |
| `source/VesselModel.mc` | SignalK I/O + auth state machine. Hosts the 1 s vessel-data poll, the 3 s pending-request poll, autopilot commands, spinner control, error-view orchestration. ~1100 LOC — candidates for extraction listed in TODO below. |
| `source/AuthConfigView.mc` | **Unified** view for the entire device-access-request lifecycle. Renders per `authState`: NO_URL / NEEDS_REQUEST / PENDING / DENIED / CONNECTED (with green checkmark). Replaces three previous views. |
| `source/VesselDataView.mc` | Main 3-row dashboard (SOG / AWA+AWS / DBT) with wind-angle arrow and port/starboard arcs. Select pushes AutopilotView. |
| `source/AutopilotView.mc` | Autopilot control UI. UP/DOWN/CLOCK/MENU adjust target heading (±1°/±10°); select opens the mode menu. Contains `AutopilotDelegate` (keys) and `AutopilotMenuDelegate` (Menu2). |
| `source/ErrorView.mc` | Full-screen error overlay pushed on top of any view by `VesselModel.showNetworkError`. Auto-pops on successful recovery; back dismisses manually. |
| `source/SignalKGlanceView.mc` | Glance-carousel tile. `(:glance)` annotated; reads last-known state from `Application.Storage` only. Has zero dependency on VesselModel (can't — glance slice is memory-restricted). |
| `source/Utilities.mc` | Pure helpers: unit conversions (kn/nm/rad/deg/K→°C), display formatters (`formatSpeedKnots`, `formatDepthMeters`, …), `normalizeBaseUrl`, `deriveInitialAuthState`, `generateUuidV4`, wind-arrow drawer, HTTP/BLE error-code table, `drawStatusScreen` helper. All side-effect-free; all unit-tested. |
| `source/UtilitiesTest.mc` | 43 Run-No-Evil tests covering every pure helper. Stripped from release builds by `(:test)` annotation. |
| `source/Constants.mc` | Shared constants that need to exist in both main-app and glance slices: `StorageKeys` module, `ApStates` module, `AUTH_*` enum, `AP_STATE_*` enum. |
| `resources/strings/strings.xml` | `AppName`. |
| `resources-icon-{40,60,65}/drawables/` | Per-launcher-slot-size icon variants. Each folder has its own `drawables.xml` + `launcher_icon.png`. |
| `resources/properties.xml` | Settings UI — `baseurl_prop` only (read by `VesselModel.configureSignalK`). |
| `manifest.xml` | App metadata, products, permissions. `minApiLevel="5.2.0"`, `type="watch-app"`. |
| `monkey.jungle` | Build config. Points at the manifest + per-device icon-folder overrides. |
| `.vscode/tasks.json` | Committed. The build/deploy/test tasks listed above. |

## Architecture — single-model, view-per-state

One global model (`vessel`, declared in `VesselConnectApp.mc`), every view
reads from it. State changes happen on the model; `WatchUi.requestUpdate()`
triggers redraws. For big transitions (auth state changes, error display),
the model calls `WatchUi.switchToView` / `pushView` directly — no
observer / callback indirection.

View routing summary:

```
AuthConfigView (NO_URL | NEEDS_REQUEST | PENDING | DENIED | CONNECTED)
     │
     │ user acknowledges CONNECTED
     ▼
VesselDataView ──select──► AutopilotView
     │
     │ 401 on data poll
     ▼
AuthConfigView (NEEDS_REQUEST, after resetAccessRequest)
```

`ErrorView` is pushed on top of *whichever* view is currently visible
when a transient network error occurs. Auto-pops on recovery, or manually
via back key.

## Auth state machine (owned by VesselModel, enum in Constants.mc)

```
NO_URL         ─user sets baseurl_prop─►  NEEDS_REQUEST
NEEDS_REQUEST  ─tap request─►             PENDING (on 202)
PENDING        ─poll APPROVED─►           CONNECTED (awaiting user ack)
CONNECTED      ─user ack (tap)─►          VesselDataView + data polling
PENDING        ─poll DENIED──►            DENIED
DENIED         ─tap reset────►            NEEDS_REQUEST (fresh clientId)
CONNECTED      ─401/-400/403 on data──►   NEEDS_REQUEST (token cleared)
any            ─baseurl_prop cleared──►   NO_URL
```

**Important**: `authState` is not persisted. On launch,
`VesselModel.configureSignalK` re-derives it via
`Utilities.deriveInitialAuthState(baseURL, token, accessRequestHref)`
(pure function, unit-tested).

### Persisted in `Application.Storage` (keys in `Constants.StorageKeys`)

- `signalk-client-id` — v4 UUID generated once per install; sticks across
  launches and re-requests against the same server.
- `signalk-access-href` — polling URL returned by the server on submit
  (persisted so a mid-pending restart can resume without re-submitting).
- `signalk-token` — `"Bearer <JWT>"` once approved.
- `signalk-glance` — combined dict `{sog, aws, ap}` written every ~5 s
  while connected; read by the glance view. Single key (not three) to
  cut flash writes 3×.

## Robustness features (worth knowing before touching)

- **Access-request timeout**: 3 s. Longer than that and
  `Communications.cancelAllRequests` kills the POST and surfaces
  "Server not found".
- **Spinner delay**: 250 ms. The spinner only appears if the request
  is slow enough to warrant feedback. Fast responses never flash the
  loading screen.
- **Duplicate-tap dedup**: `accessRequestInFlight` flag blocks repeated
  taps from queueing BLE QUEUE FULL errors.
- **Late-response guard**: if the timeout fires first, a late callback
  arriving afterwards is detected and ignored.
- **Auth failure recognition**: signalk-server returns 401 with a plain
  text body `"Unauthorized"` which CIQ's JSON parser rejects → CIQ
  surfaces `-400` to the callback instead of the real 401. `onReceive`
  treats `-400`, `401`, and `403` all as "token dead" and bounces to
  NEEDS_REQUEST.
- **Invalid-timer bug fix**: `invalidateTimer(t)` returns `null` and
  callers reassign — Monkey C passes refs by value, so `timer = null`
  inside the function did nothing before.

## Test strategy

All 43 tests are **pure-function** tests via Garmin's Run No Evil
framework (`Toybox.Test`, `(:test)` annotation). Covered:

- Unit conversions (knots, NM, rad/deg, K→°C).
- Display formatters (`formatSpeedKnots`, `formatDepthMeters`,
  `formatTemperatureCelsius`, `formatTripNauticalMiles`), including
  boundary cases (depth sentinel at ≥500 m).
- URL normalisation (null/empty/trailing slash).
- Auth-state derivation (every reachable `(url, token, href)` branch).
- UUID v4 format (length, dash positions, version nibble, variant nibble).
- Error-code → display-string mapping (spot checks).

**What can't be unit-tested under Run No Evil**: anything touching
`Communications.makeWebRequest`, `WatchUi.*`, timers, `Application.Storage`.
No mocks, no stubs. Network code is exercised against a real SignalK
server or the deltasim plugin.

### End-to-end smoke test

1. Reset simulator Storage (Simulator → File → Reset App Settings).
2. Run the app. Expect `AuthConfigView` in **NO_URL** state.
3. Open the simulator's **Settings → Edit Persistent Storage…** (or the
   Garmin Connect mobile app on a real device) and set `baseurl_prop`
   to `http://127.0.0.1:3000`. Expect transition to **NEEDS_REQUEST**.
4. Tap select — server log shows `POST /signalk/v1/access/requests 202`.
   View transitions to **PENDING** (spinner may briefly appear if the
   POST took >250 ms).
5. Open `http://localhost:3000/admin/#/security/access-requests`, click
   **Approve** with **readwrite** permission.
6. Within a few seconds the view transitions to **CONNECTED** with the
   green checkmark. Tap select to enter the data view.
7. Server log shows `GET /signalk/v1/api/minimumvesseldatarest/vesseldata
   200` on a 1 s cadence.
8. Push AutopilotView (select) and change heading — server log shows
   `POST /signalk/v1/api/raymarineautopilotfork/command 200`.

## Code style

- **One class per file**, filename matches class.
- **Views and their delegates** live in the same file (existing convention
  across all view files).
- **Comments**: `/* ... */` for multi-line blocks (2+ lines);
  `//` for single-line and inline. Document *why* / *when*, not *what*.
  File-header, class-header, and function-purpose comments expected.
- **Units** on physical-quantity fields are inline comments
  (`// radians`, `// meter/second`).
- **Strict type-check is ON**. Timer targets need `as Void` return.
  `Communications.makeWebRequest` callbacks need
  `(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null) as Void`.
  `BehaviorDelegate.onKey` returns `Lang.Boolean`.

## Cross-repo changes

The watch app lives in this repo, but two server-side plugins (sibling
dirs under `~/Documents/Development/projects/`) are tightly coupled:

- `signalk-raymarine-autopilot/index.js` — exposes `POST /command` at
  both `/plugins/...` (admin-only, legacy) and `/signalk/v1/api/...`
  (readwrite, used by this app) via `registerWithRouter` +
  `signalKApiRoutes` hooks.
- `signalk-minimalvesseldata-plugin/index.js` — same dual-endpoint
  pattern for GET `/vesseldata`.
- `signalk-autopilot-deltasim/index.js` — dev-only simulator that
  emits fake autopilot state deltas. Accepts commands at
  `/signalk/v1/api/apsimulator/command` for closed-loop local testing.

**Never modify files in sibling repos without explicit user permission**,
even when a watch-app question touches on them. (Saved lesson — the
user reverted an unauthorized POST→PUT change across three files once.)

---

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
   `VesselModel.updateVesselDataFromServer`. The headers/options dicts
   are rebuilt every 1 s tick — move them to `const` fields initialised
   once in `initialize()`. Memory-pressure win at zero behaviour change.

4. **Fix `AutopilotView` module-level mutable state** (`changeHeading`,
   `changeHeadingMode` at file scope). These leak between AutopilotView
   lifetimes. Move to `AutopilotDelegate` fields.

5. **`using Toybox.X` → `import Toybox.X`** across all `.mc` files. The
   modern CIQ idiom lets the strict type checker resolve `Number`,
   `Dictionary`, `Boolean` etc. without the `Lang.` prefix. No
   functional change.

## Medium value, medium risk

6. **Split `VesselModel.mc`** (currently ~1100 LOC). Candidate
   extractions in decreasing size:

   - `AccessRequestController` — auth state machine, request/poll
     lifecycle, timers. ~200 LOC.
   - `VesselDataPolling` — data-poll loop, retry timer, glance snapshot
     writer, 12 vessel-data fields, onReceive parsing. ~150 LOC.
   - `AutopilotCommander` — `setAutopilotState`, `changeHeading`,
     `sendAutopilotCommand`, `onAutopilotReceive`, `isAutopilotRequestPending`.
     ~80 LOC.
   - `SpinnerController` — `spinnerDelayTimer`, `spinnerTimer`,
     `spinnerVisible`, `onSpinnerTick`. ~40 LOC.
   - `NetworkErrorHandler` — `showNetworkError`, `dismissErrorView`,
     `errorViewVisible`. ~50 LOC.

   User declined this in the April 2026 review pass (too invasive);
   revisit only if a future change hits the "can't find anything in
   VesselModel" wall. Post-split target: ~400 LOC shell.

7. **Older device support**. Adding fenix6/7 or FR255/265 is
   straightforward (they're watch-app-capable) but needs rendering
   validation on smaller/rect screens — the current layouts assume
   ≥240×240 round.

8. **SignalK Autopilot API v2 migration**. The autopilot commands still
   go through the custom `/signalk/v1/api/raymarineautopilotfork/command`
   endpoint. SignalK has a v2 REST API
   (`PUT /signalk/v2/api/vessels/self/autopilots/_default/target/adjust`)
   which would let this app work with any v2-compatible provider plugin,
   not just our fork. Blocked on: the raymarine plugin supporting the
   v2 provider interface — no work has started there.

## Low priority / nice-to-have

9. **Battery-friendly polling**. `updateInterval = 1000` ms still hammers
   the server. Options: (a) reduce to 2–3 s; (b) only poll while the
   data view is foregrounded; (c) adaptive cadence based on last-change
   detection. No user demand yet.

10. **View-routing listener pattern**. VesselModel currently instantiates
    view classes directly (`new AuthConfigView()` / `new ErrorView()`
    etc.). A listener-based refactor would let VesselModel emit state
    changes and let the app layer route. Cleaner architecture, more
    code, no runtime benefit. Skip unless doing a broader MVC
    rearchitecture.

11. **Refresh screenshots in `doc/`**. Current `sc1.jpg` / `sc2.jpg` /
    `sc3.jpg` are from the pre-2026 UI — they show the old
    username/password data view, not the current AuthConfigView / glance
    / CONNECTED flow. Regenerate after a successful sideload on a real
    fenix 8 / epix Pro.

12. **Server-side cleanup for orphaned pending requests**. If the user
    resets during PENDING, the server-side request stays PENDING until
    an admin denies it. No SignalK-spec DELETE endpoint exists (verified
    against 2.x server source). Would need either a client-side
    re-submission of approved state or a change to signalk-server itself.
