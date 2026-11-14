// What the status LEDs show at a moment. Pure logic with no Arduino calls, so
// the host tests check it (firmware/tests/test_led_pattern.cpp).
#pragma once

#include <cstdint>

namespace gw {
namespace mcu {

struct LedState {
  bool status;   // the first LED (green, or the board's only one)
  bool link;     // the second LED: on while a phone is connected
};

constexpr uint32_t kLedPeriodMs = 5000;   // the "running" blink
constexpr uint32_t kLedBlinkMs = 40;
constexpr uint32_t kLedSosPeriodMs = 1000;
constexpr uint32_t kLedSosOnMs = 150;

inline LedState ledState(uint32_t nowMs, bool sosActive, bool phoneConnected, bool hasLinkLed) {
  LedState s{false, hasLinkLed && phoneConnected};
  if (sosActive) {
    s.status = nowMs % kLedSosPeriodMs < kLedSosOnMs;
    return s;
  }
  const uint32_t t = nowMs % kLedPeriodMs;
  s.status = t < kLedBlinkMs;
  // One LED only: a second blink just after the first means "phone connected".
  if (!hasLinkLed && phoneConnected && t >= 4 * kLedBlinkMs && t < 5 * kLedBlinkMs) s.status = true;
  return s;
}

}  // namespace mcu
}  // namespace gw
