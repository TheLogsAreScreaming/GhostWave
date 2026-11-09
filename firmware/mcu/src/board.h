// Per-board pin maps. The ESP32 values come from Meshtastic's variant files at
// meshtastic/firmware commit 7579bfe (2026-10-15), the RAK4631 ones from RAK's
// datasheet cross-checked against RAK's BSP and Meshtastic (variants/rak4631/
// variant.h has the sources). Nothing is guessed: what the sources do not
// state is marked.
#pragma once

#include <stdint.h>

#if defined(GW_BOARD_FILE)
// One header per board in src/boards/, chosen in boards.d/<env>.ini.
#include GW_BOARD_FILE
#elif defined(GW_BOARD_TRACKER_V2)
// Source: variants/esp32s3/heltec_wireless_tracker_v2/variant.h
//         (+ pins_arduino.h there for SCK/MISO/MOSI/SS, src/configuration.h for
//          TX_GAIN_LORA, src/mesh/LoRaFEMInterface.cpp for FEM sequencing)
#define GW_BOARD_NAME "heltec_wireless_tracker_v2"
constexpr int kPinLoraSck = 9;
constexpr int kPinLoraMiso = 11;
constexpr int kPinLoraMosi = 10;
constexpr int kPinLoraCs = 8;
constexpr int kPinLoraDio1 = 14;    // SX1262 IRQ
constexpr int kPinLoraBusy = 13;    // variant calls it LORA_DIO2 / SX126X_BUSY
constexpr int kPinLoraRst = 12;
constexpr float kTcxoVolts = 1.8f;  // SX126X_DIO3_TCXO_VOLTAGE
// DIO2 drives the RF switch (SX126X_DIO2_AS_RF_SWITCH); it is wired to the
// KCT8103L FEM's CPS pin.

// KCT8103L front end (PA + LNA). TX: CSD=1 CTX=1. RX with LNA: CSD=1 CTX=0.
#define GW_HAS_KCT8103L 1
constexpr int kPinFemPower = 7;     // LORA_PA_POWER: FEM LDO enable, HIGH = on
constexpr int kPinFemCsd = 4;       // LORA_KCT8103L_PA_CSD: HIGH = chip on
constexpr int kPinFemCtx = 5;       // LORA_KCT8103L_PA_CTX: HIGH = TX / RX bypass, LOW = RX LNA
// TX_GAIN_LORA for HELTEC_WIRELESS_TRACKER_V2: dB of FEM gain at each SX1262
// drive level 0..21 dBm. Meshtastic's numbers, not measured by us.
constexpr uint8_t kPaGainDb[22] = {14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
                                   14, 13, 13, 13, 12, 12, 11, 10, 9,  8,  7};

#define GW_HAS_GPS 1
constexpr int kPinVext = 3;         // VEXT_ENABLE: powers GPS, GPS LNA and TFT
constexpr bool kVextOn = true;      // VEXT_ON_VALUE HIGH
constexpr int kPinGpsRx = 33;       // GPS_RX_PIN (ESP32 RX <- GPS TX)
constexpr int kPinGpsTx = 34;       // GPS_TX_PIN (ESP32 TX -> GPS RX)
constexpr int kPinGpsReset = 35;    // PIN_GPS_RESET; GPS_RESET_MODE LOW = held in reset
constexpr uint32_t kGpsBaud = 115200;   // GPS_BAUDRATE (UC6580)

#elif defined(GW_BOARD_HELTEC_V3)
// Source: variants/esp32s3/heltec_v3/variant.h
#ifndef GW_BOARD_NAME
#define GW_BOARD_NAME "heltec_v3"
#endif
constexpr int kPinLoraSck = 9;
constexpr int kPinLoraMiso = 11;
constexpr int kPinLoraMosi = 10;
constexpr int kPinLoraCs = 8;
constexpr int kPinLoraDio1 = 14;
constexpr int kPinLoraBusy = 13;
constexpr int kPinLoraRst = 12;
constexpr float kTcxoVolts = 1.8f;
// DIO2 drives the RF switch. No external PA: output = SX1262 drive.
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
// VEXT_ENABLE is `Vext` from the Arduino core's heltec_wifi_lora_32_V3
// pins_arduino.h (GPIO 36), active LOW (Meshtastic's default VEXT_ON_VALUE).
// The variant says it powers "the oled display and the lora antenna boost".
// Not confirmed from a schematic that it touches the RF path, so it is
// switched on exactly as Meshtastic does.
constexpr int kPinVext = 36;
constexpr bool kVextOn = false;     // LOW = on

