# CLAUDE.md

Guidance for future Claude Code sessions working on this repository.

## What this project is

A Connect IQ **watch-app** for Garmin smartwatches that displays SignalK
marine data and controls a Raymarine-compatible autopilot. Talks HTTP to a
SignalK node server and relies on two server-side plugins:

- `signalk-raymarine-autopilot` — autopilot commands
- `signalk-minimalvesseldata-plugin` — the vessel-data REST endpoint

**Authentication:** the app uses SignalK's *device access request* flow. No
credentials on the watch. On first launch the app POSTs a one-time request
to `/signalk/v1/access/requests`; an admin approves it via the SignalK admin
UI; the resulting JWT is stored and used as a Bearer token for subsequent
data/autopilot calls.

## Toolchain

| Piece | Location |
| --- | --- |
| Connect IQ SDK 9.1.0 | `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b` |
| Developer key | `~/Documents/Development/keys/garmin_developer/developer_key` |
| VS Code extension | `garmin.monkey-c` (official) |
| JRE | 11+ required by the Monkey C extension |

VS Code has `monkeyC.developerKeyPath` pointing at the key above in user
settings. Nothing is wired project-locally; the extension generates
`.vscode/launch.json` on the first `Ctrl+F5` run.

## Target devices & API level

From `manifest.xml`:

- **Fenix 8:** `fenix843mm`, `fenix847mm`, `fenix8pro47mm`, `fenix8solar47mm`, `fenix8solar51mm` (API 6.0)
- **Epix Pro Gen 2:** `epix2pro42mm`, `epix2pro47mm`, `epix2pro51mm` (API 5.2)
- **Forerunner:** `fr970` (API 6.0), `fr965` (API 5.2)

`minApiLevel = 5.2.0`. Legacy devices (fenix5/6/7, fr645/935) were dropped
in the 2026 modernization — they're watch-app-compatible in principle but
would need rendering tweaks for older screen sizes; adding them back is a
separate pass if ever needed.

`type = "watch-app"` (not "widget"): System-5+ Garmin devices removed the
legacy widget carousel. The app appears in the glance carousel via
`SignalKGlanceView` (see source map).

## Build, run, test

### From VS Code
- Open any `.mc` file → **Run → Run Without Debugging** (`Ctrl+F5`) → pick a device.
- **Monkey C: Build for Device** (palette) produces a sideload PRG.
- Test Explorer (flask icon) runs Run No Evil tests in `source/UtilitiesTest.mc`.

### From the CLI

```sh
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b"
KEY="$HOME/Documents/Development/keys/garmin_developer/developer_key"
```

Production build:
```sh
"$SDK/bin/monkeyc" -o bin/signalk-connect.prg -f monkey.jungle -y "$KEY" -d fenix847mm
```

Simulator run (start `"$SDK/bin/connectiq" &` first):
```sh
"$SDK/bin/monkeydo" bin/signalk-connect.prg fenix847mm
```

Unit tests:
```sh
"$SDK/bin/monkeyc" -o bin/signalk-connect.prg -f monkey.jungle -y "$KEY" -d fenix847mm --unit-test
"$SDK/bin/monkeydo" bin/signalk-connect.prg fenix847mm -t
```

## Source layout

| File | Purpose |
| --- | --- |
| `source/VesselConnectApp.mc` | App entry. Creates the global `vessel`. `getInitialView` branches on auth state. `getGlanceView` returns the glance tile. |
| `source/VesselModel.mc` | All SignalK I/O: device access request, JWT storage, the 100 ms vessel-data poll, autopilot commands. Owns the `authState` state machine. |
| `source/RequestAccessView.mc` | Initial "tap to request access" screen shown when no token is stored. |
| `source/PendingView.mc` | "Waiting for approval" screen shown while polling the access-request href. Menu key opens a Menu2 with a Reset action. |
| `source/DeniedView.mc` | Terminal-denied screen with a "tap to try again" button (generates a fresh clientId). |
| `source/VesselDataView.mc` | Main 3-row display screen + `VesselDataViewDelegate`. Self-redirects to `RequestAccessView` if `authState` flips back to NEEDS_REQUEST (e.g. 401 on a data call). |
| `source/AutopilotView.mc` | Autopilot control UI. UP/DOWN/CLOCK/MENU adjust target heading; select opens the mode menu. Contains `AutopilotDelegate` (keys) and `AutopilotMenuDelegate` (Menu2). |
| `source/SignalKGlanceView.mc` | Glance-carousel tile. `(:glance)` annotated; reads last-known state from `Application.Storage` — does NOT depend on VesselModel. |
| `source/Utilities.mc` | Pure conversions (kn, nm, rad/deg, K/°C), wind-arrow drawer, HTTP/BLE error-code → display-string table. |
| `source/UtilitiesTest.mc` | Run No Evil characterization tests. Stripped from release builds by `(:test)` annotation. |
| `resources/strings/strings.xml` | `AppName`. |
| `resources/drawables/` | Launcher icon + `drawables.xml`. |
| `resources/properties.xml` | Settings UI — currently only `baseurl_prop`. |
| `manifest.xml` | App metadata, products, permissions. `minApiLevel="5.2.0"`, `type="watch-app"`. |
| `monkey.jungle` | Build config — currently just points at the manifest. |

