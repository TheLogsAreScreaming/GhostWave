// Heltec Mesh Node T114. Source: meshtastic/firmware @ 771efca, variants/nrf52840/heltec_mesh_node_t114.
// Untested on hardware.
#pragma once
#define GW_BOARD_NAME "heltec_t114"
constexpr int kPinLoraCs = 24;
constexpr int kPinLoraDio1 = 20;
constexpr int kPinLoraBusy = 17;
constexpr int kPinLoraRst = 25;
constexpr float kTcxoVolts = 1.8f;  // DIO3
constexpr int kPinVext = 21;   // board power switch, -1 = none
constexpr bool kVextOn = true;
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
#define GW_HAS_BLE 1
#define GW_NRF52 1
