// Identity keys (DESIGN §3), IDENT signatures (§4.5) and key agreement for DATA
// encryption (§9.1). The AEAD itself lives in packet.h (aeadSeal / aeadOpen)
// because it is defined over the frame.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace gw {

constexpr size_t kKeySize = 32;
constexpr size_t kSigSize = 64;
constexpr size_t kIdentFixed = kKeySize + kSigSize;   // IDENT body before the name
constexpr size_t kIdentNameMax = 9;                   // fills a 128-byte frame exactly

// Public key for an X25519 secret key.
void x25519Public(const uint8_t secret[kKeySize], uint8_t pub[kKeySize]);

// Ed25519 (RFC 8032) public key for a 32-byte seed.
void ed25519Public(const uint8_t seed[kKeySize], uint8_t pub[kKeySize]);

// Converts a peer's Ed25519 identity key (DESIGN §3) to its X25519 key.
void ed25519ToX25519(const uint8_t edPub[kKeySize], uint8_t xPub[kKeySize]);

// Converts our Ed25519 seed to the matching X25519 secret: the first half of
// SHA-512(seed), as RFC 8032 derives the signing scalar. x25519Public() of the
// result equals ed25519ToX25519() of the seed's public key.
void ed25519SecretToX25519(const uint8_t seed[kKeySize], uint8_t xSecret[kKeySize]);

// Node ID for an Ed25519 public key: the first 4 bytes of SHA-512(pub), read
// little-endian like every other ID on the wire (DESIGN §3).
uint32_t nodeIdOf(const uint8_t edPub[kKeySize]);
// False for IDs a key may not own: 0, broadcast, or short ID 0 (= anycast).
bool nodeIdUsable(uint32_t id);

// Encrypted client link (docs/CLIENT_PROTOCOL.md §7): a balanced PAKE over
// X25519. The generator comes from the PIN, so neither a listener nor a fake
// node gets anything to test PIN guesses against offline.
constexpr size_t kPinNonceSize = 16, kPinProofSize = 32, kLinkTagSize = 16;
struct LinkKeys {
  uint8_t clientToNode[kKeySize], nodeToClient[kKeySize], confirm[kPinProofSize];
};
// Our share: X25519(secret, generator(pin, nonce)).
void linkShare(const std::string& pin, const uint8_t nonce[kPinNonceSize], const uint8_t secret[kKeySize],
               uint8_t share[kKeySize]);
// Keys from our secret and the peer's share. False for a low-order share.
bool linkKeys(const uint8_t secret[kKeySize], const uint8_t theirShare[kKeySize], const uint8_t nonce[kPinNonceSize],
              const uint8_t serverShare[kKeySize], const uint8_t clientShare[kKeySize], LinkKeys& out);
// ChaCha20-Poly1305, nonce = 4 zero bytes || seq (little-endian). `seq` must
// never repeat under one key. Writes n + kLinkTagSize bytes.
void linkSeal(const uint8_t key[kKeySize], uint64_t seq, const uint8_t* plain, size_t n, uint8_t* out);
// Opens `n` bytes from linkSeal (tag included) into `plain` (n - tag bytes).
bool linkOpen(const uint8_t key[kKeySize], uint64_t seq, const uint8_t* sealed, size_t n, uint8_t* plain);
// Constant-time comparison of two proofs.
bool pinProofEqual(const uint8_t a[kPinProofSize], const uint8_t b[kPinProofSize]);

// Group channel ID (DESIGN §9.3): the first 4 bytes of
// SHA-512("ghostwave-chan-v1" || key), little-endian, never 0. Lets the host
// tell channels apart without handling keys; it never goes on the air.
uint32_t groupChannelId(const uint8_t key[kKeySize]);

// Truncated keyed BLAKE2b over a beacon's fields, under the channel key (DESIGN §9.1).
constexpr size_t kBeaconMacSize = 4;
void beaconMac(const uint8_t key[kKeySize], const uint8_t* msg, size_t len, uint8_t out[kBeaconMacSize]);

// IDENT body (DESIGN §4.5): pub (32) || Ed25519 signature (64) || name (0..9).
// The signature covers "ghostwave-ident-v1" || pub || name. False if the name
// is too long.
bool identBody(const uint8_t seed[kKeySize], const std::string& name, std::vector<uint8_t>& out);
// Checks an IDENT body sent by `src`: length, src == nodeIdOf(pub), signature.
// On success fills the sender's Ed25519 public key and name.
bool identCheck(const std::vector<uint8_t>& body, uint32_t src, uint8_t edPub[kKeySize], std::string& name);

// DM key between us and a peer: BLAKE2b-256(X25519(mySecret, theirPub) ||
// min(pubs) || max(pubs) || "ghostwave-dm-v1"). Both sides get the same key.
// Returns false for a low-order peer key (all-zero shared secret).
bool dmKey(const uint8_t mySecret[kKeySize], const uint8_t theirPub[kKeySize], uint8_t out[kKeySize]);

// Overwrites secret material.
void wipe(void* p, size_t n);

}  // namespace gw
