// Turns raw button samples into gestures: a long press (held ~3 s, fires once
// while still held), a double press and a single press. Pure logic with no
// Arduino calls, so the host tests check it (firmware/tests/test_button_gesture.cpp).
#pragma once

#include <cstdint>

namespace gw {
namespace mcu {

class ButtonGesture {
 public:
  enum class Event { None, Single, Double, Long };

  static constexpr uint32_t kDebounceMs = 30;
  static constexpr uint32_t kLongMs = 3000;      // hold this long: Long (SOS)
  static constexpr uint32_t kShortMaxMs = 600;   // a press up to this long counts as a click
  static constexpr uint32_t kGapMs = 400;        // max release-to-press gap inside a double press

  // Call often (every few ms) with the raw level (true = pressed).
  Event update(bool pressed, uint32_t nowMs) {
    if (pressed != raw_) {
      raw_ = pressed;
      rawSince_ = nowMs;
    }
    if (raw_ != stable_ && nowMs - rawSince_ >= kDebounceMs) {
      stable_ = raw_;
      if (stable_) {
        pressStart_ = nowMs;
        longFired_ = false;
      } else if (!longFired_) {
        if (nowMs - pressStart_ <= kShortMaxMs + kDebounceMs) {
          if (++clicks_ == 2) {
            clicks_ = 0;
            return Event::Double;
          }
          lastRelease_ = nowMs;
        } else {
          clicks_ = 0;   // a medium press: nothing
        }
      }
    }
    if (stable_ && !longFired_ && nowMs - pressStart_ >= kLongMs) {
      longFired_ = true;
      clicks_ = 0;
      return Event::Long;
    }
    if (!stable_ && clicks_ == 1 && nowMs - lastRelease_ > kGapMs) {
      clicks_ = 0;
      return Event::Single;
    }
    return Event::None;
  }

  bool held() const { return stable_; }
  // How long the current press has lasted (0 when released).
  uint32_t heldMs(uint32_t nowMs) const { return stable_ ? nowMs - pressStart_ : 0; }

 private:
  bool raw_ = false, stable_ = false, longFired_ = false;
  uint32_t rawSince_ = 0, pressStart_ = 0, lastRelease_ = 0;
  int clicks_ = 0;
};

// Battery percent from a resting cell voltage: linear between the points of
// Meshtastic's T1000-E open-circuit table (OCV_ARRAY, 100 % .. 0 % in 10 %
// steps). 0xFF if mv is 0 (no reading).
inline uint8_t batteryPercent(uint32_t mv) {
  static const uint16_t kOcv[11] = {4190, 4042, 3957, 3885, 3820, 3776, 3746, 3725, 3696, 3644, 3100};
  if (mv == 0) return 0xFF;
  if (mv >= kOcv[0]) return 100;
  if (mv <= kOcv[10]) return 0;
  for (int i = 1; i < 11; ++i) {
    if (mv >= kOcv[i]) {
      // between kOcv[i] (100 - 10 i %) and kOcv[i - 1] (10 % more)
      uint32_t span = kOcv[i - 1] - kOcv[i];
      return static_cast<uint8_t>(100 - 10 * i + (10 * (mv - kOcv[i]) + span / 2) / span);
    }
  }
  return 0;
}

}  // namespace mcu
}  // namespace gw
