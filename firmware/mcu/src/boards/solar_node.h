// Seeed SenseCAP Solar Node. Source: meshtastic/firmware @ 771efca, variants/nrf52840/seeed_solar_node.
// Untested on hardware.
#pragma once
#define GW_BOARD_NAME "solar_node"
constexpr int kPinLoraCs = 4;
constexpr int kPinLoraDio1 = 3;
constexpr int kPinLoraBusy = 29;
constexpr int kPinLoraRst = 28;
constexpr float kTcxoVolts = 1.8f;  // DIO3
#define GW_LORA_RXEN 5
constexpr int kPinVext = -1;   // board power switch, -1 = none
constexpr bool kVextOn = false;
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
#define GW_HAS_BLE 1
#define GW_NRF52 1
