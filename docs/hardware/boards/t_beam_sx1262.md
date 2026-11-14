# LilyGO T-Beam (SX1262 version)

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `t_beam_sx1262` (`cd firmware/mcu && pio run -e t_beam_sx1262`). Pins come from meshtastic/firmware @ 771efca, `variants/esp32/tbeam and src/Power.cpp`.

Flash with `pio run -t upload`. The phone app connects over Bluetooth (pairing key `654321`), as on the nRF boards. Built, not yet tried on this board.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. The middle button: press it to turn the screen page, hold it 3 seconds to start an SOS, double-press to stop it. On T-Beam 1.1 the extra LED blinks every 5 seconds. GPS is not used yet: it needs the power chip switched on for it.

For T-Beams with an AXP192 or AXP2101 power chip. GPS is not used.
