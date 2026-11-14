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
  static constexpr uint32_t kEinkPageMs = 20000;  // e-ink: fewer page turns, fewer refreshes

  // How long each page stays up (kPageMs unless a board changes it).
  void setPagePeriod(uint32_t ms) { pageMs_ = ms ? ms : kPageMs; }

  // How long after the last event the screen goes off (the app's screen
  // timeout, 1.11); 0 = never off, it only dims. It dims after a minute, or
  // halfway through a shorter timeout.
  void setOffAfter(uint32_t ms) { offMs_ = ms; }
  uint32_t offAfter() const { return offMs_; }

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
    if (offMs_ && idle >= offMs_) return Level::Off;
    const uint32_t dim = offMs_ && offMs_ < 2 * kDimMs ? offMs_ / 2 : kDimMs;
    return idle >= dim ? Level::Dim : Level::Bright;
  }

  // The page to draw now, advancing every page period through `pages` pages.
  uint8_t page(uint32_t nowMs, uint8_t pages) {
    if (pages == 0) return 0;
    if (page_ >= pages) page_ = 0;
    if (nowMs - pageSince_ >= pageMs_) {
      page_ = static_cast<uint8_t>((page_ + 1) % pages);
      pageSince_ = nowMs;
    }
    return page_;
  }

 private:
  bool awake_ = false;
  uint32_t lastWake_ = 0, pageSince_ = 0;
  uint32_t pageMs_ = kPageMs;
  uint32_t offMs_ = kOffMs;
  uint8_t page_ = 0;
};

}  // namespace mcu
}  // namespace gw
