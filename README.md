## signalk garmin smartwatch app

Connect IQ App that display boat data and let you control an autopilot using the open marine data standard [SignalK](http://signalk.org)

For the garmin app to work you need the following plugin installed on your [signalk nodejs server](https://github.com/SignalK/signalk-server-node).

[Autopilot plugin](https://github.com/beat843796/signalk-raymarine-autopilot)

[Minimal vessel data plugin](https://github.com/beat843796/signalk-minimalvesseldata-plugin)

### Screenshots

![Image 1](https://github.com/beat843796/signalk-garmin-smartwatchapp/raw/master/doc/sc1.jpg)
![Image 2](https://github.com/beat843796/signalk-garmin-smartwatchapp/raw/master/doc/sc2.jpg)
![Image 3](https://github.com/beat843796/signalk-garmin-smartwatchapp/raw/master/doc/sc3.jpg)

### Building & running

Builds with **Connect IQ SDK 9.1.0** on VS Code + the official Monkey C
extension. Requires JRE 11+ and a Garmin developer key.

#### VS Code

1. Install the **Monkey C** extension (Garmin).
2. Set `monkeyC.developerKeyPath` in VS Code settings to your Garmin developer key.
3. Open this folder.
4. Command Palette → **Monkey C: Verify Installation** (once).
5. Open any `.mc` file → **Run → Run Without Debugging** (`Cmd+F5`) → pick a
   device (e.g. `fenix5`). The extension generates `.vscode/launch.json`
   automatically.
6. To export a sideload PRG: **Monkey C: Build for Device**.

The Test Explorer (flask icon on the left) runs the Run No Evil unit tests in
`source/UtilitiesTest.mc`.

#### CLI

```sh
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b"
KEY="$HOME/Documents/Development/keys/garmin_developer/developer_key"

# Build
"$SDK/bin/monkeyc" -o bin/siriconnect.prg -f monkey.jungle -y "$KEY" -d fenix5

# Start the simulator (once) then run
"$SDK/bin/connectiq" &
"$SDK/bin/monkeydo" bin/siriconnect.prg fenix5

# Unit tests
"$SDK/bin/monkeyc" -o bin/siriconnect.prg -f monkey.jungle -y "$KEY" -d fenix5 --unit-test
"$SDK/bin/monkeydo" bin/siriconnect.prg fenix5 -t
```

Supported device ids are listed in `manifest.xml` (fenix5 family, fr645, fr935,
fenixchronos). See [`CLAUDE.md`](CLAUDE.md) for the full toolchain notes,
source-file map, and migration caveats.
