// Seeed Xiao ESP32-S3 + Wio-SX1262 kit. Source: meshtastic/firmware @ 771efca, variants/esp32s3/seeed_xiao_s3.
// Untested on hardware.
#pragma once
#define GW_BOARD_NAME "xiao_s3"
constexpr int kPinLoraSck = 7;
constexpr int kPinLoraMiso = 8;
constexpr int kPinLoraMosi = 9;
constexpr int kPinLoraCs = 41;
constexpr int kPinLoraDio1 = 39;
constexpr int kPinLoraBusy = 40;
constexpr int kPinLoraRst = 42;
constexpr float kTcxoVolts = 1.8f;  // DIO3
#define GW_LORA_RXEN 38
constexpr int kPinVext = -1;   // board power switch, -1 = none
constexpr bool kVextOn = false;
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
