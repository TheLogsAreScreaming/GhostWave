# Seeed SenseCAP Solar Node

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `solar_node` (`cd firmware/mcu && pio run -e solar_node`). Pins come from meshtastic/firmware @ 771efca, `variants/nrf52840/seeed_solar_node`.

Flash the UF2 (`.pio/build/solar_node/firmware.uf2`) through the bootloader drive. Check `INFO_UF2.TXT` first: this build needs SoftDevice **S140 7.3.0**. It has the Bluetooth phone link.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. GPS, buttons and other extras are not used yet.
