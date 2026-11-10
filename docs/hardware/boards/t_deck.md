# LilyGO T-Deck

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `t_deck` (`cd firmware/mcu && pio run -e t_deck`). Pins come from meshtastic/firmware @ 771efca, `variants/esp32s3/t-deck`.

From `firmware/mcu`, flash with `pio run -e t_deck -t upload`. If several serial devices are attached, select this board explicitly with `--upload-port PORT`. Close any serial monitor before uploading. It is serial only: ESP32 builds have no Bluetooth phone link yet.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. GPS, buttons and other extras are not used yet.

The screen, keyboard and trackball are not used. Use the USB serial console.

## After an interrupted upload

Reconnect this board over USB, select its serial port again, then rerun the same `t_deck` upload command. If the port does not appear, use the manufacturer's download-mode procedure for the exact PCB revision. After upload, open `pio device monitor --port PORT --baud 115200` and run `status` to check the running firmware before a radio test.
