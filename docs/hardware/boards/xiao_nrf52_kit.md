# Seeed Xiao nRF52840 + Wio-SX1262 kit

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `xiao_nrf52_kit` (`cd firmware/mcu && pio run -e xiao_nrf52_kit`). Pins come from meshtastic/firmware @ 771efca, `variants/nrf52840/seeed_xiao_nrf52840_kit (default pinout)`.

Flash the UF2 (`.pio/build/xiao_nrf52_kit/firmware.uf2`) through the bootloader drive. Check `INFO_UF2.TXT` first: this build needs SoftDevice **S140 7.3.0**. It has the Bluetooth phone link.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. GPS, buttons and other extras are not used yet.
