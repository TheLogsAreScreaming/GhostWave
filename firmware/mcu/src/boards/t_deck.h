// LilyGO T-Deck. Source: meshtastic/firmware @ 771efca, variants/esp32s3/t-deck.
// Untested on hardware.
#pragma once
#include <Arduino.h>
#define GW_BOARD_NAME "t_deck"
constexpr int kPinLoraSck = 40;
constexpr int kPinLoraMiso = 38;
constexpr int kPinLoraMosi = 41;
constexpr int kPinLoraCs = 9;
constexpr int kPinLoraDio1 = 45;
constexpr int kPinLoraBusy = 13;
constexpr int kPinLoraRst = 17;
constexpr float kTcxoVolts = 1.8f;  // DIO3
constexpr int kPinVext = 10;   // board power switch, -1 = none
constexpr bool kVextOn = true;
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
#define GW_HAS_BOARD_POWER 1
inline void gwBoardPower() {
  // Display and SD card share the radio SPI bus: keep them deselected.
  pinMode(12, OUTPUT);
  digitalWrite(12, HIGH);
  pinMode(39, OUTPUT);
  digitalWrite(39, HIGH);
}
