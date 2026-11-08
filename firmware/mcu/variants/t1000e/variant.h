// Arduino variant for the Seeed SenseCAP T1000-E (nRF52840 + LR1110 + AG3335
// GNSS), for GhostWave. Arduino pin N is GPIO N: P0.xx = xx, P1.xx = 32 + xx.
//
// Sources (cross-checked, see docs/hardware/BOARD_PIN_EVIDENCE.md):
//   [SEEED-SDK] Seeed-Studio/Seeed-Tracker-T1000-E-for-LoRaWAN-dev-board
//               @ 03147a9, smtc_hal/inc/smtc_hal_config.h
//   [SEEED-ARD] Seeed-Studio/Adafruit_nRF52_Arduino @ 667f05f,
//               variants/Seeed_Tracker_T1000_E_LoRaWAN/variant.h
//   [MT]        meshtastic/firmware @ 11e3b28 (develop),
//               variants/nrf52840/tracker-t1000-e/variant.h
#ifndef GHOSTWAVE_VARIANT_T1000E_H
#define GHOSTWAVE_VARIANT_T1000E_H

#define VARIANT_MCK (64000000ul)
#define USE_LFXO

#include "WVariant.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PINS_COUNT (48)
#define NUM_DIGITAL_PINS (48)
#define NUM_ANALOG_INPUTS (6)
#define NUM_ANALOG_OUTPUTS (0)

// One LED, green, P0.24, active high [SEEED-SDK USER_LED_G][MT PIN_LED1].
// ([SEEED-SDK] also names P0.03 USER_LED_R; Meshtastic does not use it.)
#define PIN_LED1 (24)
#define LED_BUILTIN PIN_LED1
#define LED_GREEN PIN_LED1
#define LED_BLUE PIN_LED1      // the core wants one; there is no blue LED
#define LED_STATE_ON 1

// The one button, P0.06, active high with a pull-down [SEEED-SDK][MT]
#define PIN_BUTTON1 (6)

// Analog: P0.02/AIN0 battery divider [SEEED-SDK SENSE_ADC_BAT][MT BATTERY_PIN]
#define PIN_A0 (2)
#define PIN_A1 (4)
#define PIN_A2 (5)
#define PIN_A3 (29)
#define PIN_A4 (31)
#define PIN_A5 (0xff)
#define PIN_A6 (0xff)
#define PIN_A7 (0xff)
static const uint8_t A0 = PIN_A0;
static const uint8_t A1 = PIN_A1;
static const uint8_t A2 = PIN_A2;
static const uint8_t A3 = PIN_A3;
static const uint8_t A4 = PIN_A4;
static const uint8_t A5 = PIN_A5;
static const uint8_t A6 = PIN_A6;
static const uint8_t A7 = PIN_A7;
#define ADC_RESOLUTION 14
#define PIN_AREF (0xff)
static const uint8_t AREF = PIN_AREF;
#define PIN_NFC1 (9)
#define PIN_NFC2 (10)

// Serial1 = AG3335 GNSS: nRF RX P0.14, nRF TX P0.13 [SEEED-SDK AG3335_UART_*][MT]
#define PIN_SERIAL1_RX (14)
#define PIN_SERIAL1_TX (13)
// Serial2 = debug UART pads [SEEED-SDK DEBUG_*]
#define PIN_SERIAL2_RX (17)
#define PIN_SERIAL2_TX (16)

// SPI = LR1110: SCK P0.11, MOSI P1.09, MISO P1.08, NSS P0.12 [SEEED-SDK][SEEED-ARD][MT]
#define SPI_INTERFACES_COUNT 1
#define PIN_SPI_MISO (40)
#define PIN_SPI_MOSI (41)
#define PIN_SPI_SCK (11)
static const uint8_t SS = 12;
static const uint8_t MOSI = PIN_SPI_MOSI;
static const uint8_t MISO = PIN_SPI_MISO;
static const uint8_t SCK = PIN_SPI_SCK;

// I2C: accelerometer (unused) [SEEED-SDK][MT]
#define WIRE_INTERFACES_COUNT 1
#define PIN_WIRE_SDA (26)
#define PIN_WIRE_SCL (27)

#ifdef __cplusplus
}
#endif

#endif
