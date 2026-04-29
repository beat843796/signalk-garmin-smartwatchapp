# TODO

- [] add the AppVersion string resource and render it on the StatusView footer 
- [] Checkmark / X Icon for toasts
- [] Icons for menu items (SK, BLE, HELP)
- [] handle -300 error (when permission is missing...)
- [] use specific APIs that explicitly request WiFi-direct (some newer SDKs offer :options => {  transport => Communications.TRANSPORT_WIFI } style controls), or accept that the phone must be aboard and connected.
- [] fetch navionics map tiles and server through plugin as image load
- [] signalk crashes sometimes. im sure its one of the plugins lets check
- [x] shouldnt the access request for rest be made automatically?? -> NO
- [x] should the BLE connection after selection shouldnt start automatically?
- [] control audio
- [] Security to BLE
- [] Localization
- [] Combine autopilot and minimumvesseldata into one garmin-companion plugin
- [] remove BLE Disconnect (makes no sense unless for debugging)