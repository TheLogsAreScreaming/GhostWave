// LilyGO T3-S3 (SX1262 version). Source: meshtastic/firmware @ 771efca, variants/esp32s3/tlora_t3s3_v1.
// Untested on hardware.
#pragma once
#define GW_BOARD_NAME "t3s3"
constexpr int kPinLoraSck = 5;
constexpr int kPinLoraMiso = 3;
constexpr int kPinLoraMosi = 6;
constexpr int kPinLoraCs = 7;
constexpr int kPinLoraDio1 = 33;
constexpr int kPinLoraBusy = 34;
constexpr int kPinLoraRst = 8;
constexpr float kTcxoVolts = 1.8f;  // DIO3
constexpr int kPinVext = -1;   // board power switch, -1 = none
constexpr bool kVextOn = false;
// 0.96" SSD1306 on I2C SDA 18, SCL 17 (LilyGo T3-S3 utilities.h), no reset line.
#define GW_HAS_OLED 1
#define GW_OLED_SDA 18
#define GW_OLED_SCL 17
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
