// nRF52 settings store: one versioned, CRC-checked file in internal flash
// (Adafruit InternalFS, LittleFS on the 28 KB filesystem region below the
// bootloader). Every save rewrites the whole record to a temporary file and
// renames it over the old one, which LittleFS does atomically, so a power cut
// mid-save leaves either the old or the new settings, never a mix. Bluefruit
// keeps its BLE bonds in the same filesystem (/adafruit/bond_prph).
#include "settings.h"

#if defined(ARDUINO_ARCH_NRF52)

#include <Adafruit_LittleFS.h>
#include <Arduino.h>
#include <InternalFileSystem.h>
#include <nrf_sdm.h>
#include <nrf_soc.h>

#include <cstring>
#include <vector>

#include "app_state.h"
#include "board.h"
#include "ghostwave/packet.h"
#include "ghostwave/util.h"

using namespace Adafruit_LittleFS_Namespace;

namespace gw {
namespace mcu {

namespace {

constexpr const char* kPath = "/gw/settings";
constexpr const char* kTmpPath = "/gw/settings.tmp";
constexpr const char* kChannelsPath = "/gw/channels";
constexpr const char* kChannelsTmp = "/gw/channels.tmp";
constexpr const char* kEdKeysPath = "/gw/edkeys";
constexpr const char* kEdKeysTmp = "/gw/edkeys.tmp";
constexpr uint8_t kMagic[4] = {'G', 'W', 'S', '1'};
constexpr uint8_t kVersion = 1;
// Optional fields after the peers: tag, length, value. Unknown tags are
// skipped. A field at its default is left out.
constexpr uint8_t kTagRegion = 1;
constexpr uint8_t kTagEdIdentity = 2;   // no value: the secret is an Ed25519 seed
constexpr uint8_t kTagName = 3;
constexpr uint8_t kTagTxOff = 4;        // no value; absent on boards from before the gate

bool g_fsOk = false;
// The identity secret as loaded. main.cpp wipes Settings::secret once the
// router has its own copy, and every save rewrites the whole record, so
// saves take the secret from here.
Key32 g_secret{};

class Writer {
 public:
  void u8(uint8_t v) { b_.push_back(v); }
  void u32(uint32_t v) {
    for (int i = 0; i < 4; ++i) b_.push_back(static_cast<uint8_t>(v >> (8 * i)));
  }
  void raw(const void* p, size_t n) {
    auto* c = static_cast<const uint8_t*>(p);
    b_.insert(b_.end(), c, c + n);
  }
  void f64(double v) { raw(&v, sizeof v); }   // little-endian IEEE on Cortex-M
  void f32(float v) { raw(&v, sizeof v); }
  std::vector<uint8_t>& bytes() { return b_; }

 private:
  std::vector<uint8_t> b_;
};

class Reader {
 public:
  Reader(const uint8_t* p, size_t n) : p_(p), n_(n) {}
  bool ok() const { return ok_; }
  uint8_t u8() { return take(1) ? p_[off_ - 1] : 0; }
  uint32_t u32() {
    if (!take(4)) return 0;
    const uint8_t* q = p_ + off_ - 4;
    return q[0] | q[1] << 8 | q[2] << 16 | static_cast<uint32_t>(q[3]) << 24;
  }
  void raw(void* out, size_t n) {
    if (take(n)) std::memcpy(out, p_ + off_ - n, n);
  }
  double f64() {
    double v = 0;
    raw(&v, sizeof v);
    return v;
  }
  float f32() {
    float v = 0;
    raw(&v, sizeof v);
    return v;
  }
  size_t left() const { return n_ - off_; }

