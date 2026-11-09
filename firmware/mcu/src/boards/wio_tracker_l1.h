// Seeed Wio Tracker L1. Source: meshtastic/firmware @ 771efca, variants/nrf52840/seeed_wio_tracker_L1.
// Untested on hardware.
#pragma once
#define GW_BOARD_NAME "wio_tracker_l1"
constexpr int kPinLoraCs = 46;
constexpr int kPinLoraDio1 = 7;
constexpr int kPinLoraBusy = 42;
constexpr int kPinLoraRst = 39;
constexpr float kTcxoVolts = 1.8f;  // DIO3
#define GW_LORA_RXEN 40
constexpr int kPinVext = -1;   // board power switch, -1 = none
constexpr bool kVextOn = false;
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
#define GW_HAS_BLE 1
#define GW_NRF52 1
