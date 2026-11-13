# LilyGO T-Beam (SX1276 version)

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `t_beam_sx1276` (`cd firmware/mcu && pio run -e t_beam_sx1276`). Pins come from meshtastic/firmware @ 771efca, `variants/esp32/tbeam and src/Power.cpp`.

Flash with `pio run -t upload`. The phone app connects over Bluetooth (pairing key `654321`), as on the nRF boards. Built, not yet tried on this board.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. GPS, buttons and other extras are not used yet.

For T-Beams with an AXP192 or AXP2101 power chip. The SX1276 is limited to 17 dBm here. Whether it talks to SX1262 boards has not been tested. GPS is not used.
