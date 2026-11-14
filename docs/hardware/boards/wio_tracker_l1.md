# Seeed Wio Tracker L1

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `wio_tracker_l1` (`cd firmware/mcu && pio run -e wio_tracker_l1`). Pins come from meshtastic/firmware @ 771efca, `variants/nrf52840/seeed_wio_tracker_L1`.

Flash the UF2 (`.pio/build/wio_tracker_l1/firmware.uf2`) through the bootloader drive. Check `INFO_UF2.TXT` first: this build needs SoftDevice **S140 7.3.0**. It has the Bluetooth phone link.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. The built-in GPS gives the node its position once it has a fix (`pos` shows it). The button: press it to turn the screen page (or wake a dark screen), hold it 3 seconds to start an SOS, double-press to stop it. The LED blinks every 5 seconds, twice when a phone is connected, and flashes once a second during an SOS.

The 0.96" OLED shows the status, node, neighbour and message pages, and the pairing key while the phone pairs.
