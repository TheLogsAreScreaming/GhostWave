// ESP32 settings store (NVS). The nRF52 one is settings_nrf52.cpp.
#include "settings.h"

#include "app_state.h"

#if defined(ARDUINO_ARCH_ESP32)

#include <Arduino.h>
#include <Preferences.h>
#include <bootloader_random.h>
#include <esp_mac.h>
#include <esp_random.h>

#include <cstring>
#include <map>
#include <vector>

#include "board.h"
#include "ghostwave/packet.h"

namespace gw {
namespace mcu {

namespace {

constexpr const char* kNs = "gw";

// Blob layout for "peers": count records of 4-byte LE id + 32-byte key.
constexpr size_t kPeerRecord = 4 + kKeySize;

class Nvs {
 public:
  explicit Nvs(bool readOnly) { ok_ = prefs_.begin(kNs, readOnly); }
  ~Nvs() {
    if (ok_) prefs_.end();
  }
  Nvs(const Nvs&) = delete;
  Nvs& operator=(const Nvs&) = delete;
  bool ok() const { return ok_; }
  Preferences* operator->() { return &prefs_; }

 private:
  Preferences prefs_;
  bool ok_;
};

bool getKey(Nvs& nvs, const char* name, Key32& out) {
  return nvs->getBytesLength(name) == out.size() && nvs->getBytes(name, out.data(), out.size()) == out.size();
}

bool savePeers(const Settings& s) {
  uint8_t blob[kMaxStoredPeers * kPeerRecord];
  for (size_t i = 0; i < s.peerCount; ++i) {
    uint8_t* r = blob + i * kPeerRecord;
    uint32_t id = s.peers[i].id;
    for (int b = 0; b < 4; ++b) r[b] = static_cast<uint8_t>(id >> (8 * b));
    std::memcpy(r + 4, s.peers[i].pub.data(), kKeySize);
  }
  Nvs nvs(false);
  return nvs.ok() && nvs->putBytes("peers", blob, s.peerCount * kPeerRecord) == s.peerCount * kPeerRecord;
}

bool g_fresh = false;

// An app-state record (app_state.h encoding) in one NVS blob.
template <typename T, typename Decode>
bool loadBlob(const char* key, T& out, Decode decode) {
  Nvs nvs(true);
  if (!nvs.ok()) return false;
  size_t len = nvs->getBytesLength(key);
  if (!len) return false;
  std::vector<uint8_t> b(len);
  if (nvs->getBytes(key, b.data(), len) != len) return false;
  const bool ok = decode(b, out);
  gw::wipe(b.data(), b.size());
  return ok;
}

bool saveBlob(const char* key, std::vector<uint8_t> b) {
  if (b.empty()) return false;
  Nvs nvs(false);
  const bool ok = nvs.ok() && nvs->putBytes(key, b.data(), b.size()) == b.size();   // NVS writes are atomic
  gw::wipe(b.data(), b.size());
  return ok;
}

}  // namespace

bool settingsWereFresh() { return g_fresh; }

void secureRandom(uint8_t* out, size_t n) {
  // Without Wi-Fi/BT running the RNG needs this source enabled to be a TRNG.
  // It borrows the SAR ADC, so it must run before anything else uses the ADC.
  bootloader_random_enable();
  esp_fill_random(out, n);
  bootloader_random_disable();
}

bool loadSettings(Settings& s) {
  Nvs nvs(false);
  if (!nvs.ok()) return false;

  if (getKey(nvs, "idkey", s.secret)) {
    s.edIdentity = nvs->getBool("edid", false);
    s.nodeId = nvs->getUInt("id", 0);
    if (s.nodeId == 0 || s.nodeId == kBroadcast) {   // a board from before Ed25519
      uint8_t mac[6];
      esp_efuse_mac_get_default(mac);
      s.nodeId = crc32c(mac, sizeof mac);
      if (s.nodeId == 0 || s.nodeId == kBroadcast) s.nodeId = 0x6E57A11u;
      if (!nvs->putUInt("id", s.nodeId)) return false;
    }
  } else {
    newEdIdentity(s);
    // The key goes last: a power cut before it just makes a new identity next boot.
    if (!nvs->putBool("edid", true) || !nvs->putBool("txoff", true) || !nvs->putUInt("id", s.nodeId)) return false;
    if (nvs->putBytes("idkey", s.secret.data(), s.secret.size()) != s.secret.size()) return false;
    g_fresh = true;
    Serial.println("generated new identity key");
  }
  {
    const std::string name = nvs->getString("name", "").c_str();
    if (s.edIdentity && validNodeName(name)) s.name = name;
  }
  s.havePsk = getKey(nvs, "psk", s.psk);

  s.fixedPos = nvs->getBool("fixpos", false);
  s.lat = nvs->getDouble("lat", 0);
  s.lon = nvs->getDouble("lon", 0);
  s.outputDbm = nvs->getChar("power", kDefaultOutputDbm);
  s.freqMHz = nvs->getFloat("freq", 914.875f);   // clear of Meshtastic/MeshCore US defaults
  s.region = static_cast<Region>(nvs->getUChar("region", 0));
  if (static_cast<size_t>(s.region) >= kRegionCount) s.region = Region::Us915;
  s.responder = nvs->getBool("responder", false);
  s.requireEnc = nvs->getBool("reqenc", false);
  s.txOn = !nvs->getBool("txoff", false);   // absent on boards from before the gate
  s.bleOn = !nvs->getBool("bleoff", false);

  s.peerCount = 0;
  size_t len = nvs->getBytesLength("peers");
  if (len && len % kPeerRecord == 0 && len <= kMaxStoredPeers * kPeerRecord) {
    uint8_t blob[kMaxStoredPeers * kPeerRecord];
    if (nvs->getBytes("peers", blob, len) != len) return false;
    for (size_t off = 0; off < len; off += kPeerRecord) {
      PeerKey& p = s.peers[s.peerCount++];
      p.id = blob[off] | blob[off + 1] << 8 | blob[off + 2] << 16 | static_cast<uint32_t>(blob[off + 3]) << 24;
      std::memcpy(p.pub.data(), blob + off + 4, kKeySize);
      if (p.id == 0 || p.id == kBroadcast) return false;
      for (size_t j = 0; j + 1 < s.peerCount; ++j)
        if (s.peers[j].id == p.id) return false;
    }
  } else if (len) {
    return false;  // malformed peer trust store
  }
  return true;
}

bool saveFixedPos(const Settings& s) {
  Nvs nvs(false);
  return nvs.ok() && nvs->putBool("fixpos", s.fixedPos) && nvs->putDouble("lat", s.lat) &&
         nvs->putDouble("lon", s.lon);
}

bool savePsk(const Settings& s) {
  Nvs nvs(false);
  if (!nvs.ok()) return false;
  if (!s.havePsk) return nvs->remove("psk") || !nvs->isKey("psk");
  return nvs->putBytes("psk", s.psk.data(), s.psk.size()) == s.psk.size();
}

bool saveRadio(const Settings& s) {
  Nvs nvs(false);
  return nvs.ok() && nvs->putChar("power", s.outputDbm) && nvs->putFloat("freq", s.freqMHz) &&
         nvs->putUChar("region", static_cast<uint8_t>(s.region));
}

bool saveFlags(const Settings& s) {
  Nvs nvs(false);
  return nvs.ok() && nvs->putBool("responder", s.responder) && nvs->putBool("reqenc", s.requireEnc) &&
         nvs->putBool("txoff", !s.txOn);
}

bool saveBle(const Settings& s) {
  Nvs nvs(false);
  return nvs.ok() && nvs->putBool("bleoff", !s.bleOn);
}

bool blePinValid(const char* pin) {
  if (!pin) return false;
  for (int i = 0; i < 6; ++i)
    if (pin[i] < '0' || pin[i] > '9') return false;
  return pin[6] == 0;
}

void loadBlePin(char out[7]) {
  std::strcpy(out, kDefaultBlePin);
  Nvs nvs(true);
  if (!nvs.ok()) return;
  char b[8] = {0};
  if (nvs->getString("blepin", b, sizeof b) == 7 && blePinValid(b)) std::strcpy(out, b);   // length includes the NUL
}

bool saveBlePin(const char* pin) {
  if (!blePinValid(pin)) return false;
  Nvs nvs(false);
  return nvs.ok() && nvs->putString("blepin", pin) == 6;
}

bool loadChannels(std::vector<SavedChannel>& out) { return loadBlob("channels", out, app_state::decodeChannels); }
bool saveChannels(const std::vector<SavedChannel>& in) { return saveBlob("channels", app_state::encodeChannels(in)); }
bool loadEdKeys(std::map<uint32_t, AppKey>& out) { return loadBlob("edkeys", out, app_state::decodeEdKeys); }
bool saveEdKeys(const std::map<uint32_t, AppKey>& in) { return saveBlob("edkeys", app_state::encodeEdKeys(in)); }

bool saveName(const Settings& s) {
  Nvs nvs(false);
  if (!nvs.ok()) return false;
  if (s.name.empty()) return nvs->remove("name") || !nvs->isKey("name");
  return nvs->putString("name", s.name.c_str()) == s.name.size();
}

bool loadIdentitySeed(Key32& out) {
  Nvs nvs(true);
  return nvs.ok() && getKey(nvs, "idkey", out);
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
  if (savePeers(s)) return true;
  s.peers[i] = previous;
  if (adding) --s.peerCount;
  return false;
}

}  // namespace mcu
}  // namespace gw

#endif  // ARDUINO_ARCH_ESP32
