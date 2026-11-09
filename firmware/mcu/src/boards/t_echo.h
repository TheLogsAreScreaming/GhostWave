// LilyGO T-Echo. Source: meshtastic/firmware @ 771efca, variants/nrf52840/t-echo.
// Untested on hardware.
#pragma once
#define GW_BOARD_NAME "t_echo"
constexpr int kPinLoraCs = 24;
constexpr int kPinLoraDio1 = 20;
constexpr int kPinLoraBusy = 17;
constexpr int kPinLoraRst = 25;
constexpr float kTcxoVolts = 1.8f;  // DIO3
constexpr int kPinVext = 12;   // board power switch, -1 = none
constexpr bool kVextOn = true;
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
#define GW_HAS_BLE 1
#define GW_NRF52 1
