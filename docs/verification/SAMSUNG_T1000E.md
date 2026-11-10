# Samsung and SenseCAP T1000-E bench record

The operator tested an installed GhostWave Android app on a Samsung phone with a SenseCAP T1000-E. The connection screen showed firmware `ghostwave-t1000e 0.1.0-dev.8`. The app build, Android version, phone model and radio hardware revision were not recorded.

| Check | Result | Evidence |
|---|---|---|
| Connect over Bluetooth | Pass | Operator confirmation and connection-screen screenshot showing the connected radio and firmware version |
| Reconnect with the app open | Pass | Operator toggled Bluetooth off and on at the phone and reported automatic reconnect |
| Display radio status | Pass | Operator confirmed node ID, battery level and position were visible |
| Connect-screen bottom inset | Clipping observed | Screenshot showed the end of the help text behind Samsung's navigation bar. Retest on a build containing #180. |

## Remaining device checks

Record the installed APK's build identifier and both firmware versions before the next run. Use the RAK4631 as the second endpoint. Record each direction separately for encrypted message receipt and sender delivery confirmation. For an identified bench-test SOS, record reception, acknowledgment and cancellation on both devices. Repeat the incoming message and SOS notification checks after the Samsung screen has been off for 30 minutes with background connection enabled. Record misses, duplicates and the observed reconnect behavior.
