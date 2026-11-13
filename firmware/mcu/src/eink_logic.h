// E-ink screen rules (T-Echo): which panel pixel shows which pixel of the
// 128x64 page, and when the panel may refresh. Pure logic with no Arduino calls,
// so the host tests check it (tests/test_eink_logic.cpp).
//
// An e-ink panel keeps its picture without power but wears with every refresh,
// and a refresh takes the panel ~0.3 s (partial) to ~2 s (full). So the panel
// only refreshes when the picture changed, routine changes (counters, page
// turns) wait at least kRoutineGapMs, and a full refresh clears the ghosting
// that partial refreshes leave behind every kMaxPartials partials or kFullEveryMs.
#pragma once

#include <cstdint>

namespace gw {
namespace mcu {
namespace eink {

// The 128x64 page is drawn 1.5x (192x96), centred on the square panel.
constexpr int kSrcW = 128, kSrcH = 64;
constexpr int kScaledW = kSrcW * 3 / 2, kScaledH = kSrcH * 3 / 2;

// Whether panel pixel (px, py) is ink. `src` is a one-bit, MSB-first, row-major
// 128x64 buffer (Adafruit GFXcanvas1); `rotation` is Adafruit_GFX's 0-3, the
// way the panel is mounted in the case. Outside the page is paper.
inline bool inkAt(const uint8_t* src, int panelW, int panelH, int rotation, int px, int py) {
  int lx, ly;   // the pixel in the upright picture
  int lw = panelW, lh = panelH;
  switch (rotation & 3) {
    case 1: lx = py; ly = panelW - 1 - px; lw = panelH; lh = panelW; break;
    case 2: lx = panelW - 1 - px; ly = panelH - 1 - py; break;
    case 3: lx = panelH - 1 - py; ly = px; lw = panelH; lh = panelW; break;
    default: lx = px; ly = py; break;
  }
  const int dx = lx - (lw - kScaledW) / 2;
  const int dy = ly - (lh - kScaledH) / 2;
  if (dx < 0 || dy < 0 || dx >= kScaledW || dy >= kScaledH) return false;
  const int sx = dx * 2 / 3, sy = dy * 2 / 3;
  return (src[sy * (kSrcW / 8) + sx / 8] & (0x80 >> (sx & 7))) != 0;
}

enum class Refresh : uint8_t { None, Partial, Full };

class RefreshPolicy {
 public:
  static constexpr uint32_t kRoutineGapMs = 20000;   // routine changes: one refresh per 20 s at most
  static constexpr uint32_t kUrgentGapMs = 1000;     // events (message, passkey, SOS): within a second
  static constexpr uint8_t kMaxPartials = 30;        // then a full refresh clears the ghosting
  static constexpr uint32_t kFullEveryMs = 3600000;  // and at least once an hour while changing

  // What to do with a new picture. `changed`: it differs from what the panel
  // shows. `urgent`: something the reader must see now. Call done() once the
  // chosen refresh has been started.
  Refresh decide(uint32_t nowMs, bool changed, bool urgent) const {
    if (!changed && !forceFull_) return Refresh::None;
    if (!started_) return Refresh::Full;   // first picture: a clean panel
    const uint32_t since = nowMs - lastMs_;
    if (since < (urgent || forceFull_ ? kUrgentGapMs : kRoutineGapMs)) return Refresh::None;
    if (forceFull_ || partials_ >= kMaxPartials || nowMs - lastFullMs_ >= kFullEveryMs) return Refresh::Full;
    return Refresh::Partial;
  }

  // The next refresh is a full one, even of an unchanged picture (the screen
  // going to sleep or waking up), as soon as kUrgentGapMs allows.
  void forceFull() { forceFull_ = true; }

  void done(Refresh r, uint32_t nowMs) {
    if (r == Refresh::None) return;
    started_ = true;
    lastMs_ = nowMs;
    if (r == Refresh::Full) {
      partials_ = 0;
      lastFullMs_ = nowMs;
      forceFull_ = false;
    } else if (partials_ < 255) {
      ++partials_;
    }
  }

  uint8_t partials() const { return partials_; }

 private:
  bool started_ = false, forceFull_ = false;
  uint32_t lastMs_ = 0, lastFullMs_ = 0;
  uint8_t partials_ = 0;
};

}  // namespace eink
}  // namespace mcu
}  // namespace gw
