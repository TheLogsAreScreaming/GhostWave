// LilyGO T-LoRa V2.1-1.6. Source: meshtastic/firmware @ 771efca, variants/esp32/tlora_v2_1_16.
// Untested on hardware.
#pragma once
#define GW_BOARD_NAME "tlora_v2_1_6"
constexpr int kPinLoraSck = 5;
constexpr int kPinLoraMiso = 19;
constexpr int kPinLoraMosi = 27;
constexpr int kPinLoraCs = 18;
constexpr int kPinLoraDio1 = 26;
constexpr int kPinLoraBusy = 33;
constexpr int kPinLoraRst = 23;
constexpr float kTcxoVolts = 1.8f;  // DIO3
#define GW_RADIO_SX1276 1
#define GW_MAX_OUTPUT_DBM 17
constexpr int kPinVext = -1;   // board power switch, -1 = none
constexpr bool kVextOn = false;
// 0.96" SSD1306 on I2C SDA 21, SCL 22 (LilyGo T-LoRa V2.1-1.6), no reset line.
#define GW_HAS_OLED 1
#define GW_OLED_SDA 21
#define GW_OLED_SCL 22
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
