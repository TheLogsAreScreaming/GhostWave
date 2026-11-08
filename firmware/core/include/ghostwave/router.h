// GhostWave router: contention-based geographic forwarding, DTN custody store,
// spray-and-wait, airtime budget and CSMA (docs/DESIGN.md §5–6), the SOS lane
// (§8), DATA encryption (§9.1) and IDENT key exchange (§4.5).
//
// Platform-agnostic: the host supplies a RadioPort (send / CAD), an AppPort
// (delivery callbacks), a position, and calls tick() every few milliseconds.
#pragma once

#include <array>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "ghostwave/packet.h"
#include "ghostwave/util.h"

namespace gw {

class RadioPort {
 public:
  virtual ~RadioPort() = default;
  // True if a LoRa preamble/packet is on the air right now (CAD or RSSI).
  virtual bool channelBusy() = 0;
  // Transmit one frame; returns when it is on the air or failed.
  virtual bool transmit(const uint8_t* buf, size_t len) = 0;
};

// From a neighbor's beacon (DESIGN §4.4). Speed 0 = stopped or not measured.
struct Velocity {
  double speedMps = 0;
  double headingDeg = 0;   // true, clockwise from north
};

// SOS body (DESIGN §8). Position travels in the frame's src_pos.
struct SosInfo {
  uint32_t src = 0;
  uint16_t seq = 0;
  Position pos;               // valid = false if the originator had no fix
  uint8_t accuracy = 0xFF;    // 4 m steps, 0xFF unknown
  uint8_t battery = 0xFF;     // percent, 0xFF unknown
  std::string text;           // <= kSosTextMax bytes
};
constexpr size_t kSosTextMax = 60;

class AppPort {
 public:
  virtual ~AppPort() = default;
  virtual void onMessage(uint32_t src, uint32_t msgId, const std::vector<uint8_t>& payload) = 0;
  // End-to-end receipt for a message we sent.
  virtual void onDelivered(uint32_t dst, uint32_t msgId) { (void)dst, (void)msgId; }
  // A new SOS, or a newer seq of one we already hold.
  virtual void onSos(const SosInfo& sos) { (void)sos; }
  // A responder acknowledged our SOS.
  virtual void onSosAck(uint32_t responder, uint16_t seq) { (void)responder, (void)seq; }
  // A verified IDENT taught us a new peer key (trust on first use), or a known
  // peer changed its name.
  virtual void onPeerIdent(uint32_t id, const std::string& name, bool firstSeen) {
    (void)id, (void)name, (void)firstSeen;
  }
  // A correctly signed IDENT for `id` carries a different key from the one we
  // hold. Since node ID = hash(key), an honest node cannot do this: it means a
  // brute-forced ID collision (DESIGN §9.2). The old key stays in use; call
  // Router::addPeerKey(id, ed25519ToX25519(newEdPub)) to accept the new one.
  virtual void onKeyChange(uint32_t id, const uint8_t newEdPub[32], const std::string& name) {
    (void)id, (void)newEdPub, (void)name;
  }
  // A neighbor's beacon: its position, and whether it was new or had not been
  // heard for a while (client link, docs/CLIENT_PROTOCOL.md).
  virtual void onNeighbor(uint32_t id, const Position& pos, bool isNew) { (void)id, (void)pos, (void)isNew; }
  // A group channel message (DESIGN §9.3) on a channel we joined; `chanId` is
  // groupChannelId(key) as returned by Router::addGroupChannel.
  virtual void onChannelMessage(uint32_t chanId, uint32_t src, uint32_t msgId, const std::vector<uint8_t>& payload) {
    (void)chanId, (void)src, (void)msgId, (void)payload;
  }
};

// Group channels a node can join at once (DESIGN §9.3).
constexpr size_t kMaxGroupChannels = 8;

// A peer key the router holds (pinned, or learned from IDENT).
struct PeerInfo {
  uint32_t id = 0;
  std::array<uint8_t, 32> xPub{};
  std::string name;
  bool pinned = false;
};

struct Config {
  uint32_t nodeId = 0;
  Phy phy;
  double progressThresholdM = 150;
  double areaDiameterM = 2500;      // first-attempt forwarding area
  size_t areaMinNeighbors = 10;     // ...used only when this crowded
  int contentionK = 3;
  uint8_t hopLimit = 15;
  uint8_t channelHops = 3;          // group channel messages: scoped-flood radius (DESIGN §9.3)
  uint8_t sprayCopiesLog2 = 3;      // 8 copies
  size_t storeCapacity = 64;
  uint64_t storeTtlMs = 6ull * 3600 * 1000;
  double beaconMoveM = 250;
  uint32_t beaconMaxMs = 15 * 60 * 1000;
  uint32_t beaconMinMs = 60 * 1000;
  double utilTarget = 0.25;
  double budgetShare = 0.30;        // airtime fair share for originated traffic
  double budgetFloor = 0.02;
  double budgetDepthMs = 8000;
  uint64_t rngSeed = 0;
  bool requireEncryption = false;   // drop plaintext DATA addressed to us
  bool responder = false;           // auto-reply SOS_ACK to every new SOS seq
  uint64_t sosTtlMs = 24ull * 3600 * 1000;
  uint32_t sosRepeatMs = 5 * 60 * 1000;
  uint32_t sosMinGapMs = 60 * 1000;  // originate at most 1 SOS per this
  size_t sosCapacity = 16;           // distinct originators held
  uint32_t identIntervalMs = 60 * 60 * 1000;   // broadcast IDENT this often; 0 = only on request
  size_t peerCapacity = 64;          // peer keys held (pinned + learned)
  size_t seenCapacity = 0;           // duplicate-suppression entries; 0 = unbounded (MCU ports set it)
};

struct Key {
  uint8_t type;
  uint32_t src;
  uint32_t mid;
  bool operator<(const Key& o) const {
    if (type != o.type) return type < o.type;
    if (src != o.src) return src < o.src;
    return mid < o.mid;
  }
  bool operator==(const Key& o) const { return type == o.type && src == o.src && mid == o.mid; }
};

struct RouterStats {
  uint32_t tx = 0, rx = 0, rxBad = 0, delivered = 0, forwarded = 0, stored = 0;
  uint32_t rxAuthFail = 0, sosHeard = 0, sosTx = 0;
  uint32_t identTx = 0, identRx = 0, identBad = 0, keyChanges = 0;
  uint64_t airMs = 0;
};

class Router {
 public:
  Router(const Config& cfg, RadioPort& radio, AppPort& app);
  ~Router();
  Router(const Router&) = delete;
  Router& operator=(const Router&) = delete;

