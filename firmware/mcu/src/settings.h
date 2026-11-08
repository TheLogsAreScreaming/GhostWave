// Node settings, persisted in NVS on the ESP32 (Preferences, namespace "gw",
// settings.cpp) and in a LittleFS file in internal flash on the nRF52
// (settings_nrf52.cpp).
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

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
  Key32 secret{};               // X25519 identity secret
  bool havePsk = false;
  Key32 psk{};                  // channel key
  bool fixedPos = false;        // stored position (boards without GPS, or no fix yet)
  double lat = 0, lon = 0;
  int8_t outputDbm = 0;         // at the antenna port, before the board cap
  float freqMHz = 0;
  Region region = Region::Us915;
  bool responder = false;
  bool requireEnc = false;
  bool bleOn = true;            // nRF52 only: advertise the BLE client link
  size_t peerCount = 0;
  std::array<PeerKey, kMaxStoredPeers> peers{};
};

// Loads everything; on first boot creates and saves a node ID (from the
// factory MAC / FICR device ID) and an identity key (from the hardware RNG).
// False if storage fails.
bool loadSettings(Settings& s);

bool saveFixedPos(const Settings& s);
bool savePsk(const Settings& s);
bool saveRadio(const Settings& s);   // power, frequency and region
bool saveFlags(const Settings& s);
bool saveBle(const Settings& s);
// Adds or replaces `id`'s key. False when kMaxStoredPeers are already held.
bool savePeer(Settings& s, uint32_t id, const Key32& pub);

// Hardware RNG (ESP32: with the RF-independent entropy source switched on;
// nRF52: the RNG peripheral, through the SoftDevice once it is running).
void secureRandom(uint8_t* out, size_t n);

}  // namespace mcu
}  // namespace gw
