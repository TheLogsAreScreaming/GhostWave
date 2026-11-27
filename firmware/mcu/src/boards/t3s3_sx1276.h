// LilyGO T3-S3 (SX1276 version). Source: LilyGO/LilyGO-T3S3 and meshtastic/firmware.
// Untested on hardware.
#pragma once
#define GW_BOARD_NAME "t3s3_sx1276"
#define GW_RADIO_SX1276 1
constexpr int kPinLoraSck = 5;
constexpr int kPinLoraMiso = 3;
constexpr int kPinLoraMosi = 6;
constexpr int kPinLoraCs = 7;
constexpr int kPinLoraDio1 = 9;    // DIO0 on SX1276 (IRQ); SX1276 uses DIO0 for RxDone/TxDone
constexpr int kPinLoraBusy = 33;   // DIO1 on SX1276
constexpr int kPinLoraRst = 8;
constexpr float kTcxoVolts = 0.0f;  // no TCXO on SX1276 version
constexpr int kPinVext = -1;   // board power switch, -1 = none
constexpr bool kVextOn = false;
// 0.96" SSD1306 on I2C SDA 18, SCL 17 (same as SX1262 version), no reset line.
#define GW_HAS_OLED 1
#define GW_OLED_SDA 18
#define GW_OLED_SCL 17
#define GW_BUTTON_PIN 0   // BOOT button, active LOW
#define GW_LED_PIN 37
#define GW_LED_ON HIGH
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
