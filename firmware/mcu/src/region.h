// Regulatory regions (DESIGN §12) and the duty-cycle cap (§6.1). Plain C++, so
// the host tests cover it. The radio enforces the cap on every frame, relays
// and SOS included: it is a legal limit, unlike the router's fair-share budget.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace gw {
namespace mcu {

enum class Region : uint8_t { Us915 = 0, Eu868 = 1 };

struct RegionInfo {
  const char* name;
  float minMHz, maxMHz;   // centre frequency of a BW125 channel inside the band
  float defaultMHz;
  uint16_t dutyPermille;  // of any hour on air; 0 = no duty-cycle rule
};

// US: DESIGN §12 leaves the rule path open; no duty-cycle rule applies here.
// EU: the 869.4-869.65 MHz sub-band, 10 %. Its 500 mW ERP is above kMaxOutputDbm.
constexpr size_t kRegionCount = 2;
constexpr RegionInfo kRegions[kRegionCount] = {
    {"us915", 902.0625f, 927.9375f, 914.875f, 0},
    {"eu868", 869.4625f, 869.5875f, 869.525f, 100},
};

inline const RegionInfo& regionInfo(Region r) {
  const size_t i = static_cast<size_t>(r);
  return kRegions[i < kRegionCount ? i : 0];
}

inline bool regionFromName(const char* name, Region& out) {
  for (size_t i = 0; i < kRegionCount; ++i) {
    if (std::strcmp(name, kRegions[i].name) == 0) {
      out = static_cast<Region>(i);
      return true;
    }
  }
  return false;
}

// Airtime used over the last hour, in one-minute buckets. 61 buckets, so a
// frame stays counted for at least a full 60 minutes. Held in RAM: a reboot
// forgets it.
class DutyWindow {
 public:
  void setPermille(uint16_t permille) { limitMs_ = uint32_t(permille) * 3600; }
  bool capped() const { return limitMs_ != 0; }
  uint32_t limitMs() const { return limitMs_; }

  uint32_t usedMs(uint64_t nowMs) const {
    const uint64_t cur = minute(nowMs);
    uint64_t sum = 0;
    for (size_t i = 0; i < kBuckets; ++i)
      if (stamp_[i] != 0 && cur - stamp_[i] < kBuckets) sum += ms_[i];
    return static_cast<uint32_t>(sum);
  }

  bool allows(uint64_t nowMs, uint32_t airMs) const {
    return !capped() || uint64_t(usedMs(nowMs)) + airMs <= limitMs_;
  }

  void record(uint64_t nowMs, uint32_t airMs) {
    const uint64_t cur = minute(nowMs);
    const size_t i = static_cast<size_t>(cur % kBuckets);
    if (stamp_[i] != cur) {
      stamp_[i] = cur;
      ms_[i] = 0;
    }
    ms_[i] += airMs;
  }

 private:
  static constexpr size_t kBuckets = 61;
  static uint64_t minute(uint64_t nowMs) { return nowMs / 60000 + 1; }   // 0 marks an unused bucket

  uint32_t limitMs_ = 0;
  std::array<uint64_t, kBuckets> stamp_{};
  std::array<uint32_t, kBuckets> ms_{};
};

}  // namespace mcu
}  // namespace gw
