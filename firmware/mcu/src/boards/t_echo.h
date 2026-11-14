// LilyGO T-Echo. Source: meshtastic/firmware @ 771efca, variants/nrf52840/t-echo.
// Untested on hardware.
#pragma once
#define GW_BOARD_NAME "t_echo"
constexpr int kPinLoraCs = 24;
constexpr int kPinLoraDio1 = 20;
constexpr int kPinLoraBusy = 17;
constexpr int kPinLoraRst = 25;
constexpr float kTcxoVolts = 1.8f;  // DIO3
constexpr int kPinVext = 12;   // board power switch, -1 = none
constexpr bool kVextOn = true;
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 1        // L76K on Serial1, powered with the board (kPinVext)
constexpr int kPinGpsRx = 41;     // P1.09, CPU <- GPS
constexpr int kPinGpsTx = 40;     // P1.08, CPU -> GPS
constexpr uint32_t kGpsBaud = 9600;
#define GW_GPS_STANDBY 34         // P1.02, HIGH = awake
#define GW_GPS_RESET 37           // P1.05 (PIN_GPS_REINIT), LOW = reset
#define GW_BUTTON_PIN 42          // P1.10, active LOW
#define GW_LED_PIN 15             // P0.15 green, lit LOW
#define GW_LED_ON LOW
#define GW_LED2_PIN 14            // P0.14 blue, lit LOW
#define GW_LED2_ON LOW
#define GW_HAS_BLE 1
// 1.54" e-ink, 200x200, SSD1681 (GDEH0154D67) on its own SPI bus (variant.h:
// PIN_EINK_*; PIN_EINK_EN 43 is the front light). The panel runs off the board
// power switch (kPinVext, P0.12) with the radio and GPS.
#define GW_HAS_OLED 1
#define GW_DISPLAY_EINK 1
#define GW_EINK_CS 30
#define GW_EINK_DC 28
#define GW_EINK_RST 2
#define GW_EINK_BUSY 3
#define GW_EINK_SCK 31
#define GW_EINK_MOSI 29
#define GW_EINK_MISO 39   // not wired; the SPI driver needs a pin (P1.07, unused)
#define GW_EINK_LIGHT 43
#define GW_EINK_W 200
#define GW_EINK_H 200
#define GW_EINK_ROTATION 3   // unchecked on a board: if the picture sits sideways, change it here
#define GW_NRF52 1
