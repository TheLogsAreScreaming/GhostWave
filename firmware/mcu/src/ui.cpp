#include "ui.h"

#if GW_HAS_UI

#include <Arduino.h>

namespace gw {
namespace mcu {
namespace ui {

namespace {

struct Step {
  uint16_t hz;     // 0 = silent
  bool led;
  uint16_t ms;
};

// Patterns end with {0, false, 0}.
const Step kAlive[] = {{3000, true, 60}, {0, false, 0}};
const Step kMessage[] = {{2200, true, 90}, {0, false, 90}, {2200, true, 90}, {0, false, 0}};
const Step kSosOn[] = {{2700, true, 400}, {0, false, 150}, {2700, true, 400}, {0, false, 150},
                       {2700, true, 400}, {0, false, 0}};
const Step kSosAcked[] = {{1500, true, 150}, {0, false, 60}, {2000, true, 150}, {0, false, 60},
                          {2600, true, 400}, {0, false, 0}};
const Step kSosOff[] = {{1200, true, 300}, {0, false, 0}};
const Step kRefused[] = {{400, true, 150}, {0, false, 100}, {400, true, 150}, {0, false, 0}};
const Step kProgress[] = {{1800, true, 40}, {0, false, 0}};

ButtonGesture g_button;
const Step* g_pat = nullptr;
size_t g_step = 0;
uint32_t g_stepEnd = 0;
uint32_t g_lastHoldBeep = 0;

uint32_t g_battMv = 0;
uint32_t g_nextBattMs = 0;

void startStep(uint32_t now) {
  const Step& s = g_pat[g_step];
  if (s.hz) tone(kPinBuzzer, s.hz);
  else noTone(kPinBuzzer);
  digitalWrite(kPinLed, s.led ? HIGH : LOW);
  g_stepEnd = now + s.ms;
}

void sampleBattery() {
  // VBAT / 2 on AIN0, 3.0 V internal reference, 12 bits (Meshtastic's T1000-E
  // settings: AREF 3.0, ADC_MULTIPLIER 2.0).
  analogReference(AR_INTERNAL_3_0);
  analogReadResolution(12);
  uint32_t sum = 0;
  for (int i = 0; i < 8; ++i) sum += analogRead(kPinBattery);
  g_battMv = (sum / 8) * 3000u * 2u / 4096u;
}

}  // namespace

void begin() {
  pinMode(kPinButton, INPUT_PULLDOWN);
  pinMode(kPinLed, OUTPUT);
  digitalWrite(kPinLed, LOW);
  pinMode(kPinBuzzerEn, OUTPUT);
  digitalWrite(kPinBuzzerEn, HIGH);
  pinMode(kPinBuzzer, OUTPUT);
  sampleBattery();
}

void play(Sound s) {
  switch (s) {
    case Sound::Alive: g_pat = kAlive; break;
    case Sound::Message: g_pat = kMessage; break;
    case Sound::SosOn: g_pat = kSosOn; break;
    case Sound::SosAcked: g_pat = kSosAcked; break;
    case Sound::SosOff: g_pat = kSosOff; break;
    case Sound::Refused: g_pat = kRefused; break;
    case Sound::HoldProgress: g_pat = kProgress; break;
  }
  g_step = 0;
  startStep(millis());
}

ButtonGesture::Event poll(uint32_t now, bool sosActive) {
  // pattern player
  if (g_pat && static_cast<int32_t>(now - g_stepEnd) >= 0) {
    if (g_pat[g_step].ms == 0) {
      noTone(kPinBuzzer);
      digitalWrite(kPinLed, LOW);
      g_pat = nullptr;
    } else {
      ++g_step;
      startStep(now);
    }
  }
  // SOS on: a 100 ms flash every 2 s while nothing else is playing
  if (!g_pat) digitalWrite(kPinLed, sosActive && now % 2000 < 100 ? HIGH : LOW);

  if (static_cast<int32_t>(now - g_nextBattMs) >= 0) {
    if (!g_pat) sampleBattery();   // the buzzer load would pull VBAT down
    g_nextBattMs = now + 30000;
  }

  auto ev = g_button.update(digitalRead(kPinButton) == HIGH, now);
  // ticks at 1 s and 2 s of a hold, so the user knows the long press is coming
  uint32_t held = g_button.heldMs(now);
  if (held >= 1000 && held < ButtonGesture::kLongMs && held / 1000 != g_lastHoldBeep) {
    g_lastHoldBeep = held / 1000;
    play(Sound::HoldProgress);
  }
  if (!g_button.held()) g_lastHoldBeep = 0;
  return ev;
}

uint32_t batteryMv() { return g_battMv; }
uint8_t batteryPct() { return batteryPercent(g_battMv); }

}  // namespace ui
}  // namespace mcu
}  // namespace gw

#endif
