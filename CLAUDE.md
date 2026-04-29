# CLAUDE.md

Guidance for future Claude Code sessions working on this repository.

## What this project is

A Connect IQ **watch-app** for Garmin smartwatches that displays SignalK
marine data and controls a Raymarine-compatible autopilot. Talks HTTP to a
SignalK node server on the user's boat LAN (typically a Raspberry Pi) or connects via BLE, and
relies on two server-side plugins:

- `signalk-raymarine-autopilot` — autopilot commands (sibling repo)
- `signalk-minimalvesseldata-plugin` — the vessel-data REST endpoint (sibling repo) and BLE provider
- `signalk-autopilot-deltasim` — optional: emits fake autopilot deltas for local dev (sibling repo)

the plugins are installed on the rpi for testing in the ~./signalk folder using `npm install <githubrepo>`

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

- ConnectIQ SKD: https://developer.garmin.com/connect-iq/overview/
- garmin developer forum: https://forums.garmin.com/developer/connect-iq/f/discussion


## SignalK

- SignalK (including API): https://signalk.org/specification/1.8.2/doc/
- SignalK node server github repo: https://github.com/SignalK/signalk-server
- Minimal Vesseldata plugin: https://github.com/beat843796/signalk-minimalvesseldata-plugin
- Autopilot pligin: https://github.com/beat843796/signalk-raymarine-autopilot

## Code Style

- When making mulitline comments use `/* */` instead of `//`

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

### DEV/TEST Setup

- SignalK Server with all plugins installed running on my rpi in local network reachable via `https://signalk.rpi.cb84.io`
- ssh into it using `admin@rpi` as auth is done via pubkey that exists on dev machine. always ask if you want to ssh into it
- signalk folder on rpi i `~/.signalk`
- signalk managed via systemctl on rpi
- on dev machine nrf52 dongle that fully emulates the devices BLE stack is connected. The com port needs to be set correctly wich should be `/dev/cu.usbmodem0010503767301`

## API level


`minApiLevel = 5.2.0`. Legacy devices (fenix5/6/7, fr645/935) were dropped
in the 2026 modernization. The `resources-icon-{40,60,65}/drawables/`
folders hold per-size launcher icons; `monkey.jungle` maps each device to
the right folder via `resourcePath` overrides.

`type = "watch-app"` (not "widget"). System-5+ Garmin devices removed the
legacy widget carousel. The app appears in the glance carousel via
`SignalKGlanceView`.

## General Rules

- Do not update any md files yourself unless i ask for it explicitly. Also do not update the TODO.md