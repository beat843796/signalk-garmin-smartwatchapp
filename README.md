## signalk garmin smartwatch app

Connect IQ app that displays boat data and controls a Raymarine-compatible
autopilot over HTTP, using the open marine data standard
[SignalK](http://signalk.org). First launch asks your SignalK server for
access; an admin approves the watch once and the per-device token is stored
for future launches — no username or password on the watch.

### Required SignalK plugins

Install these on your [SignalK Node server](https://github.com/SignalK/signalk-server):

- [Autopilot plugin](https://github.com/beat843796/signalk-raymarine-autopilot) — heading / mode control.
- [Minimal vessel data plugin](https://github.com/beat843796/signalk-minimalvesseldata-plugin) — the aggregated `vesseldata` endpoint the watch polls.

The user the watch registers as needs `admin` role (the minimal-vessel-data
plugin endpoint is admin-only).

### Supported devices

| Family | Devices |
| --- | --- |
| Fenix 8 | `fenix843mm`, `fenix847mm`, `fenix8pro47mm`, `fenix8solar47mm`, `fenix8solar51mm` |
| Epix Pro Gen 2 | `epix2pro42mm`, `epix2pro47mm`, `epix2pro51mm` |
| Forerunner | `fr970`, `fr965` |

Minimum API level: **5.2.0**.

### Screenshots

> Screenshots below are from the legacy UI and will be refreshed after a
> release on the new devices.

![Image 1](https://github.com/beat843796/signalk-garmin-smartwatchapp/raw/master/doc/sc1.jpg)
![Image 2](https://github.com/beat843796/signalk-garmin-smartwatchapp/raw/master/doc/sc2.jpg)
![Image 3](https://github.com/beat843796/signalk-garmin-smartwatchapp/raw/master/doc/sc3.jpg)

### First run

1. Install the app on the watch and launch it.
2. The watch shows **Request access?** — tap the select key.
3. Open `http://<your-signalk-host>:3000/admin/#/security/access-requests`
   in a browser, click **Approve** on the row for your watch.
4. Within a few seconds the watch switches to the live data view and starts
   polling. The token is stored on the watch; future launches skip straight
   to the data view.

If the admin clicks **Deny**, the watch shows "Access denied" with a
"tap to try again" prompt — this generates a fresh device identity and
submits a new request.

### Building & running

Builds with **Connect IQ SDK 9.1.0** on VS Code + the official Monkey C
extension. Requires JRE 11+ and a Garmin developer key.

#### VS Code

1. Install the **Monkey C** extension (Garmin).
2. Set `monkeyC.developerKeyPath` in VS Code settings to your developer key.
3. Open this folder.
4. Open any `.mc` file → **Run → Run Without Debugging** (`Ctrl+F5` on macOS;
   plain `F5` starts a debug session). Pick a device the first time
   (e.g. `fenix847mm`).

Flask icon in the left sidebar runs the Run No Evil unit tests in
`source/UtilitiesTest.mc`.

#### CLI

```sh
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b"
KEY="$HOME/Documents/Development/keys/garmin_developer/developer_key"

# Build
"$SDK/bin/monkeyc" -o bin/signalk-connect.prg -f monkey.jungle -y "$KEY" -d fenix847mm

# Start the simulator (once) then run
"$SDK/bin/connectiq" &
"$SDK/bin/monkeydo" bin/signalk-connect.prg fenix847mm

# Unit tests
"$SDK/bin/monkeyc" -o bin/signalk-connect.prg -f monkey.jungle -y "$KEY" -d fenix847mm --unit-test
"$SDK/bin/monkeydo" bin/signalk-connect.prg fenix847mm -t
```

See [`CLAUDE.md`](CLAUDE.md) for the full toolchain notes and source map.
