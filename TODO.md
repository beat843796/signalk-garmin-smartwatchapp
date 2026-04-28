# TODO

- [] Plugin Error Screen: Show QR Code of plugin
- [x] BLE Support
- [] Handle Glances Properly (more frequent updates) or replace with sth more meaningful
- [] Improve launcher icon, does not work well on black BG
- [] BUGFIX: requesting access, killing server, request retry, not found after server restart
- [] BUG: 401 (no access request granted) shows MISSING PLUGIN ERROR
- [] add the AppVersion string resource and render it on the StatusView footer 
- [] wire up a pre-build script that stamps git short SHA into a BuildInfo.mc
- [] Checkmark / X Icon for toasts
- [] handle -300 error (when permission is missing...)
- [] use specific APIs that explicitly request WiFi-direct (some newer SDKs offer :options => {  transport => Communications.TRANSPORT_WIFI } style controls), or accept that the phone must be aboard and connected.
- [] Check if Communications.connectionAvailable
- [] fetch navionics map tiles and server through plugin as image load
- [] signalk crashes sometimes. im sure its one of the plugins lets check