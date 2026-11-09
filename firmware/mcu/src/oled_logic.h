// When the status screen dims or sleeps, and which page it shows. Pure logic
// with no Arduino calls, so the host tests check it (tests/test_oled_logic.cpp).
// There is no button on this board, so pages cycle by themselves and events wake it.
#pragma once

#include <cstdint>

namespace gw {
namespace mcu {

class ScreenPolicy {
 public:
  enum class Level { Bright, Dim, Off };

  static constexpr uint32_t kDimMs = 60000;      // a minute after the last event
  static constexpr uint32_t kOffMs = 600000;     // ten minutes after it
  static constexpr uint32_t kPageMs = 5000;

  void wake(uint32_t nowMs) {
    lastWake_ = nowMs;
    awake_ = true;
  }

  // Wakes and shows `page` first, for one page period.
  void show(uint8_t page, uint32_t nowMs) {
    wake(nowMs);
    page_ = page;
    pageSince_ = nowMs;
  }

  Level level(uint32_t nowMs) const {
    if (!awake_) return Level::Off;
    uint32_t idle = nowMs - lastWake_;
    if (idle >= kOffMs) return Level::Off;
    return idle >= kDimMs ? Level::Dim : Level::Bright;
  }

  // The page to draw now, advancing every kPageMs through `pages` pages.
  uint8_t page(uint32_t nowMs, uint8_t pages) {
    if (pages == 0) return 0;
    if (page_ >= pages) page_ = 0;
    if (nowMs - pageSince_ >= kPageMs) {
      page_ = static_cast<uint8_t>((page_ + 1) % pages);
      pageSince_ = nowMs;
    }
    return page_;
  }

 private:
  bool awake_ = false;
  uint32_t lastWake_ = 0, pageSince_ = 0;
  uint8_t page_ = 0;
};

}  // namespace mcu
}  // namespace gw