#elif defined(GW_BOARD_RAK4631)
// Sources: RAK4631 datasheet "RAK4630 internal connections" table, cross-
// checked with meshtastic/firmware @ 11e3b28 variants/nrf52840/rak4631/
// variant.h (SX126X_*). Arduino pin = GPIO number, P1.xx = 32 + xx.
#ifndef GW_BOARD_NAME
#define GW_BOARD_NAME "rak4631"
#endif
constexpr int kPinLoraCs = 42;      // P1.10 NSS
constexpr int kPinLoraDio1 = 47;    // P1.15 DIO1 (IRQ)
constexpr int kPinLoraBusy = 46;    // P1.14 BUSY
constexpr int kPinLoraRst = 38;     // P1.06 NRESET
// SCK P1.11 / MOSI P1.12 / MISO P1.13 are the variant's default SPI pins.
constexpr float kTcxoVolts = 1.8f;  // TCXO powered from DIO3 (SX126X_DIO3_TCXO_VOLTAGE)
// DIO2 drives the antenna switch (SX126X_DIO2_AS_RF_SWITCH). P1.05 powers
// that switch (RAK datasheet ANT_SW "SX1262 RF switch power", Meshtastic
// SX126X_POWER_EN): HIGH = on. P1.07 also reaches the switch on the
// schematic but must stay undriven: the datasheet says it "should not be
// initialized", as DIO2 controls the switch.
#define GW_HAS_ANT_POWER 1
constexpr int kPinAntPower = 37;    // P1.05
// WisBlock IO2 (P1.02) switches the 3V3_S rail for slot modules; Meshtastic
// turns it on at boot. Nothing GhostWave needs is on it, but a GPS or sensor
// module in a slot would be, so it is switched on the same way.
constexpr int kPin3v3SEnable = 34;
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0                // no GPS on a bare RAK19007: app or CLI position
#define GW_HAS_BLE 1
#define GW_NRF52 1

#elif defined(GW_BOARD_RAK3401_1W)
// RAK3401 core + RAK13302 1 W module (SX1262 + SKY66122 PA), for example the
// WisMesh High Power Booster kit. Sources: meshtastic/firmware
// variants/nrf52840/rak3401_1watt/variant.h and RAK's RAK13302 datasheet.
// The radio is on the WisBlock slot bus (SPI1), not the RAK4631's internal bus.
#define GW_BOARD_NAME "rak3401_1w"
constexpr int kPinLoraCs = 26;      // P0.26
constexpr int kPinLoraDio1 = 10;    // P0.10, an NFC pin: needs CONFIG_NFCT_PINS_AS_GPIOS
constexpr int kPinLoraBusy = 9;     // P0.09, an NFC pin
constexpr int kPinLoraRst = 4;      // P0.04
constexpr float kTcxoVolts = 1.8f;  // SX126X_DIO3_TCXO_VOLTAGE
#define GW_HAS_OLED 1               // RAK1921 in the I2C slot; optional, detected at boot
#define GW_LORA_SPI SPI1            // P0.03 SCK, P0.30 MOSI, P0.29 MISO (variants/rak4631)
#define GW_HAS_ANT_POWER 1
constexpr int kPinAntPower = 21;    // P0.21 SX126X_POWER_EN
constexpr int kPin3v3SEnable = 34;  // WB_IO2: the slot's 3V3_S rail, needed by the module
#define GW_HAS_KCT8103L 0
// TX_GAIN_LORA for RAK13302: dB of PA gain at each SX1262 drive level 0..21.
// Meshtastic's numbers, not measured by us. RAK's datasheet agrees: drive 13
// gives 21 dBm, 22 gives 30 dBm.
#define GW_HAS_PA_CURVE 1
constexpr uint8_t kPaGainDb[22] = {7, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 8};
#define GW_HAS_GPS 0
#define GW_HAS_BLE 1
#define GW_NRF52 1
#elif defined(GW_BOARD_T1000E)
// Seeed SenseCAP T1000-E. Sources: Seeed's T1000-E SDK (smtc_hal_config.h),
// Seeed's Arduino variant and meshtastic/firmware @ 11e3b28
// variants/nrf52840/tracker-t1000-e (variants/t1000e/variant.h cites them).
#define GW_BOARD_NAME "t1000e"
#define GW_RADIO_LR1110 1
constexpr int kPinLoraCs = 12;      // P0.12 NSS
constexpr int kPinLoraDio1 = 33;    // P1.01 LR1110 IRQ (DIO9)
constexpr int kPinLoraBusy = 7;     // P0.07 BUSY
constexpr int kPinLoraRst = 42;     // P1.10 NRESET
// SCK P0.11 / MOSI P1.09 / MISO P1.08 are the variant's default SPI pins.
// TCXO on the LR1110's VTCXO pin. The sources disagree: Meshtastic 1.6 V
// (LR11X0_DIO3_TCXO_VOLTAGE, used on every Meshtastic T1000-E), Seeed's
// Arduino LoRaWAN library 1.8 V, Seeed's SDK shield file 3.0 V. Meshtastic's
// value is the one proven on many boards, so it is used; see
// BOARD_PIN_EVIDENCE.md. -DGW_TCXO_VOLTS=... overrides it.
#ifndef GW_TCXO_VOLTS
#define GW_TCXO_VOLTS 1.6f
#endif
constexpr float kTcxoVolts = GW_TCXO_VOLTS;
#define GW_HAS_KCT8103L 0
#define GW_HAS_BLE 1
#define GW_NRF52 1

