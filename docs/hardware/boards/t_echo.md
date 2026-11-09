# LilyGO T-Echo

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `t_echo` (`cd firmware/mcu && pio run -e t_echo`). Pins come from meshtastic/firmware @ 771efca, `variants/nrf52840/t-echo`.

Flash the UF2 (`.pio/build/t_echo/firmware.uf2`) through the bootloader drive. Check `INFO_UF2.TXT` first: this build needs SoftDevice **S140 6.1.1**. It has the Bluetooth phone link.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. GPS, buttons and other extras are not used yet.

Meshtastic marks this TCXO as optional. This build always asks for 1.8 V, so a board without a TCXO would report radio FAILED.