 private:
  bool take(size_t n) {
    if (!ok_ || n_ - off_ < n) return ok_ = false;
    off_ += n;
    return true;
  }
  const uint8_t* p_;
  size_t n_, off_ = 0;
  bool ok_ = true;
};

// Settings::secret is ignored: the record always carries g_secret.
std::vector<uint8_t> encode(const Settings& s) {
  Writer w;
  w.raw(kMagic, sizeof kMagic);
  w.u8(kVersion);
  w.u32(s.nodeId);
  w.raw(g_secret.data(), g_secret.size());
  w.u8(s.havePsk);
  w.raw(s.psk.data(), s.psk.size());
  w.u8(s.fixedPos);
  w.f64(s.lat);
  w.f64(s.lon);
  w.u8(static_cast<uint8_t>(s.outputDbm));
  w.f32(s.freqMHz);
  w.u8(s.responder);
  w.u8(s.requireEnc);
  w.u8(s.bleOn);
  w.u8(static_cast<uint8_t>(s.peerCount));
  for (size_t i = 0; i < s.peerCount; ++i) {
    w.u32(s.peers[i].id);
    w.raw(s.peers[i].pub.data(), s.peers[i].pub.size());
  }
  if (s.region != Region::Us915) {
    w.u8(kTagRegion);
    w.u8(1);
    w.u8(static_cast<uint8_t>(s.region));
  }
  if (s.edIdentity) {
    w.u8(kTagEdIdentity);
    w.u8(0);
  }
  if (!s.name.empty()) {
    w.u8(kTagName);
    w.u8(static_cast<uint8_t>(s.name.size()));
    w.raw(s.name.data(), s.name.size());
  }
  if (!s.txOn) {
    w.u8(kTagTxOff);
    w.u8(0);
  }
  w.u32(crc32c(w.bytes().data(), w.bytes().size()));
  return std::move(w.bytes());
}

bool decode(const std::vector<uint8_t>& b, Settings& s) {
  if (b.size() < sizeof kMagic + 1 + 4 || std::memcmp(b.data(), kMagic, sizeof kMagic) != 0) return false;
  const size_t body = b.size() - 4;
  Reader crc(b.data() + body, 4);
  if (crc.u32() != crc32c(b.data(), body)) return false;
  Reader r(b.data() + sizeof kMagic, body - sizeof kMagic);
  if (r.u8() != kVersion) return false;
  Settings t;
  t.nodeId = r.u32();
  r.raw(t.secret.data(), t.secret.size());
  t.havePsk = r.u8();
  r.raw(t.psk.data(), t.psk.size());
  t.fixedPos = r.u8();
  t.lat = r.f64();
  t.lon = r.f64();
  t.outputDbm = static_cast<int8_t>(r.u8());
  t.freqMHz = r.f32();
  t.responder = r.u8();
  t.requireEnc = r.u8();
  t.bleOn = r.u8();
  size_t n = r.u8();
  if (!r.ok() || n > kMaxStoredPeers) return false;
  for (size_t i = 0; i < n; ++i) {
    PeerKey& p = t.peers[i];
    p.id = r.u32();
    r.raw(p.pub.data(), p.pub.size());
    if (p.id == 0 || p.id == kBroadcast) return false;
    for (size_t j = 0; j < i; ++j)
      if (t.peers[j].id == p.id) return false;
  }
  t.peerCount = n;
  while (r.ok() && r.left() != 0) {
    const uint8_t tag = r.u8();
    const size_t len = r.u8();
    if (!r.ok() || r.left() < len) return false;
    uint8_t value[255];
    r.raw(value, len);
    if (tag == kTagRegion && len == 1 && value[0] < kRegionCount) t.region = static_cast<Region>(value[0]);
    if (tag == kTagEdIdentity) t.edIdentity = true;
    if (tag == kTagTxOff) t.txOn = false;
    if (tag == kTagName) {
      std::string name(reinterpret_cast<const char*>(value), len);
      if (validNodeName(name)) t.name = name;
    }
  }
  if (!r.ok()) return false;
  s = t;
  gw::wipe(t.secret.data(), t.secret.size());
  gw::wipe(t.psk.data(), t.psk.size());
  return true;
}

bool readFile(const char* path, std::vector<uint8_t>& out) {
  File f = InternalFS.open(path, FILE_O_READ);
  if (!f) return false;
  size_t n = f.size();
  if (n == 0 || n > 4096) {
    f.close();
    return false;
  }
  out.resize(n);
  bool ok = f.read(out.data(), n) == static_cast<int>(n);
  f.close();
  return ok;
}

// Temp file, then a rename, which LittleFS does atomically. Wipes `b`.
bool writeAtomic(const char* path, const char* tmp, std::vector<uint8_t>& b) {
  if (!g_fsOk) {
    gw::wipe(b.data(), b.size());
    return false;
  }
  InternalFS.remove(tmp);   // FILE_O_WRITE appends to an existing file
  File f = InternalFS.open(tmp, FILE_O_WRITE);
  bool ok = false;
  if (f) {
    ok = f.write(b.data(), b.size()) == b.size();
    f.close();
  }
  gw::wipe(b.data(), b.size());
  return ok && InternalFS.rename(tmp, path);
}

bool saveAll(const Settings& s) {
  std::vector<uint8_t> b = encode(s);
  return writeAtomic(kPath, kTmpPath, b);
}

// The file, or the temp file if a crash came between writing it and the
// rename. A file that exists but does not decode is reported.
template <typename T, typename Decode>
bool loadRecord(const char* path, const char* tmp, T& out, Decode decode) {
  if (!g_fsOk) return false;
  std::vector<uint8_t> b;
  const bool ok = (readFile(path, b) && decode(b, out)) || (readFile(tmp, b) && decode(b, out));
  gw::wipe(b.data(), b.size());
  if (!ok && InternalFS.exists(path)) Serial.printf("%s unreadable: ignored\n", path);
  return ok;
}

uint32_t deviceId() {
  uint8_t id[8];
  for (int w = 0; w < 2; ++w)
    for (int i = 0; i < 4; ++i) id[4 * w + i] = static_cast<uint8_t>(NRF_FICR->DEVICEID[w] >> (8 * i));
  uint32_t v = crc32c(id, sizeof id);
  return v == 0 || v == kBroadcast ? 0x6E57A11u : v;
}

}  // namespace

void secureRandom(uint8_t* out, size_t n) {
  uint8_t en = 0;
  sd_softdevice_is_enabled(&en);
  if (en) {
    // the SoftDevice owns the RNG: take bytes from its pool as they come
    while (n) {
      uint8_t avail = 0;
      sd_rand_application_bytes_available_get(&avail);
      size_t take = avail < n ? avail : n;
      if (take && sd_rand_application_vector_get(out, static_cast<uint8_t>(take)) == NRF_SUCCESS) {
        out += take;
        n -= take;
      } else {
        delay(1);
      }
    }
    return;
  }
  NRF_RNG->CONFIG = RNG_CONFIG_DERCEN_Enabled;   // bias correction
  NRF_RNG->TASKS_START = 1;
  for (size_t i = 0; i < n; ++i) {
    NRF_RNG->EVENTS_VALRDY = 0;
    while (!NRF_RNG->EVENTS_VALRDY) {
    }
    out[i] = static_cast<uint8_t>(NRF_RNG->VALUE);
  }
  NRF_RNG->TASKS_STOP = 1;
}

bool loadSettings(Settings& s) {
  g_fsOk = InternalFS.begin();
  if (!g_fsOk) {
    s.nodeId = deviceId();
    secureRandom(s.secret.data(), s.secret.size());
    s.outputDbm = kDefaultOutputDbm;
    s.freqMHz = 914.875f;
    return false;
  }
  InternalFS.mkdir("/gw");
  std::vector<uint8_t> b;
  bool loaded = (readFile(kPath, b) && decode(b, s)) ||
                // a crash between writing the temp file and the rename
                (readFile(kTmpPath, b) && decode(b, s));
  gw::wipe(b.data(), b.size());
  if (loaded) {
    g_secret = s.secret;
    return true;
  }
  if (InternalFS.exists(kPath)) Serial.println("settings file unreadable: starting fresh (new identity key)");
  s = Settings();
  newEdIdentity(s);
  s.txOn = false;
  s.outputDbm = kDefaultOutputDbm;
  s.freqMHz = 914.875f;   // clear of Meshtastic/MeshCore US defaults
  g_secret = s.secret;
  Serial.println("generated new identity key");
  return saveAll(s);
}

bool saveFixedPos(const Settings& s) { return saveAll(s); }
bool savePsk(const Settings& s) { return saveAll(s); }
bool saveRadio(const Settings& s) { return saveAll(s); }
bool saveFlags(const Settings& s) { return saveAll(s); }
bool saveBle(const Settings& s) { return saveAll(s); }
bool saveName(const Settings& s) { return saveAll(s); }

bool loadIdentitySeed(Key32& out) {
  out = g_secret;
  return true;
}

bool savePeer(Settings& s, uint32_t id, const Key32& pub) {
  if (id == 0 || id == kBroadcast) return false;
  size_t i = 0;
  while (i < s.peerCount && s.peers[i].id != id) ++i;
  const bool adding = i == s.peerCount;
  if (adding && s.peerCount == kMaxStoredPeers) return false;
  const PeerKey previous = s.peers[i];
  if (adding) ++s.peerCount;
  s.peers[i] = {id, pub};
  if (saveAll(s)) return true;
  s.peers[i] = previous;
  if (adding) --s.peerCount;
  return false;
}

bool loadChannels(std::vector<SavedChannel>& out) {
  return loadRecord(kChannelsPath, kChannelsTmp, out, app_state::decodeChannels);
}

bool saveChannels(const std::vector<SavedChannel>& in) {
  std::vector<uint8_t> b = app_state::encodeChannels(in);
  return !b.empty() && writeAtomic(kChannelsPath, kChannelsTmp, b);
}

bool loadEdKeys(std::map<uint32_t, AppKey>& out) {
  return loadRecord(kEdKeysPath, kEdKeysTmp, out, app_state::decodeEdKeys);
}

bool saveEdKeys(const std::map<uint32_t, AppKey>& in) {
  std::vector<uint8_t> b = app_state::encodeEdKeys(in);
  return !b.empty() && writeAtomic(kEdKeysPath, kEdKeysTmp, b);
}

}  // namespace mcu
}  // namespace gw

#endif  // ARDUINO_ARCH_NRF52
