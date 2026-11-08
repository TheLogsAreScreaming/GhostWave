// What the app hands an nRF52 node to keep: joined group channels and pinned
// Ed25519 contact keys. Each list is its own CRC-checked file in internal
// flash next to /gw/settings (settings_nrf52.cpp), written the same atomic way.
// The record format below is plain C++ so the host tests can cover it.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#include "ghostwave/packet.h"

namespace gw {
namespace mcu {

using AppKey = std::array<uint8_t, 32>;

struct SavedChannel {
  std::string name;
  AppKey key{};
};

namespace app_state {

constexpr size_t kMaxChannels = 8;       // gw::kMaxGroupChannels
constexpr size_t kMaxChannelName = 16;   // gw::ChannelBook::kNameMax
constexpr size_t kMaxEdKeys = 32;        // kMaxStoredPeers: a pin without a stored peer key is useless
constexpr uint8_t kChannelsMagic[4] = {'G', 'W', 'C', '1'};
constexpr uint8_t kEdKeysMagic[4] = {'G', 'W', 'E', '1'};

inline void putCrc(std::vector<uint8_t>& b) {
  const uint32_t c = crc32c(b.data(), b.size());
  for (int i = 0; i < 4; ++i) b.push_back(static_cast<uint8_t>(c >> (8 * i)));
}

// True if `b` starts with `magic`, ends in a good CRC and is long enough to
// hold the count byte. `body` is then the size without the CRC.
inline bool checkRecord(const std::vector<uint8_t>& b, const uint8_t magic[4], size_t& body) {
  if (b.size() < 4 + 1 + 4 || std::memcmp(b.data(), magic, 4) != 0) return false;
  body = b.size() - 4;
  const uint8_t* q = b.data() + body;
  const uint32_t want = q[0] | q[1] << 8 | q[2] << 16 | static_cast<uint32_t>(q[3]) << 24;
  return crc32c(b.data(), body) == want;
}

// Empty when the list is too long or a name does not fit the format.
inline std::vector<uint8_t> encodeChannels(const std::vector<SavedChannel>& in) {
  std::vector<uint8_t> b(kChannelsMagic, kChannelsMagic + 4);
  if (in.size() > kMaxChannels) return {};
  b.push_back(static_cast<uint8_t>(in.size()));
  for (const SavedChannel& c : in) {
    if (c.name.empty() || c.name.size() > kMaxChannelName) return {};
    b.push_back(static_cast<uint8_t>(c.name.size()));
    b.insert(b.end(), c.name.begin(), c.name.end());
    b.insert(b.end(), c.key.begin(), c.key.end());
  }
  putCrc(b);
  return b;
}

inline bool decodeChannels(const std::vector<uint8_t>& b, std::vector<SavedChannel>& out) {
  size_t body = 0;
  if (!checkRecord(b, kChannelsMagic, body)) return false;
  size_t off = 4;
  const size_t n = b[off++];
  if (n > kMaxChannels) return false;
  std::vector<SavedChannel> t;
  for (size_t i = 0; i < n; ++i) {
    if (off >= body) return false;
    const size_t len = b[off++];
    if (len == 0 || len > kMaxChannelName || body - off < len + 32) return false;
    SavedChannel c;
    c.name.assign(reinterpret_cast<const char*>(&b[off]), len);
    std::memcpy(c.key.data(), &b[off + len], 32);
    off += len + 32;
    t.push_back(c);
  }
  if (off != body) return false;
  out = t;
  return true;
}

// Empty when there are more than kMaxEdKeys.
inline std::vector<uint8_t> encodeEdKeys(const std::map<uint32_t, AppKey>& in) {
  if (in.size() > kMaxEdKeys) return {};
  std::vector<uint8_t> b(kEdKeysMagic, kEdKeysMagic + 4);
  b.push_back(static_cast<uint8_t>(in.size()));
  for (const auto& e : in) {
    for (int i = 0; i < 4; ++i) b.push_back(static_cast<uint8_t>(e.first >> (8 * i)));
    b.insert(b.end(), e.second.begin(), e.second.end());
  }
  putCrc(b);
  return b;
}

inline bool decodeEdKeys(const std::vector<uint8_t>& b, std::map<uint32_t, AppKey>& out) {
  size_t body = 0;
  if (!checkRecord(b, kEdKeysMagic, body)) return false;
  const size_t n = b[4];
  if (n > kMaxEdKeys || body != 5 + n * 36) return false;
  std::map<uint32_t, AppKey> t;
  for (size_t i = 0; i < n; ++i) {
    const uint8_t* q = &b[5 + i * 36];
    const uint32_t id = q[0] | q[1] << 8 | q[2] << 16 | static_cast<uint32_t>(q[3]) << 24;
    if (id == 0 || id == kBroadcast || t.count(id)) return false;
    std::memcpy(t[id].data(), q + 4, 32);
  }
  out = t;
  return true;
}

}  // namespace app_state

// Implemented for the nRF52 in settings_nrf52.cpp. Load: false if the file is
// missing or damaged (`out` is left alone). Save: false if nothing was written.
bool loadChannels(std::vector<SavedChannel>& out);
bool saveChannels(const std::vector<SavedChannel>& in);
bool loadEdKeys(std::map<uint32_t, AppKey>& out);
bool saveEdKeys(const std::map<uint32_t, AppKey>& in);

}  // namespace mcu
}  // namespace gw
