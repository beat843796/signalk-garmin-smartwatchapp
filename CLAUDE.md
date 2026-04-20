# CLAUDE.md

Guidance for future Claude Code sessions working on this repository.

## What this project is

A Connect IQ **widget** for Garmin smartwatches that displays **SignalK** marine
data and controls a Raymarine-compatible autopilot. It talks HTTP to a SignalK
node server and relies on two server-side plugins:

- `signalk-raymarine-autopilot` — autopilot commands
- `signalk-minimalvesseldata-plugin` — the vessel-data REST endpoint

Original SDK: **3.1.0** (~2018), originally built with the Connect IQ Eclipse
plugin. Migrated in 2026 to build on **Connect IQ SDK 9.1.0** from VS Code.
No source code was modified during the migration; see "Known issues" below.

## Toolchain

| Piece | Location |
| --- | --- |
| Connect IQ SDK 9.1.0 | `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b` |
| Developer key | `~/Documents/Development/keys/garmin_developer/developer_key` |
| VS Code extension | `garmin.monkey-c` (official) |
| JRE | 11+ required by the Monkey C extension |

VS Code has `monkeyC.developerKeyPath` pointing at the key above in user
settings. Nothing else is wired project-locally; the extension generates
`.vscode/launch.json` on the first `Cmd+F5` run.

## Build, run, test

### From VS Code
- Command Palette → **Monkey C: Verify Installation** (once, sanity check).
- Open any `.mc` file → **Run → Run Without Debugging** (`Cmd+F5`) → pick a device.
- Command Palette → **Monkey C: Build Current Project** to produce a PRG without running.
- Command Palette → **Monkey C: Build for Device** to export a sideload PRG.
- Test Explorer (left sidebar, flask icon) runs the Run No Evil unit tests.

### From the CLI
The SDK ships its own `monkeyc` / `monkeydo` / `connectiq`. Keep one shell open with:

```sh
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b"
KEY="$HOME/Documents/Development/keys/garmin_developer/developer_key"
```

Production build (for running / sideload):
```sh
"$SDK/bin/monkeyc" -o bin/siriconnect.prg -f monkey.jungle -y "$KEY" -d fenix5
```

Run in the simulator (start `"$SDK/bin/connectiq" &` first if not already running):
```sh
"$SDK/bin/monkeydo" bin/siriconnect.prg fenix5
```

Unit tests:
```sh
"$SDK/bin/monkeyc" -o bin/siriconnect.prg -f monkey.jungle -y "$KEY" -d fenix5 --unit-test
"$SDK/bin/monkeydo" bin/siriconnect.prg fenix5 -t
```

Supported device ids (from `manifest.xml`): `fenix5`, `fenix5plus`, `fenix5s`,
`fenix5splus`, `fenix5x`, `fenix5xplus`, `fenixchronos`, `fr645`, `fr645m`,
`fr935`. All pre-API-4.0.0 devices.

## Source layout

| File | Purpose |
| --- | --- |
| `source/VesselConnectApp.mc` | App entry point, `AppBase` lifecycle, creates the global `vessel` model, returns the initial view. |
| `source/VesselModel.mc` | HTTP polling against SignalK (login, vessel data every 100 ms, autopilot command). Persists the JWT token via `Application.Storage`. |
| `source/VesselDataView.mc` | Main 3-row display screen + its `BehaviorDelegate` (enter → opens AutopilotView). |
| `source/AutopilotView.mc` | Autopilot control UI. Handles UP/DOWN/CLOCK/MENU/ESC keys to adjust target heading, renders rudder angle. Also contains `AutopilotMenuDelegate` (Menu2). |
| `source/Utilities.mc` | Module with pure conversion functions (kn, nm, rad/deg, K/°C), an HTTP/BLE error-code → display-string table, and a wind-arrow drawer. |
| `source/UtilitiesTest.mc` | Run No Evil characterization tests for `Utilities` (see "Test strategy"). Stripped from release builds by the `(:test)` annotation. |
| `resources/strings/strings.xml` | App name. |
| `resources/drawables/` | Launcher icon + `drawables.xml`. |
| `resources/properties.xml` | Defines the user-editable settings (SignalK URL, user, password) but **not currently wired into the code** — see "Known issues". |
| `resources/layouts/layout.xml` | **Unused** test layouts. |
| `manifest.xml` | App metadata, product list, permissions. Uses legacy `minSdkVersion="3.1.0"` attribute (see "Migration gotcha"). |
| `monkey.jungle` | Build config. Sets `project.typecheck = 0` to keep the pre-existing type-signature mismatches from blocking the build (see "Migration gotcha"). |