  void setPosition(const Position& p, uint64_t nowMs);
  // Seed the location table (contact card / QR code / manual entry).
  void addKnownPosition(uint32_t id, const Position& p, uint64_t observedMs);
  // Keys (DESIGN §9.1). DATA to a peer with a known key is sealed with the DM
  // key, else with the channel key if set, else sent with the CRC MIC only.
  // setSigningKey sets our Ed25519 identity: it derives the X25519 secret (no
  // separate setIdentityKey needed) and enables IDENT. False if the key's node
  // ID (nodeIdOf) is not Config::nodeId or the name is over kIdentNameMax bytes.
  bool setSigningKey(const uint8_t ed25519Seed[32], const std::string& name = "");
  // X25519-only identity, for nodes without an Ed25519 key: can learn peers
  // from IDENT but cannot send one. Replaces (and stops IDENT for) any signing
  // key set before; DM keys of peers already held are re-derived.
  void setIdentityKey(const uint8_t x25519Secret[32]);
  void setChannelKey(const uint8_t key[32]);
  // Pins a key the host trusts (key file, QR code). Overrides any key learned
  // from IDENT. Call after setIdentityKey / setSigningKey. False on a low-order
  // key or a table full of pinned keys.
  bool addPeerKey(uint32_t id, const uint8_t x25519Public[32]);
  bool hasPeerKey(uint32_t id) const { return peers_.count(id) != 0; }
  // Every peer key held, in node ID order. No DM keys leave the router.
  std::vector<PeerInfo> peerList() const;
  // Names a peer we hold a key for (contact card). An IDENT later overrides it.
  bool setPeerName(uint32_t id, const std::string& name);
  // Asks a neighbor for its IDENT (1 hop; the request carries our own IDENT).
  // False without a signing key.
  bool requestIdent(uint32_t id, uint64_t nowMs);

