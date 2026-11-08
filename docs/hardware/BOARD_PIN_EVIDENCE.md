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

## Seeed SenseCAP T1000-E: desk check (not hardware-verified)

Used by `firmware/mcu` env `t1000e` (`src/board.h`, `variants/t1000e/variant.h`). No board has been
probed. The qualification matrix stays pending until the bench test in `T1000E_FLASHING.md` passes.

- **Board:** Seeed SenseCAP T1000-E: nRF52840, Semtech LR1110, Airoha AG3335 GNSS, one button, a
  buzzer, a green LED and a Li-ion cell. PCB revision: not recorded yet; take it from the user's
  unit at the bench.
- **Bootloader:** Seeed's UF2 bootloader with SoftDevice S140 **7.3.0** (Meshtastic's board file:
  `sd_version 7.3.0`). Application at 0x27000 (our `variants/t1000e/nrf52840_s140_v7.ld`).
- **Sources:**
  - [SEEED-SDK] Seeed-Studio/Seeed-Tracker-T1000-E-for-LoRaWAN-dev-board @ 03147a9:
    `smtc_hal/inc/smtc_hal_config.h` (pins), `t1000_e/LR11XX/smtc_shield_lr11xx/common/src/smtc_shield_lr11x0_common.c`
    (RF switch, TCXO).
  - [SEEED-ARD] Seeed-Studio/Adafruit_nRF52_Arduino @ 667f05f:
    `variants/Seeed_Tracker_T1000_E_LoRaWAN/variant.h`, `libraries/LBM_T1000E/.../ral_lr11xx_bsp.c`.
  - [MT] meshtastic/firmware @ 11e3b28: `variants/nrf52840/tracker-t1000-e/variant.h`, `rfswitch.h`,
    `boards/tracker-t1000-e.json`.
  - Schematic URL: Seeed has not published one that we found. The product wiki is
    https://wiki.seeedstudio.com/sensecap_t1000_e/.

| Signal | nRF52840 pin | Arduino pin | Sources |
|---|---|---|---|
| SPI bus SCK / MOSI / MISO | P0.11 / P1.09 / P1.08 | 11 / 41 / 40 | [SEEED-SDK] [SEEED-ARD] [MT] |
| NSS | P0.12 | 12 | [SEEED-SDK] [SEEED-ARD] [MT] |
| RESET (NRESET) | P1.10 | 42 | [SEEED-SDK] [MT] |
| BUSY | P0.07 | 7 | [SEEED-SDK] [MT] |
| DIO1 / IRQ (LR1110 DIO9) | P1.01 | 33 | [SEEED-SDK] [SEEED-ARD] [MT] |
| RF switch | LR1110 DIO5–DIO8 (RFSW0–3): rx 0+3, tx 0+1+3, tx_hp 1+3, gnss 2 | — | [SEEED-SDK] [MT] agree. [SEEED-ARD] differs (no RFSW3). |
| TCXO | LR1110 VTCXO, **1.6 V** used | — | **Conflict:** [MT] 1.6 V, [SEEED-ARD] 1.8 V, [SEEED-SDK] 3.0 V. 1.6 V is what every Meshtastic T1000-E runs, and RadioLib's default. Override with `-DGW_TCXO_VOLTS=…`. Verify on the bench. |
| GNSS UART (nRF RX / TX) | P0.14 / P0.13, 115200 | 14 / 13 | [SEEED-SDK] [SEEED-ARD] [MT] |
| GNSS power / VRTC / reset | P1.11 HIGH / P0.08 HIGH / P1.15 LOW = running | 43 / 8 / 47 | [SEEED-SDK] names, [MT] levels (`GPS_RESET_MODE HIGH`) |
| GNSS sleep / RTC int / RESETB out | P1.12 HIGH / P0.15 LOW / P1.14 input pull-up | 44 / 15 / 46 | [SEEED-SDK] [MT] |
| Button | P0.06, active HIGH, pull-down | 6 | [SEEED-SDK] [MT] |
| LED (green) | P0.24, active HIGH | 24 | [SEEED-SDK] [SEEED-ARD] [MT] |
| Buzzer enable / PWM | P1.05 HIGH / P0.25 | 37 / 25 | [SEEED-SDK] [SEEED-ARD] [MT] |
| Battery | P0.02 / AIN0, VBAT ÷ 2, 3.0 V reference | 2 | [SEEED-SDK] (`SENSE_ADC_BAT`), [MT] (`ADC_MULTIPLIER 2.0`, `AREF_VOLTAGE 3.0`) |
| Sensor power | P1.06 HIGH | 38 | [SEEED-SDK] `SENSE_POWER_EN`, [MT] `PIN_3V3_EN` |
| P0.04 | left undriven | 4 | **Conflict:** [MT] drives it HIGH as a sensor enable. [SEEED-SDK] lists it as `SENSE_ADC_VCC`, an analog input. |

- **Sync word:** the LR1110 gets the one-byte LoRa sync word 0x24. RadioLib 7.8.1 programs an SX1262
  with `setSyncWord(0x24, 0x44)` = register 0x2444. The LR1110's one-byte form maps to the SX126x
  two-byte form the same way (0x12 ↔ 0x1424, 0x34 ↔ 0x3444), so the two chips send the same sync
  symbols. SF9 / BW125 / CR 4/5 / 16-symbol preamble / CRC on go through the same RadioLib `begin()`
  parameters as on the SX1262.
- **Power and region:** 10 dBm default, 22 dBm cap (above 14 dBm RadioLib selects the high-power PA).
  US 902–928 MHz only.
- **Reviewer:** desk check by the GhostWave port session, 2026-11-07. Independent cross-check: the
  three sources above. Bench verification: pending.
