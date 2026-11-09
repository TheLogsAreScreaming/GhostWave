// Generic nRF52840 pin map: Arduino pin N = GPIO N. PIN_SPI_SCK, _MISO and
// _MOSI come from the board's boards.d/<env>.ini.
// Arduino variant for the RAKwireless RAK4631 WisBlock core (nRF52840 +
// SX1262) on the Adafruit nRF52 core, for GhostWave. Arduino pin N is GPIO
// N: P0.xx = xx, P1.xx = 32 + xx.
//
// Sources (cross-checked, see docs/hardware/BOARD_PIN_EVIDENCE.md):
//   [RAK-DS]  RAK4631 datasheet, "RAK4630 internal connections" table
//             https://docs.rakwireless.com/product-categories/wisblock/rak4631/datasheet/
//   [RAK-BSP] RAKWireless/RAK-nRF52-Arduino @ cc4b1bf,
//             variants/WisCore_RAK4631_Board/variant.h
//   [MT]      meshtastic/firmware @ 11e3b28 (develop, 2026-11-07),
//             variants/nrf52840/rak4631/variant.h
//
// Difference from [RAK-BSP]: there the default SPI is the WisBlock slot bus
// (P0.03/P0.29/P0.30) and the radio is driven by RAK's own SX126x library.
// Here, as in [MT], the default SPI is the internal SX1262 bus, so RadioLib
// can use `SPI` directly, and SPI1 is the slot bus.
#ifndef GHOSTWAVE_VARIANT_GW_NRF52840_H
#define GHOSTWAVE_VARIANT_GW_NRF52840_H

#define VARIANT_MCK (64000000ul)
#define USE_LFXO   // 32.768 kHz crystal on the module

#include "WVariant.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PINS_COUNT (48)
#define NUM_DIGITAL_PINS (48)
#define NUM_ANALOG_INPUTS (6)
#define NUM_ANALOG_OUTPUTS (0)

// LEDs on the RAK19007/19003 base board: green P1.03, blue P1.04 [RAK-BSP][MT]
#define PIN_LED1 (0xff)   // none driven: boards differ
#define PIN_LED2 (0xff)   // none driven: boards differ
#define LED_BUILTIN PIN_LED1
#define LED_CONN PIN_LED2
#define LED_GREEN PIN_LED1
#define LED_BLUE PIN_LED2
#define LED_STATE_ON 1

// Analog. A0 = P0.05 = AIN3, the base board's VBAT divider [RAK-BSP][MT]
#define PIN_A0 (5)
#define PIN_A1 (31)
#define PIN_A2 (28)
#define PIN_A3 (29)
#define PIN_A4 (30)
#define PIN_A5 (31)
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
#define PIN_AREF (2)
#define PIN_NFC1 (9)
#define PIN_NFC2 (10)
static const uint8_t AREF = PIN_AREF;

// UART1 on the WisBlock connector (GPS slot) [RAK-BSP][MT]
#define PIN_SERIAL1_RX (15)
#define PIN_SERIAL1_TX (16)
#define PIN_SERIAL2_RX (8)
#define PIN_SERIAL2_TX (6)

// SPI = internal SX1262 bus: P1.11 SCK, P1.12 MOSI, P1.13 MISO [RAK-DS][MT]
// SPI1 = WisBlock slot bus [RAK-BSP][MT]
#define SPI_INTERFACES_COUNT 2
#define PIN_SPI1_MISO (29)
#define PIN_SPI1_MOSI (30)
#define PIN_SPI1_SCK (3)
static const uint8_t SS = 42;   // SX1262 NSS, P1.10
static const uint8_t MOSI = PIN_SPI_MOSI;
static const uint8_t MISO = PIN_SPI_MISO;
static const uint8_t SCK = PIN_SPI_SCK;

// I2C on the WisBlock connector [RAK-BSP][MT]
#define WIRE_INTERFACES_COUNT 2
#define PIN_WIRE_SDA (13)
#define PIN_WIRE_SCL (14)
#define PIN_WIRE1_SDA (24)
#define PIN_WIRE1_SCL (25)

// WisBlock IO2 = P1.02: enables the switched 3V3_S rail for slot modules [MT]
#define WB_IO2 (34)

#ifdef __cplusplus
}
#endif

#endif