  // Queue a message; returns its msg_id, or 0 if it cannot be sealed (too big).
  uint32_t send(uint32_t dst, const std::vector<uint8_t>& payload, uint64_t nowMs);

  // Group channels (DESIGN §9.3): a pre-shared 256-bit key per channel.
  // addGroupChannel returns the channel ID (groupChannelId(key)); adding the
  // same key again returns the same ID. 0 when kMaxGroupChannels are joined.
  uint32_t addGroupChannel(const uint8_t key[32]);
  bool removeGroupChannel(uint32_t chanId);
  bool hasGroupChannel(uint32_t chanId) const;
  // Floods a message to everyone holding the channel key, cfg.channelHops
  // hops out; best effort (no store-and-forward, no receipt). Hearing a
  // neighbor relay it counts as sent; otherwise, with a neighbor around, it
  // is re-sent up to twice (~4 s, then ~8 s after going out). Returns its
  // msg_id, or 0 for an unknown channel or a payload over kChannelPayloadMax.
  uint32_t sendChannel(uint32_t chanId, const std::vector<uint8_t>& payload, uint64_t nowMs);
  // Largest channel payload: 128-byte frame - 19 header - 7 sender position - 16 tag.
  static constexpr size_t kChannelPayloadMax = 86;
  // Broadcast our IDENT soon (after a name change via setSigningKey).
  void announceIdent(uint64_t nowMs);

  // SOS lane (DESIGN §8). Sends now and re-sends every sosRepeatMs with the
  // current position and a new seq; re-sends a seq early (up to twice, ~15 s
  // and ~45 s on) while no neighbor has been heard relaying any of ours. Calling again updates the body. Returns
  // false when rate limited (sosMinGapMs since the last origination).
  bool startSos(const std::string& text, uint8_t batteryPct, uint8_t accuracy4m, uint64_t nowMs);
  // Cancels pending origination/retries. Stored SOS remains available to carriers until TTL.
  void stopSos();
  bool sosActive() const { return sosOn_; }
  // Send SOS_ACK for the SOS we hold from `sosSrc`. False if we hold none.
  bool ackSos(uint32_t sosSrc, uint64_t nowMs);
  size_t sosCount() const { return sos_.size(); }
  // True if we hold an SOS from `src`; fills its seq.
  bool hasSos(uint32_t src, uint16_t* seq = nullptr) const;

  void onReceive(const uint8_t* buf, size_t len, float rssiDbm, uint64_t nowMs);
  void tick(uint64_t nowMs);

  const RouterStats& stats() const { return stats_; }
  size_t storeSize() const { return store_.size(); }
  size_t neighborCount(uint64_t nowMs) const;
  size_t neighborTableSize() const { return nb_.size(); }
  // The velocity in a neighbor's latest beacon. False for an unknown neighbor.
  // Informational: no forwarding decision uses it yet.
  bool neighborVelocity(uint32_t id, Velocity& out) const;
  size_t seenSize() const { return seen_.size(); }
  uint32_t id() const { return cfg_.nodeId; }