#define GW_HAS_GPS 1                // AG3335 on Serial1 (variant: RX P0.14, TX P0.13)
constexpr uint32_t kGpsBaud = 115200;   // Meshtastic GPS_BAUDRATE; AG3335 default
constexpr int kPinGpsPower = 43;    // P1.11 AG3335_POWER_EN, HIGH = on
constexpr int kPinGpsVrtc = 8;      // P0.08 AG3335_VRTC_EN, HIGH (backup RTC supply)
constexpr int kPinGpsReset = 47;    // P1.15 AG3335_RESET, HIGH = held in reset (Meshtastic GPS_RESET_MODE HIGH)
constexpr int kPinGpsSleepInt = 44; // P1.12 AG3335_SLEEP_INT, HIGH = awake
constexpr int kPinGpsRtcInt = 15;   // P0.15 AG3335_RTC_INT, LOW normally
constexpr int kPinGpsResetbOut = 46;// P1.14 AG3335_RESETB_OUT, input with pull-up

#define GW_HAS_UI 1                 // button + buzzer + LED + battery
constexpr int kPinButton = 6;       // P0.06, active HIGH, pull-down
constexpr int kPinLed = 24;         // P0.24 green, active HIGH
constexpr int kPinBuzzerEn = 37;    // P1.05 BUZZER_POWER_EN, HIGH = on
constexpr int kPinBuzzer = 25;      // P0.25 PWM
constexpr int kPinBattery = 2;      // P0.02 / AIN0, VBAT through a 1:2 divider (Meshtastic ADC_MULTIPLIER 2.0)
constexpr int kPinSensorPower = 38; // P1.06 SENSE_POWER_EN (Meshtastic PIN_3V3_EN): on, as Meshtastic does
// Not driven: P0.04, which Meshtastic drives HIGH as "sensor enable" but
// Seeed's SDK lists as SENSE_ADC_VCC, an analog input.

#else
#error "Define GW_BOARD_TRACKER_V2, GW_BOARD_HELTEC_V3, GW_BOARD_RAK4631, GW_BOARD_RAK3401_1W or GW_BOARD_T1000E (see platformio.ini)"
#endif

#ifndef GW_RADIO_LR1110
#define GW_RADIO_LR1110 0
#endif
#ifndef GW_HAS_UI
#define GW_HAS_UI 0
#endif

#ifndef GW_HAS_ANT_POWER
#define GW_HAS_ANT_POWER 0
#endif
#ifndef GW_HAS_OLED
#define GW_HAS_OLED 0
#endif
#ifndef GW_HAS_PA_CURVE
#define GW_HAS_PA_CURVE 0
#endif
#ifndef GW_LORA_SPI
#define GW_LORA_SPI SPI
#endif
#ifndef GW_HAS_BLE
#define GW_HAS_BLE 0
#endif
#ifndef GW_NRF52
#define GW_NRF52 0
#endif

// Conducted output ceiling at the antenna port. DESIGN §12 leaves the US rule
// path open (one fixed BW125 channel does not qualify for 15.247's 1 W), so
// this holds every preset at what a bare SX1262 can do until a compliance
// decision. On the Tracker V2 the FEM gain is subtracted before driving the
// SX1262, so the antenna port still sees at most this.
#ifndef GW_MAX_OUTPUT_DBM
#define GW_MAX_OUTPUT_DBM 22
#endif
constexpr int kMaxOutputDbm = GW_MAX_OUTPUT_DBM;
#if GW_NRF52
// First real radios for GhostWave: start low for bench tests (two boards a
// few metres apart). `power <dBm>` raises it.
constexpr int kDefaultOutputDbm = 10;
#else
constexpr int kDefaultOutputDbm = 20;
#endif

// Frequency limits and the duty-cycle cap are per region: region.h.
