# LilyGO T-Deck

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `t_deck` (`cd firmware/mcu && pio run -e t_deck`). Pins come from meshtastic/firmware @ 771efca, `variants/esp32s3/t-deck`.

Flash with `pio run -t upload`. It is serial only: ESP32 builds have no Bluetooth phone link yet.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. GPS, buttons and other extras are not used yet.

The screen, keyboard and trackball are not used. Use the USB serial console.
