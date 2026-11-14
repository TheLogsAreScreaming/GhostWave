// Heltec V4. Source: meshtastic/firmware @ 771efca, variants/esp32s3/heltec_v4 and src/mesh/LoRaFEMInterface.cpp.
// Untested on hardware.
#pragma once
#include <Arduino.h>
#include <cstring>
#define GW_HAS_PA_CURVE 1
#define GW_HAS_BOARD_FEM 1
// dB of gain at each SX1262 drive level 0..21: gc1109_tx_gain and
// kct8103l_tx_gain in Meshtastic's LoRaFEMInterface.cpp. Not measured by us.
constexpr uint8_t kGainGc1109[22] = {11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 10, 10, 9, 9, 8, 7};
constexpr uint8_t kGainKct8103l[22] = {13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 12, 12, 11, 11, 10, 9, 8, 7};
inline uint8_t kPaGainDb[22] = {13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13};
inline bool gwFemIsKct = false;
inline void gwFemRx() { digitalWrite(gwFemIsKct ? 5 : 46, LOW); }
inline void gwFemTx() { digitalWrite(gwFemIsKct ? 5 : 46, HIGH); }
#define GW_BOARD_NAME "heltec_v4"
constexpr int kPinLoraSck = 9;
constexpr int kPinLoraMiso = 11;
constexpr int kPinLoraMosi = 10;
constexpr int kPinLoraCs = 8;
constexpr int kPinLoraDio1 = 14;
constexpr int kPinLoraBusy = 13;
constexpr int kPinLoraRst = 12;
constexpr float kTcxoVolts = 1.8f;  // DIO3
constexpr int kPinVext = 36;   // board power switch, -1 = none
constexpr bool kVextOn = false;
// 0.96" SSD1306 wired as on the V3: SDA 17, SCL 18, reset 21, powered by Vext.
#define GW_HAS_OLED 1
#define GW_OLED_SDA 17
#define GW_OLED_SCL 18
#define GW_OLED_RST 21
// Battery: GPIO 1 through a divider switched in by GPIO 37 HIGH (variant.h:
// BATTERY_PIN 1, ADC_CTRL 37, ADC_CTRL_ENABLED HIGH, ADC_MULTIPLIER 4.9 * 1.045).
#define GW_BATT_ADC_PIN 1
#define GW_BATT_ADC_CTRL 37
#define GW_BATT_ADC_CTRL_ON HIGH
#define GW_BATT_ADC_MULT (4.9f * 1.045f)
#define GW_BUTTON_PIN 0   // PRG, active LOW
#define GW_BUTTON_SOS 0   // GPIO 0 is on the serial chip's DTR line: pages only
#define GW_HAS_KCT8103L 0
#define GW_HAS_GPS 0
#define GW_HAS_BOARD_POWER 1
inline void gwBoardPower() {
  // Two amplifier chips have shipped on the V4. Pin 2 reads HIGH on a KCT8103L
  // and LOW on a GC1109 (LoRaFEMInterface.cpp).
  pinMode(7, OUTPUT);
  digitalWrite(7, HIGH);   // LORA_PA_POWER
  delay(1);
  pinMode(2, INPUT);
  delay(1);
  gwFemIsKct = digitalRead(2) == HIGH;
  std::memcpy(kPaGainDb, gwFemIsKct ? kGainKct8103l : kGainGc1109, sizeof kPaGainDb);
  pinMode(2, OUTPUT);
  digitalWrite(2, HIGH);   // chip enabled
  pinMode(gwFemIsKct ? 5 : 46, OUTPUT);
  gwFemRx();
  Serial.printf("amplifier: %s\n", gwFemIsKct ? "KCT8103L" : "GC1109");
}
