// LilyGO T-Beam (SX1262 version). Source: meshtastic/firmware @ 771efca, variants/esp32/tbeam and src/Power.cpp.
// Untested on hardware.
#pragma once
#include <Wire.h>
#include <XPowersLib.h>
#define GW_BOARD_NAME "t_beam_sx1262"
constexpr int kPinLoraSck = 5;
constexpr int kPinLoraMiso = 19;
constexpr int kPinLoraMosi = 27;
constexpr int kPinLoraCs = 18;
constexpr int kPinLoraDio1 = 33;
constexpr int kPinLoraBusy = 32;
constexpr int kPinLoraRst = 23;
constexpr float kTcxoVolts = 1.8f;  // DIO3
constexpr int kPinVext = -1;   // board power switch, -1 = none
constexpr bool kVextOn = false;
// Optional SSD1306 add-on on the shared I2C bus (SDA 21, SCL 22, with the
// power chip); detected at boot, so a T-Beam without one just has no screen.
#define GW_HAS_OLED 1
#define GW_OLED_SDA 21
#define GW_OLED_SCL 22
#define GW_BUTTON_PIN 38   // the middle button, active LOW
#define GW_LED_PIN 4      // the extra LED on T-Beam 1.1, lit LOW
#define GW_LED_ON LOW
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
#define GW_HAS_BOARD_POWER 1
inline void gwBoardPower() {
  Wire.begin(21, 22);
  static XPowersAXP2101 a2101(Wire);
  static XPowersAXP192 a192(Wire);
  XPowersLibInterface& newer = a2101;
  XPowersLibInterface& older = a192;
  if (newer.init()) {
    newer.setPowerChannelVoltage(XPOWERS_ALDO2, 3300);   // radio rail on the AXP2101
    newer.enablePowerOutput(XPOWERS_ALDO2);
  } else if (older.init()) {
    older.setPowerChannelVoltage(XPOWERS_LDO2, 3300);    // radio rail on the AXP192
    older.enablePowerOutput(XPOWERS_LDO2);
  } else {
    Serial.println("power chip not found: the radio may be off");
  }
}