## Auth state machine (VesselModel.mc)

```
NEEDS_REQUEST  ─tap request─►  PENDING
PENDING        ─poll APPROVED─► CONNECTED
PENDING        ─poll DENIED──►  DENIED
CONNECTED      ─401 on data──►  NEEDS_REQUEST (token cleared)
DENIED         ─tap reset────►  NEEDS_REQUEST (fresh clientId)
```

Persisted via `Application.Storage`:
- `signalk-client-id` — v4 UUID generated once per install
- `signalk-access-href` — polling URL returned by the server on submit
- `signalk-token` — `"Bearer <JWT>"` once approved
- `signalk-glance-{sog,aws,apstate}` — last-known values for the glance tile (written every ~5 s while connected)

## Test strategy

Only `Utilities.mc` is unit-tested, via Garmin's **Run No Evil** framework
(`Toybox.Test`, `(:test)` annotation). Characterization tests pin the
current behaviour of the pure functions and the error-code table.

Networking (`VesselModel`) and the views are exercised by running the app
against a real SignalK server or a local stub. The happy path looks like:

1. Reset simulator Storage (Simulator → File → Reset App Settings).
2. Run the app. Expect `RequestAccessView`.
3. Tap select — server log shows `POST /signalk/v1/access/requests 202`.
4. Open `http://localhost:3000/admin/#/security/access-requests` in a
   browser, click **Approve** with the `admin`-role user.
5. Within a few seconds the view switches to `VesselDataView` with live
   data. The server log shows `GET /plugins/minimumvesseldatarest/vesseldata
   200` on a 100 ms cadence.

## Known issues / deferred

- **Base URL is hardcoded** in `VesselModel.configureSignalK()` —
  `resources/properties.xml` defines `baseurl_prop` but the model doesn't
  read it yet. One-line fix; see the TODO in that function.
- **`System.println` is not gated.** A `(:debug)` + `(:release)` two-function
  pattern was tried but the Connect IQ jungle file doesn't accept
  `debug.`/`release.` qualifiers in SDK 9.1.0 the way the docs suggested.
  Deferred — the prints are harmless in release builds (simulator console
  only, no UI impact). Re-investigate with `$(base.excludeAnnotations)` syntax.
- **Only the newest device family is targeted.** Adding fenix6/7 or
  FR255/265 is straightforward (they're watch-app-capable) but would need
  rendering validation on smaller/round screens.
- **Hard-loop polling** — `updateInterval = 100` ms in `VesselModel`
  hammers the server. Fine for a LAN node, not battery-friendly.
- **No SignalK Autopilot API v2.** The autopilot commands still go through
  the custom `/plugins/raymarineautopilotfork/command` endpoint. SignalK
  has a v2 REST API for autopilot control but it requires a v2-compatible
  provider plugin on the server; when available, migrate to
  `PUT /signalk/v2/api/vessels/self/autopilots/_default/target/adjust`.

## Code style

- One class per file; filename matches class.
- Views and their delegates live in the same file (existing convention).
- File-header, class-header, and function-purpose comments are expected —
  see any existing `.mc` file for the style. Document *why* / *when*, not
  *what*.
- Units on physical-quantity fields are inline comments (`// radians`,
  `// meter/second`) so readers don't have to hunt.
- Strict type-check is ON. Timer targets need `as Void` return annotations;
  `Communications.makeWebRequest` callbacks need
  `as Void` + `(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null)`;
  `BehaviorDelegate.onKey` returns `Lang.Boolean`.
