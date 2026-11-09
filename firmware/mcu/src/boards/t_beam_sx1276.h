// LilyGO T-Beam (SX1276 version). Source: meshtastic/firmware @ 771efca, variants/esp32/tbeam and src/Power.cpp.
// Untested on hardware.
#pragma once
#include <Wire.h>
#include <XPowersLib.h>
#define GW_BOARD_NAME "t_beam_sx1276"
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
