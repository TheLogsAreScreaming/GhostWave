// Seeed Wio Tracker L1. Source: meshtastic/firmware @ 771efca, variants/nrf52840/seeed_wio_tracker_L1.
// Untested on hardware.
#pragma once
#define GW_BOARD_NAME "wio_tracker_l1"
constexpr int kPinLoraCs = 46;
constexpr int kPinLoraDio1 = 7;
constexpr int kPinLoraBusy = 42;
constexpr int kPinLoraRst = 39;
constexpr float kTcxoVolts = 1.8f;  // DIO3
#define GW_LORA_RXEN 40
constexpr int kPinVext = -1;   // board power switch, -1 = none
constexpr bool kVextOn = false;
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 1        // L76KB on Serial1
constexpr int kPinGpsRx = 26;     // P0.26, CPU <- GPS
constexpr int kPinGpsTx = 27;     // P0.27, CPU -> GPS
constexpr uint32_t kGpsBaud = 9600;
#define GW_GPS_STANDBY 41         // P1.09 GNSS_WAKEUP, HIGH = awake
#define GW_HAS_BLE 1
// 0.96" SSD1306 OLED on Wire: SDA P0.06, SCL P0.05 (Meshtastic variant.cpp's
// pin map; the comments in its variant.h name other pins).
#define GW_HAS_OLED 1
#define GW_OLED_SDA 6
#define GW_OLED_SCL 5
#define GW_BUTTON_PIN 8           // P0.08 user button, active LOW
#define GW_LED_PIN 33             // P1.01 user LED, lit HIGH
#define GW_LED_ON HIGH
#define GW_NRF52 1
