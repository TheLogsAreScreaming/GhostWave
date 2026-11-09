// Range test: numbered pings on a timer, counting which ones are delivered.
// Pure logic with no Arduino calls, so the host tests check it
// (tests/test_rangetest.cpp). main.cpp does the sending and printing.
#pragma once

#include <array>
#include <cstdint>

namespace gw {
namespace mcu {

class RangeTest {
 public:
  static constexpr uint32_t kDefaultIntervalMs = 30000;
  static constexpr uint32_t kMinIntervalMs = 15000;   // keeps airtime reasonable
  static constexpr uint32_t kMaxPings = 240;          // stops by itself: two hours at the default
  static constexpr size_t kTracked = 16;              // pings whose receipts can still be matched

  void start(uint32_t dst, uint32_t intervalMs, uint64_t nowMs) {
    *this = RangeTest();
    active_ = true;
    dst_ = dst;
    intervalMs_ = intervalMs < kMinIntervalMs ? kMinIntervalMs : intervalMs;
    nextAt_ = nowMs;
  }

  void stop() { active_ = false; }
  bool active() const { return active_; }
  uint32_t dst() const { return dst_; }
  uint32_t sent() const { return sent_; }
  uint32_t delivered() const { return delivered_; }
  uint32_t intervalMs() const { return intervalMs_; }

  bool due(uint64_t nowMs) const { return active_ && nowMs >= nextAt_; }

  // The sequence number the next ping should carry.
  uint32_t nextSeq() const { return sent_ + 1; }

  // After the ping was queued (msgId non-zero) or refused (0: it does not count).
  void onSent(uint32_t msgId, uint64_t nowMs) {
    nextAt_ = nowMs + intervalMs_;
    if (!msgId) return;
    ++sent_;
    ids_[sent_ % kTracked] = {msgId, sent_};
    if (sent_ >= kMaxPings) active_ = false;
  }

  // Returns the ping's sequence number if `msgId` is an outstanding ping, else 0.
  uint32_t onDelivered(uint32_t msgId) {
    for (auto& e : ids_) {
      if (e.id == msgId && e.seq) {
        const uint32_t seq = e.seq;
        e = {};
        ++delivered_;
        return seq;
      }
    }
    return 0;
  }

 private:
  struct Entry {
    uint32_t id = 0, seq = 0;
  };
  bool active_ = false;
  uint32_t dst_ = 0, intervalMs_ = kDefaultIntervalMs, sent_ = 0, delivered_ = 0;
  uint64_t nextAt_ = 0;
  std::array<Entry, kTracked> ids_{};
};

// Parses a received "RT <n>" ping. Returns n, or 0 if this is not one.
inline uint32_t rangePingSeq(const uint8_t* p, size_t len) {
  if (len < 4 || p[0] != 'R' || p[1] != 'T' || p[2] != ' ') return 0;
  uint32_t n = 0;
  size_t i = 3;
  for (; i < len && p[i] >= '0' && p[i] <= '9'; ++i) {
    if (n > 100000) return 0;
    n = n * 10 + (p[i] - '0');
  }
  return i == len ? n : 0;   // nothing may follow, so ordinary text is not mistaken for a ping
}

}  // namespace mcu
}  // namespace gw