 private:
  struct TxItem {
    Packet pkt;
    bool own;
    uint64_t readyAt;
    uint64_t seq;
    bool cancelled = false;
    bool sent = false;
  };
  using TxPtr = std::shared_ptr<TxItem>;
  struct LocEntry { Position pos; uint64_t obsMs; };
  struct Neighbor {
    Position pos;
    uint64_t heardMs;
    uint64_t bloomAnswered;   // its Bloom filter we last answered with an early beacon
    Velocity velocity;
  };
  struct Seen {
    uint64_t t = 0;
    int32_t custodyUp = -1;     // short id we took custody from
    uint64_t lackT = 0;
    bool acked = false;
    bool delivered = false;
    uint64_t ackSentT = 0;
    uint8_t storeAttempts = 0;
  };
  struct Pending { Packet pkt; uint64_t fireAt; uint16_t upstream; };
  struct Await {
    Packet orig;
    TxPtr item;
    int triesLeft;
    uint64_t deadline;
    Position posAtTx;
    uint16_t upstream;
    bool wide;
  };
  struct StoreEntry {
    Packet pkt;
    bool spray;
    int copies;
    std::set<uint16_t> given;
    uint64_t last;
    uint64_t created;
    uint8_t attempts;
  };
  struct UniAwait { Packet orig; TxPtr item; int triesLeft; uint64_t deadline; int copies; };
  struct SosEntry {
    Packet pkt;                 // as heard (or as sent, for our own)
    uint16_t seq;
    uint64_t heardMs;
    uint64_t relayMs;           // last time we re-flooded a seq from this originator
    TxPtr flood;                // pending scoped-flood rebroadcast
    uint8_t dups = 0;           // copies heard while that is pending
    TxPtr offer;                // pending offer to a neighbor
    struct Offered { uint64_t t; uint8_t tries; };   // last offer; re-offers since
    std::map<uint16_t, Offered> offered;             // by neighbor
  };

  static Key keyOf(const Packet& p) { return {static_cast<uint8_t>(p.type), p.src, p.msgId}; }
  uint16_t me16() const { return shortId(cfg_.nodeId); }

  TxPtr enqueue(const Packet& p, bool own, uint64_t now);
  void serviceMac(uint64_t now);
  double budgetRate(uint64_t now) const;

  void learn(uint32_t id, const Position& p, uint64_t obsMs);
  bool fresherTarget(Packet& p, uint64_t now) const;
  void geoSend(const Packet& f, uint64_t now, int tries = -1, bool wide = false);
  void scheduleForward(const Packet& f, float rssi, uint64_t now);
  void overheard(const Key& k, const Packet& f, uint64_t now);
  void implicitAck(const Key& k);
  void sendLinkAck(const Key& k, uint16_t to, uint64_t now);
  void storeMsg(const Packet& f, bool spray, int copies, uint64_t now);
  void unicast(const Packet& f, uint16_t nh, int copies, uint64_t now);
  void onBeacon(const Packet& p, uint64_t now);
  void updateVelocity(const Position& p, uint64_t now);
  void onLinkAck(const Packet& p, uint64_t now);
  void onAck(const Packet& p, uint64_t now);
  void onData(const Packet& p, float rssi, uint64_t now);
  void beaconTick(uint64_t now);
  void retryStore(uint64_t now);
  bool storeReady(const StoreEntry& e, uint64_t now) const;
  void reattempt(const Key& k, uint64_t now);
  bool closerNeighbor(const Position& tgt, uint64_t maxAgeMs, uint64_t now) const;
  void sendBeacon(uint64_t now, uint16_t to = 0, bool seek = false);
  void armSeek(uint64_t now, bool boot);
  void seekTick(uint64_t now);
  bool holding() const { return !store_.empty() || !sos_.empty(); }
  bool openData(const Packet& p, std::vector<uint8_t>& plain);
  void sendSosNow(uint64_t now);
  void onSos(const Packet& p, uint64_t now);
  void onSosAck(const Packet& p, uint64_t now);
  bool offerSos(uint32_t nbId, const uint8_t* bloom, bool known, bool probe, uint64_t now);
  void probeSos(uint16_t nb16, uint64_t at, uint64_t jitterMs);
  void sosTick(uint64_t now);
  void sosResendTick(uint64_t now);
  bool storePeer(uint32_t id, const uint8_t xPub[32], bool pinned, uint64_t now);
  void sendIdent(uint32_t dst, uint64_t now);
  void onIdent(const Packet& p, uint64_t now);
  void wantIdent(uint32_t id, uint64_t now);
  void askIdent(uint32_t id, uint64_t now);
  void identTick(uint64_t now);
  void onChannelData(const Packet& p, uint64_t now);

  Config cfg_;
  RadioPort& radio_;
  AppPort& app_;
  Rng rng_;
  RouterStats stats_;

  bool havePos_ = false;
  Position pos_;

