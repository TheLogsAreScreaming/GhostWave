// Test-only beacon timing overrides for ghostwaved (--beacon-min-s,
// --beacon-max-s). Header-only so the host tests can check the parsing.
//
// A stationary node beacons every Config::beaconMaxMs (15 min); that is right
// on the air but slow for interactive testing on the virtual mesh, where a
// lost startup beacon leaves a node without neighbors for up to 15 minutes.
// vmesh_lan.sh lowers it. Defaults are unchanged when the flags are absent.
#pragma once

#include <cstdint>
#include <cstdlib>
#include <string>

#include "ghostwave/router.h"

namespace gw {

// Longest accepted override: one day.
constexpr uint32_t kBeaconOverrideMaxS = 24 * 3600;

// Parses a whole number of seconds in 1..kBeaconOverrideMaxS. False otherwise
// (empty, signs, fractions, trailing junk, zero, too large).
inline bool parseBeaconSeconds(const char* s, uint32_t& out) {
  if (s == nullptr || *s < '0' || *s > '9') return false;
  char* end = nullptr;
  unsigned long v = std::strtoul(s, &end, 10);
  if (*end != '\0' || v == 0 || v > kBeaconOverrideMaxS) return false;
  out = static_cast<uint32_t>(v);
  return true;
}

// Applies the overrides (0 = keep the Config default). Returns an error
// message, or an empty string on success. Leaves cfg unchanged on error.
inline std::string applyBeaconTiming(uint32_t minS, uint32_t maxS, Config& cfg) {
  uint32_t minMs = minS ? minS * 1000 : cfg.beaconMinMs;
  uint32_t maxMs = maxS ? maxS * 1000 : cfg.beaconMaxMs;
  if (minMs > maxMs) {
    return "--beacon-min-s (" + std::to_string(minMs / 1000) + ") is more than --beacon-max-s (" +
           std::to_string(maxMs / 1000) + ")";
  }
  cfg.beaconMinMs = minMs;
  cfg.beaconMaxMs = maxMs;
  return {};
}

}  // namespace gw