## Test strategy

Only `Utilities.mc` is unit-tested, via Garmin's **Run No Evil** framework
(`Toybox.Test`, `(:test)` annotation). Tests live in `source/UtilitiesTest.mc`
and are characterization tests — they pin the *current* behaviour of the pure
functions and the error-code table so later refactors can't silently change
user-visible strings or conversion accuracy.

Networking (`VesselModel`) and the views are **not** unit-tested — they'd need
mocks for `Communications`, `Timer`, `Dc`, etc. Exercise them by running the app
in the simulator, ideally against a real SignalK server or a local stub.

Tests are stripped from release builds automatically by the `(:test)`
annotation.

## Migration gotcha — why `monkey.jungle` sets `project.typecheck = 0`

SDK 9.1.0's **gradual** type checker (the default when the project uses the
modern `minApiLevel` attribute) hard-errors on:

- `AutopilotDelegate.onKey()` overrides returning `Boolean` where the (modern)
  signature expects `Void`.
- `Communications.makeWebRequest(..., method(:cb))` where the callback's
  inferred type is `Method(responseCode as Any, data as Any) as Any` and the
  expected type is
  `Method(responseCode as Number, data as Null or Dictionary or String or PersistedContent.Iterator) as Void`.
- `Timer.Timer.start(method(:cb), ...)` — same flavour of `Any`-vs-`Void` mismatch.

Keeping the older `minSdkVersion="3.1.0"` attribute in `manifest.xml` is what
makes SDK 9.1.0 tolerate these at "lenient" check level, but even then the
unit-test build path re-enables strict checks. Adding
`project.typecheck = 0` to `monkey.jungle` is the global escape hatch that
keeps both production and `--unit-test` builds green without touching source.

If you ever tighten the type checker back on, you'll need to fix the five
`VesselModel.mc` callbacks (give them proper typed signatures and `as Void`
return type) and the three `AutopilotView.mc` `onKey` overrides.

## Known issues — deferred, do not rediscover

These all pre-date the migration and were intentionally left untouched:

- **Hardcoded credentials** — `source/VesselModel.mc:70-72` hardcodes
  `baseURL`, `username`, `password`; the real `Application.Properties.getValue`
  calls are commented out even though `resources/properties.xml` already
  defines the settings UI with the right IDs. One-line fix each.
- **Typo** — `Utilities.degreestToRadians` (extra `t`). One caller in
  `AutopilotView.mc` line ~54. Not a blocker; the test file intentionally
  calls it by its typo'd name.
- **Debug logging in release builds** — 9 `System.println` calls across
  `VesselConnectApp.mc`, `VesselModel.mc`, `VesselDataView.mc`. Would be
  cleaner behind a `(:debug)` annotation + `base.excludeAnnotations = debug`
  in the jungle.
- **`resources/layouts/layout.xml`** — defined but never referenced. Compiler
  emits validation warnings on it.
- **Device coverage** — only pre-API-4.0.0 devices. Adding modern devices
  (fenix6+, epix, fr255+, Venu, …) requires implementing
  `AppBase.getGlanceView()` returning a `WatchUi.GlanceView` — from API 4.0.0
  onward, widgets without a glance don't appear in the glance list.
- **Hard-loop polling** — `updateInterval = 100` ms in `VesselModel.mc`
  hammers the server. Probably fine for a LAN SignalK node but not battery
  friendly.

## Not in scope (do not do without asking)

- Converting `type="widget"` → `type="watch-app"` + glance view.
- Adding devices to the product list.
- Any refactor of `VesselModel`, `VesselDataView`, or `AutopilotView`.
- Turning the type checker back on.
- Creating `.vscode/launch.json` / `tasks.json` — the extension generates
  `launch.json` on first run, and a project-pinned copy tends to go stale.