  std::vector<TxPtr> txq_;
  uint64_t txSeq_ = 0;
  uint64_t macBackoffUntil_ = 0;
  double tokensMs_;
  uint64_t tokensT_ = 0;

  std::map<uint32_t, LocEntry> loc_;
  std::map<uint32_t, Neighbor> nb_;
  std::map<Key, Seen> seen_;
  std::map<Key, Pending> pending_;
  std::map<Key, Await> awaiting_;
  std::map<Key, StoreEntry> store_;
  std::map<std::pair<Key, uint16_t>, UniAwait> uni_;

  uint64_t nextBeaconCheck_ = 0;
  uint64_t lastBeaconT_ = 0;
  bool beaconed_ = false;
  Position lastBeaconPos_;
  bool velAnchorSet_ = false;
  Position velAnchor_;
  uint64_t velAnchorT_ = 0, velT_ = 0;
  Velocity velSpeed_;
  uint64_t heardAirMs_ = 0, heardMark_ = 0, utilT_ = 0;
  double util_ = 0;
  uint64_t beaconSoonAt_ = 0;   // early beacon so an SOS carrier sees our Bloom filter
  uint64_t seekAt_ = 0;         // next beacon-recovery retry; 0 = none (DESIGN §6.2)
  uint8_t seekTries_ = 0;       // retries this episode
  uint8_t seekTokens_ = 3;      // retries available
  uint64_t seekRefillT_ = 0;
  bool seekBoot_ = false, seekHeard_ = false;
  Position seekPos_;            // where the last check found us, to spot walking
  uint64_t identProbeAt_ = 0;   // beacon asking a peer heard only by IDENT; 0 = none
  uint32_t identProbeId_ = 0;

  bool haveIdKey_ = false, haveChanKey_ = false, haveSigKey_ = false;
  std::array<uint8_t, 32> idKey_{}, chanKey_{};
  struct Peer {
    std::array<uint8_t, 32> xPub;   // X25519, compared on every IDENT (TOFU)
    std::array<uint8_t, 32> dm;     // derived DM key
    std::string name;
    bool pinned;                    // from addPeerKey: never evicted
    uint64_t learnedMs;
  };
  std::map<uint32_t, Peer> peers_;
  std::vector<uint8_t> identBody_;  // signed once in setSigningKey
  uint64_t nextIdentAt_ = 0;        // periodic broadcast; 0 = not scheduled yet
  uint64_t identReplyAt_ = 0;       // broadcast answering a request; 0 = none
  uint64_t lastIdentT_ = 0;
  bool identSent_ = false;
  std::map<uint32_t, uint64_t> identWant_;    // neighbor -> when to ask for its IDENT
  std::map<uint32_t, uint64_t> identAsked_;   // neighbor -> last time we asked

  struct GroupChan { uint32_t id; std::array<uint8_t, 32> key; };
  std::vector<GroupChan> chans_;
  struct ChanFlood { TxPtr item; uint8_t dups; uint64_t t; };
  std::map<Key, ChanFlood> chanFlood_;   // pending relays of channel frames, for duplicate suppression
  struct ChanOwn { Packet pkt; TxPtr item; uint64_t sentAt; uint8_t resends; bool echoed; uint64_t created; };
  std::map<uint32_t, ChanOwn> chanOwn_;   // our channel frames by msg_id, until a relay is heard
  void chanResendTick(uint64_t now);

  std::map<uint32_t, SosEntry> sos_;   // by originator; newest seq only
  std::map<uint16_t, uint64_t> sosProbe_;   // neighbor we offered to -> when to ask for its beacon
  bool sosOn_ = false, sosEver_ = false;
  uint16_t sosSeq_ = 0;
  uint64_t sosLastTx_ = 0;
  bool sosEcho_ = false;        // heard a neighbor relay (or carry) one of our seqs since startSos
  uint8_t sosResends_ = 0;      // early re-sends of the current seq
  uint64_t sosResendAt_ = 0;    // 0 = none due
  TxPtr sosOwnTx_;              // our latest own SOS frame
  std::string sosText_;
  uint8_t sosBattery_ = 0xFF, sosAccuracy_ = 0xFF;
};

}  // namespace gw
