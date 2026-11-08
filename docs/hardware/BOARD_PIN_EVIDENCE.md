# Board pin evidence schema

No pin assignments in this document are verified or usable for transmission.

For each physical board revision, record:
- Board and baseboard model, PCB revision, bootloader, manufacturer schematic URL and schematic revision
- SX1262 SPI bus, NSS, RESET, BUSY, DIO1, optional DIO2 RF switch, TCXO control and voltage, regulator enable
- Antenna switch, power rails, maximum permitted power, regional operating constraints
- Reviewer, date, source URL, and independent cross-check

Reject blank, placeholder, guessed, or conflicting pin assignments. No mapping is approved merely because it compiles. This is a documentation contract only.

## RAK4631 on RAK19007 / RAK19003: desk check (not hardware-verified)

Used by `firmware/mcu` env `rak4631` (`src/board.h`, `variants/rak4631/variant.h`). Every pin agrees
across the three sources. No board has been probed, so this is a desk check and not a verification.
The qualification matrix stays pending until the bench test in `RAK4631_FLASHING.md` passes.

- **Board / baseboard:** RAK4631 WisBlock core (RAK4630 module: nRF52840 + SX1262) on a RAK19007 or
  RAK19003. PCB revision: not recorded yet; take it from the user's boards at the bench.
- **Bootloader:** Adafruit nRF52 UF2 bootloader with SoftDevice S140 6.1.1, as RAK ships it
  (`INFO_UF2.TXT` on the `RAK4631` drive). Application at 0x26000.
- **Sources:**
  - [RAK-DS] RAK4631 datasheet, the "RAK4630 internal connections" table (schematic URL:
    https://docs.rakwireless.com/product-categories/wisblock/rak4631/datasheet/).
  - [RAK-BSP] RAKWireless/RAK-nRF52-Arduino @ cc4b1bf, `variants/WisCore_RAK4631_Board/variant.h`.
  - [MT] meshtastic/firmware @ 11e3b28, `variants/nrf52840/rak4631/variant.h`.

| Signal | nRF52840 pin | Arduino pin | Sources |
|---|---|---|---|
| SPI bus SCK / MOSI / MISO | P1.11 / P1.12 / P1.13 | 43 / 44 / 45 | [RAK-DS] [MT] |
| NSS | P1.10 | 42 | [RAK-DS] [MT] `SX126X_CS` |
| RESET | P1.06 | 38 | [RAK-DS] [MT] `SX126X_RESET` |
| BUSY | P1.14 | 46 | [RAK-DS] [MT] `SX126X_BUSY` |
| DIO1 (IRQ) | P1.15 | 47 | [RAK-DS] [MT] `SX126X_DIO1` |
| TCXO | SX1262 DIO3, 1.8 V | — | DIO3: [RAK-DS] [MT]; 1.8 V: [MT] `SX126X_DIO3_TCXO_VOLTAGE` only |
| RF switch | SX1262 DIO2 | — | [RAK-DS] [MT] `SX126X_DIO2_AS_RF_SWITCH` |
| RF switch power | P1.05, HIGH = on | 37 | [RAK-DS] `ANT_SW` "RF switch power", [MT] `SX126X_POWER_EN` |
| P1.07 (also to the switch) | left undriven | 39 | [RAK-DS] [MT]: "should not be initialized" |
| 3V3_S rail enable (WB_IO2) | P1.02, HIGH = on | 34 | [MT] `PIN_3V3_EN` |
| LEDs green / blue | P1.03 / P1.04 | 35 / 36 | [RAK-BSP] [MT] |
| VBAT sense (not used yet) | P0.05 / AIN3 | 5 | [RAK-BSP] [MT] |

- **Power and region:** 10 dBm default and 22 dBm cap at the SX1262 output (there is no external PA).
  US 902–928 MHz only (DESIGN §12).
- **Difference from [RAK-BSP]:** RAK's variant makes the WisBlock slot bus (P0.03/P0.29/P0.30) the
  default SPI, and drives the radio through RAK's own SX126x library. GhostWave does what [MT] does:
  the internal SX1262 bus is `SPI` and the slot bus is `SPI1`.
- **Reviewer:** desk check by the GhostWave port session, 2026-11-07. Independent cross-check: the
  three sources above. Bench verification: pending.
