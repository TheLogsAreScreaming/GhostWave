# Hardware selection reference

Use the product marking and radio variant to select a build. For UF2 boards, compare the SoftDevice shown in `INFO_UF2.TXT` with the build requirement. For ESP32 boards, specify the exact PlatformIO environment when uploading.

| Product | Build target | Bootloader requirement or MCU | Hardware detail | Source |
|---|---|---|---|---|
| RAK4631 + RAK19007 | `rak4631` | S140 6.1.1 | WisBlock core and base | [Board record](RAK4631_FLASHING.md) |
| SenseCAP T1000-E | `t1000e` | S140 7.3.0 | E model, LR1110 | [Board record](T1000E_FLASHING.md) |
| Heltec T114 | `heltec_t114` | S140 6.1.1 | Radio and Bluetooth build | [Board record](boards/heltec_t114.md) |
| Wio Tracker L1 | `wio_tracker_l1` | S140 7.3.0 | GPS unused by this target | [Board record](boards/wio_tracker_l1.md) |
| T-Echo | `t_echo` | S140 6.1.1 | Build expects 1.8 V TCXO | [Board record](boards/t_echo.md) |
| WiFi LoRa 32 V4 | `heltec_v4` | ESP32-S3 | Amplifier gain is estimated | [Board record](boards/heltec_v4.md) |
| WiFi LoRa 32 V3 | `heltec_v3` | ESP32-S3 | V3 board definition | [Board record](../../firmware/mcu/platformio.ini) |
| T3-S3 | `t3s3` | ESP32-S3 | SX1262 variant only | [Board record](boards/t3s3.md) |
| T-Deck | `t_deck` | ESP32-S3 | Original T-Deck, USB console | [Board record](boards/t_deck.md) |
| Wireless Tracker V2 | `heltec_wireless_tracker_v2` | ESP32-S3 | Tracker V2 pin map and GPS | [Board record](../../firmware/mcu/src/board.h) |
| Wireless Stick Lite V3 | `heltec_wsl_v3` | ESP32-S3 | Uses V3 radio pins and Vext configuration | [Board record](../../firmware/mcu/platformio.ini) |

Record the physical PCB revision and frequency-band marking from the unit under test in the [device worksheet](DEVICE_TEST_WORKSHEET.md). Software region selection alone cannot identify the fitted radio or antenna band. See the [qualification matrix](HARDWARE_QUALIFICATION_MATRIX.md) for hardware evidence.
