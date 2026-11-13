// Heltec Mesh Node T114. Source: meshtastic/firmware @ 771efca, variants/nrf52840/heltec_mesh_node_t114.
// Untested on hardware.
#pragma once
#define GW_BOARD_NAME "heltec_t114"
constexpr int kPinLoraCs = 24;
constexpr int kPinLoraDio1 = 20;
constexpr int kPinLoraBusy = 17;
constexpr int kPinLoraRst = 25;
constexpr float kTcxoVolts = 1.8f;  // DIO3
constexpr int kPinVext = 21;   // board power switch, -1 = none
constexpr bool kVextOn = true;
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
#define GW_HAS_BLE 1
// 1.14" ST7789 240x135 on its own SPI bus (variant.h: ST7789_*, VTFT_CTRL 3
// powers it when LOW, VTFT_LEDA 15 is the backlight, on when LOW).
#define GW_HAS_OLED 1
#define GW_DISPLAY_TFT 1
#define GW_TFT_CS 11
#define GW_TFT_DC 12
#define GW_TFT_RST 2
#define GW_TFT_MOSI 41
#define GW_TFT_SCK 40
#define GW_TFT_BL 15
#define GW_TFT_BL_ON LOW
#define GW_TFT_POWER 3
#define GW_TFT_POWER_ON LOW
#define GW_TFT_W 240
#define GW_TFT_H 135
#define GW_NRF52 1
