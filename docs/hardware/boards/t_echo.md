# LilyGO T-Echo

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `t_echo` (`cd firmware/mcu && pio run -e t_echo`). Pins come from meshtastic/firmware @ 771efca, `variants/nrf52840/t-echo`.

Flash the UF2 (`.pio/build/t_echo/firmware.uf2`) through the bootloader drive. Check `INFO_UF2.TXT` first: this build needs SoftDevice **S140 6.1.1**. It has the Bluetooth phone link.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. The built-in GPS gives the node its position once it has a fix (`pos` shows it). The button: press it to turn the screen page (or wake a dark screen), hold it 3 seconds to start an SOS, double-press to stop it. The green LED blinks every 5 seconds, the blue LED stays on while a phone is connected, and green flashes once a second during an SOS.

Meshtastic marks this TCXO as optional. This build always asks for 1.8 V, so a board without a TCXO would report radio FAILED.

## E-ink screen

The 1.54" e-ink panel (200×200, SSD1681) shows the same status, node, neighbour and message pages as the OLED boards, drawn 1.5× in the middle of the panel. The pairing key appears there while the phone pairs.

E-ink keeps its picture with no power, wears a little with every refresh, and a full refresh takes about two seconds, so this screen behaves differently from the OLEDs:

* It refreshes only when the picture changes. Routine changes (counters, the next page) wait at least 20 seconds, and pages turn every 20 seconds instead of every 5.
* Events show within about a second: a new message, the pairing key, an SOS, Bluetooth or TX switching.
* Most refreshes are partial (quick, no flash). Every 30th one, at least once an hour while the picture is changing, and when the screen wakes or goes to sleep, it does a full refresh to clear ghosting.
* The SOS screen stays inverted (black) rather than flashing.
* After ten quiet minutes it does one last full refresh to the GhostWave splash and stops refreshing until something wakes it, so it never shows stale numbers.
* The controller sleeps between refreshes, and the loop never waits for one to finish. The front light stays off.

The panel's mounting rotation (`GW_EINK_ROTATION` in `firmware/mcu/src/boards/t_echo.h`) has not been checked on a board. If the picture sits sideways or upside down, change it there. The rules are host-tested in `firmware/tests/test_eink_logic.cpp`.
