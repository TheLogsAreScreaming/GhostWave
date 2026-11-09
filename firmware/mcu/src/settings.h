// Node settings, persisted in NVS on the ESP32 (Preferences, namespace "gw",
// settings.cpp) and in a LittleFS file in internal flash on the nRF52
// (settings_nrf52.cpp).
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

#include "ghostwave/crypto.h"
#include "region.h"

namespace gw {
namespace mcu {

using Key32 = std::array<uint8_t, kKeySize>;

constexpr size_t kMaxStoredPeers = 32;

struct PeerKey {
  uint32_t id;
  Key32 pub;
};

struct Settings {
  uint32_t nodeId = 0;
  Key32 secret{};               // Ed25519 seed if edIdentity, else X25519 secret
  bool edIdentity = false;      // fresh boards: Ed25519, node ID from the key, sends IDENT
  std::string name;             // IDENT name, up to kIdentNameMax bytes; Ed25519 only
  bool havePsk = false;
  Key32 psk{};                  // channel key
  bool fixedPos = false;        // stored position (boards without GPS, or no fix yet)
  double lat = 0, lon = 0;
  int8_t outputDbm = 0;         // at the antenna port, before the board cap
  float freqMHz = 0;
  Region region = Region::Us915;
  bool responder = false;
  bool requireEnc = false;
  bool txOn = true;             // false on a fresh board until `tx on`; see txGateOpen
  bool bleOn = true;            // nRF52 only: advertise the BLE client link
  size_t peerCount = 0;
  std::array<PeerKey, kMaxStoredPeers> peers{};
};

// Loads everything; on first boot creates and saves an Ed25519 identity and the
// node ID derived from it. A board set up before Ed25519 keeps its X25519 key
// and its factory-derived node ID: replacing them would change its address.
// False if storage fails.
bool loadSettings(Settings& s);

bool saveFixedPos(const Settings& s);
bool savePsk(const Settings& s);
bool saveRadio(const Settings& s);   // power, frequency and region
bool saveFlags(const Settings& s);
bool saveBle(const Settings& s);
// The Bluetooth pairing key (nRF52 builds), 6 digits. Kept in its own file so that adding it
// did not change the settings format boards already have saved.
constexpr const char* kDefaultBlePin = "654321";
void loadBlePin(char out[7]);   // the saved key, or the default
bool saveBlePin(const char* pin);
bool blePinValid(const char* pin);
bool saveName(const Settings& s);
// Copies the stored identity secret: Settings::secret is wiped after boot.
bool loadIdentitySeed(Key32& out);
// Adds or replaces `id`'s key. False when kMaxStoredPeers are already held.
bool savePeer(Settings& s, uint32_t id, const Key32& pub);

// Hardware RNG (ESP32: with the RF-independent entropy source switched on;
// nRF52: the RNG peripheral, through the SoftDevice once it is running).
void secureRandom(uint8_t* out, size_t n);

// Fills s.secret with a new Ed25519 seed and s.nodeId with its node ID, retrying
// the rare key whose ID is reserved (DESIGN §3).
inline void newEdIdentity(Settings& s) {
  uint8_t pub[kKeySize];
  do {
    secureRandom(s.secret.data(), s.secret.size());
    ed25519Public(s.secret.data(), pub);
    s.nodeId = nodeIdOf(pub);
  } while (!nodeIdUsable(s.nodeId));
  s.edIdentity = true;
}

}  // namespace mcu
}  // namespace gw
