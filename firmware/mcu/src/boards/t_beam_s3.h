// LilyGO T-Beam S3 Core (SX1262 version). Source: meshtastic/firmware @ 771efca, variants/esp32s3/tbeam-s3-core and src/Power.cpp.
// Untested on hardware.
#pragma once
#include <Wire.h>
#include <XPowersLib.h>
#define GW_BOARD_NAME "t_beam_s3"
constexpr int kPinLoraSck = 12;
constexpr int kPinLoraMiso = 13;
constexpr int kPinLoraMosi = 11;
constexpr int kPinLoraCs = 10;
constexpr int kPinLoraDio1 = 1;
constexpr int kPinLoraBusy = 4;
constexpr int kPinLoraRst = 5;
constexpr float kTcxoVolts = 1.8f;  // DIO3
constexpr int kPinVext = -1;   // board power switch, -1 = none
constexpr bool kVextOn = false;
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
#define GW_HAS_BOARD_POWER 1
inline void gwBoardPower() {
  // AXP2101 on I2C1: ALDO3 powers the radio.
  Wire1.begin(42, 41);
  static XPowersAXP2101 axp(Wire1);
  XPowersLibInterface& pmu = axp;   // these calls are public only on the interface
  if (pmu.init()) {
    pmu.setPowerChannelVoltage(XPOWERS_ALDO3, 3300);
    pmu.enablePowerOutput(XPOWERS_ALDO3);
  } else {
    Serial.println("power chip not found: the radio may be off");
  }
}
