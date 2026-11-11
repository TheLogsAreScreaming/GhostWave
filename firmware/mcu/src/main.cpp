// GhostWave node firmware for ESP32-S3 LoRa boards (Heltec Wireless Tracker
// V2, Heltec V3) and the nRF52840 RAK4631. Same router as ghostwaved; the
// console is a line CLI on the USB serial port (115200 baud) with ghostwaved's
// commands plus a few that replace its command-line options, persisted in NVS
// (ESP32) or internal flash (nRF52). Type `help`. On the nRF52 boards an app
// also drives the node over BLE (ble_link.h), through the same request
// handler as ghostwaved's TCP client link.
#include <Arduino.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "app_state.h"
#include "board.h"
#include "ghostwave/crypto.h"
#include "ghostwave/router.h"
#include "ghostwave/util.h"
#include "platform.h"
#include "radio.h"
#include "settings.h"
#include "button_gesture.h"
#include "oled.h"
#include "rangetest.h"
#include "ui.h"
#if GW_HAS_BLE
#include "ble_link.h"
#include "ghostwave/client_handler.h"
#endif

#define GW_FW_VERSION "0.1.0-dev.8"

namespace {

using gw::mcu::Key32;

// Table sizes. storeCapacity / sosCapacity are the core defaults; the seen
// table is unbounded on the Pi and capped here. loc_ / nb_ are capped at 512
// inside the core.
#if GW_NRF52
constexpr size_t kSeenCapacity = 256;   // 256 KB of RAM, shared with the SoftDevice and BLE
#else
constexpr size_t kSeenCapacity = 512;
#endif
constexpr size_t kLocCapacity = 512;
constexpr size_t kPeerCapacity = 64;

// Worst-case router heap with every table full, for a 32-bit target. Rough by
// design: each std::map/std::set node is costed at 16 B of tree links + 8 B of
// allocator overhead, and every stored frame at a full kMaxFrame payload.
constexpr size_t kNode = 24;
constexpr size_t kPacketHeap = sizeof(gw::Packet) + gw::kMaxFrame + 8;
size_t worstCaseTableBytes(const gw::Config& c) {
  size_t store = c.storeCapacity * (kNode + 12 + kPacketHeap + 40 + 8 * kNode);  // + `given` set
  size_t seen = c.seenCapacity * (kNode + 12 + 48);
  size_t loc = kLocCapacity * (kNode + 4 + sizeof(gw::Position) + 8);
  size_t nb = loc;
  size_t sos = c.sosCapacity * (kNode + 4 + kPacketHeap + 40 + 4 * kNode);
  size_t peers = kPeerCapacity * (kNode + 4 + 32);
  // TX queue, pending forwards, custody/ack waits: bounded in practice by the
  // store and the airtime budget; allow 48 frames in flight.
  size_t inflight = 48 * (kNode + 12 + 2 * kPacketHeap + 64);
  return store + seen + loc + nb + sos + peers + inflight;
}

using gw::mcu::nowMs;

std::string toHex(const uint8_t* p, size_t n) {
  static const char* d = "0123456789abcdef";
  std::string s;
  for (size_t i = 0; i < n; ++i) {
    s += d[p[i] >> 4];
    s += d[p[i] & 15];
  }
  return s;
}

int hexNibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

bool fromHex(const std::string& s, uint8_t* out, size_t n) {
  if (s.size() != 2 * n) return false;
  for (size_t i = 0; i < n; ++i) {
    int hi = hexNibble(s[2 * i]), lo = hexNibble(s[2 * i + 1]);
    if (hi < 0 || lo < 0) return false;
    out[i] = static_cast<uint8_t>(hi << 4 | lo);
  }
  return true;
}

bool parseId(const std::string& s, uint32_t& id) {
  if (s.empty() || s.size() > 8) return false;
  char* end = nullptr;
  id = static_cast<uint32_t>(std::strtoul(s.c_str(), &end, 16));
  return *end == '\0' && id != 0;
}

bool parseDouble(const std::string& s, double& v) {
  if (s.empty()) return false;
  char* end = nullptr;
  v = std::strtod(s.c_str(), &end);
  return *end == '\0';
}

// Splits off the first space-separated word of `rest`.
std::string word(std::string& rest) {
  size_t a = rest.find_first_not_of(' ');
  if (a == std::string::npos) {
    rest.clear();
    return {};
  }
  size_t b = rest.find(' ', a);
  std::string w = rest.substr(a, b == std::string::npos ? std::string::npos : b - a);
  rest = b == std::string::npos ? std::string() : rest.substr(b + 1);
  return w;
}

#if GW_HAS_BLE
gw::client::Handler* g_link = nullptr;   // the app link, once BLE is up
#define GW_LINK(call) \
  do {                 \
    if (g_link) g_link->call; \
  } while (0)
#else
#define GW_LINK(call) \
  do {                 \
  } while (0)
#endif

#if GW_HAS_UI
#define GW_SOUND(s) gw::mcu::ui::play(gw::mcu::ui::Sound::s)
#else
#define GW_SOUND(s) \
  do {              \
  } while (0)
#endif

// Our battery for SOS bodies: percent, or 0xFF where the board cannot read it.
#if GW_HAS_OLED
uint8_t readVbatPct() {
  analogReference(AR_INTERNAL_3_0);
  analogReadResolution(12);
  uint32_t sum = 0;
  for (int i = 0; i < 8; ++i) sum += analogRead(kPinVbat);
  uint32_t mv = static_cast<uint32_t>((sum / 8) * 3000.0f / 4096.0f * kVbatScale);
  return mv < 2500 ? 0xFF : gw::mcu::batteryPercent(mv);   // no cell connected: unknown
}
#endif

uint8_t ownBattery() {
#if GW_HAS_UI
  return gw::mcu::ui::batteryPct();
#elif GW_HAS_OLED
  static uint8_t pct = 0xFF;
  static uint32_t next = 0;
  uint32_t now = millis();
  if (static_cast<int32_t>(now - next) >= 0) {
    pct = readVbatPct();
    next = now + 30000;
  }
  return pct;
#else
  return 0xFF;
#endif
}

gw::mcu::RangeTest g_rt;
float g_lastRssi = 0;         // the last frame this node heard
uint32_t g_rtRxSeq = 0;       // the last range ping received
uint32_t g_rtRxCount = 0;
uint64_t g_rtShowUntil = 0;   // keep the range page up this long after a ping

// Prints router events on the console, and passes them to the app link.
class SerialApp : public gw::AppPort {
 public:
  void onMessage(uint32_t src, uint32_t msgId, const std::vector<uint8_t>& p) override {
#if GW_HAS_OLED
    gw::mcu::oled::noteMessage(src, p.data(), p.size());
#endif
    Serial.printf("MSG from %08x id %08x: %.*s\n", src, msgId, static_cast<int>(p.size()),
                  reinterpret_cast<const char*>(p.data()));
    GW_SOUND(Message);
    if (uint32_t n = gw::mcu::rangePingSeq(p.data(), p.size())) {
      g_rtRxSeq = n;
      ++g_rtRxCount;
      g_rtShowUntil = nowMs() + 90000;
      Serial.printf("RANGE ping %u received, signal %.0f dBm (%u received so far)\n", static_cast<unsigned>(n), g_lastRssi,
                    static_cast<unsigned>(g_rtRxCount));
    }
    GW_LINK(onMessage(src, msgId, p));
  }
  void onDelivered(uint32_t dst, uint32_t msgId) override {
    Serial.printf("DELIVERED to %08x id %08x\n", dst, msgId);
    if (uint32_t n = g_rt.onDelivered(msgId))
      Serial.printf("RANGE ping %u delivered, %u of %u so far, last signal heard %.0f dBm\n", static_cast<unsigned>(n),
                    static_cast<unsigned>(g_rt.delivered()), static_cast<unsigned>(g_rt.sent()), g_lastRssi);
    GW_LINK(onDelivered(dst, msgId));
  }
  void onNeighbor(uint32_t id, const gw::Position& pos, bool isNew) override {
    GW_LINK(onNeighbor(id, pos, isNew));
  }
  void onSos(const gw::SosInfo& s) override {
    Serial.printf("SOS from %08x seq %u", s.src, s.seq);
    if (s.pos.valid) Serial.printf(" at %.6f %.6f", s.pos.lat, s.pos.lon);
    else Serial.print(" no fix");
    if (s.accuracy != 0xFF) Serial.printf(" +-%um", s.accuracy * 4u);
    if (s.battery != 0xFF) Serial.printf(" batt %u%%", s.battery);
    Serial.printf(": %s\n", s.text.c_str());
    Serial.printf("  (ack with: sosack %08x)\n", s.src);
    GW_LINK(onSos(s));
  }
  void onSosAck(uint32_t responder, uint16_t seq) override {
    Serial.printf("SOSACK from %08x for seq %u\n", responder, seq);
    GW_SOUND(SosAcked);
    GW_LINK(onSosAck(responder, seq));
  }
  void onSosCancelled(uint32_t src, uint16_t seq, bool verified) override {
    Serial.printf("SOS CANCELLED by %08x seq %u%s\n", src, seq, verified ? " (signature checked, alert cleared)"
                                                                        : " (no key to check it: alert kept)");
    GW_SOUND(SosOff);
    GW_LINK(onSosCancelled(src, seq, verified));
  }
  void onPeerIdent(uint32_t id, const std::string& name, bool firstSeen) override {
    Serial.printf("IDENT %s %08x \"%s\"\n", firstSeen ? "learned key for" : "name change from", id, name.c_str());
    GW_LINK(onPeerIdent(id, name, firstSeen));
  }
  void onKeyChange(uint32_t id, const uint8_t* edPub, const std::string& name) override {
    Serial.printf("WARNING: %08x (\"%s\") sent a different signed key; keeping the old one\n", id, name.c_str());
    GW_LINK(onKeyChange(id, edPub, name));
  }
  void onChannelMessage(uint32_t chanId, uint32_t src, uint32_t msgId, const std::vector<uint8_t>& p) override {
    Serial.printf("CHAN %08x from %08x id %08x: %.*s\n", chanId, src, msgId, static_cast<int>(p.size()),
                  reinterpret_cast<const char*>(p.data()));
    GW_LINK(onChannelMessage(chanId, src, msgId, p));
  }
};

gw::mcu::Settings g_set;
gw::mcu::McuRadio g_radio;
SerialApp g_app;
gw::Config g_cfg;
std::unique_ptr<gw::Router> g_router;
Key32 g_pub{};      // X25519, which is what `keys` prints and peers encrypt to
Key32 g_edPub{};    // Ed25519, when g_signing
bool g_signing = false;   // has an Ed25519 identity and sends IDENT
gw::Position g_pos;          // what the router was last given
bool g_gpsFix = false;
#if GW_HAS_GPS
uint64_t g_gpsFixMs = 0;
uint32_t g_nmeaGood = 0;
#endif
bool g_radioOk = false;
size_t g_tableBudget = 0;
std::string g_cmdLine, g_gpsLine;
#if GW_HAS_BLE
gw::mcu::BleLink g_ble;
std::unique_ptr<gw::client::Handler> g_handler;
std::map<uint32_t, std::array<uint8_t, 32>> g_edKeys;   // Ed25519 keys the app pinned (saved: /gw/edkeys)

// Group channels joined from the app (protocol 1.1), saved in /gw/channels.
class SavedChannelBook : public gw::ChannelBook {
 public:
  using gw::ChannelBook::ChannelBook;

  void load() {
    std::vector<gw::mcu::SavedChannel> saved;
    if (!gw::mcu::loadChannels(saved)) return;
    for (auto& c : saved) {
      Result r = restore(c.name, c.key.data());
      if (r != Result::Ok) Serial.printf("saved channel \"%s\" not joined: %s\n", c.name.c_str(), describe(r));
      gw::wipe(c.key.data(), c.key.size());
    }
  }

 protected:
  bool persist() const override {
    std::vector<gw::mcu::SavedChannel> out;
    for (const Entry& e : list()) out.push_back({e.name, e.key});
    bool ok = gw::mcu::saveChannels(out);
    for (auto& c : out) gw::wipe(c.key.data(), c.key.size());
    return ok;
  }
};

std::unique_ptr<SavedChannelBook> g_channels;
uint64_t g_bootMs = 0;
#endif

void printStats() {
  auto& s = g_router->stats();
  Serial.printf("tx %u rx %u bad %u authfail %u delivered %u forwarded %u stored %u air %lums "
                "store %u nb %u sos held %u sent %u heard %u%s\n",
                s.tx, s.rx, s.rxBad, s.rxAuthFail, s.delivered, s.forwarded, s.stored,
                static_cast<unsigned long>(s.airMs), static_cast<unsigned>(g_router->storeSize()),
                static_cast<unsigned>(g_router->neighborCount(nowMs())), static_cast<unsigned>(g_router->sosCount()),
                s.sosTx, s.sosHeard, g_router->sosActive() ? " SOS-ACTIVE" : "");
}

void printPos() {
  Serial.printf("%s %.6f %.6f", g_pos.valid ? "fix" : "nofix", g_pos.lat, g_pos.lon);
#if GW_HAS_GPS
  if (g_gpsFix) Serial.printf(" (gps, %lus old)", static_cast<unsigned long>((nowMs() - g_gpsFixMs) / 1000));
  else if (g_pos.valid) Serial.print(" (stored, no gps fix yet)");
  else Serial.printf(" (gps: %u good sentences)", g_nmeaGood);
#else
  if (g_pos.valid) Serial.print(g_set.fixedPos && g_pos.lat == g_set.lat && g_pos.lon == g_set.lon ? " (stored)" : " (from app)");
#endif
  Serial.println();
}

void printTxState();

void printStatus() {
  printStats();
  printTxState();
  Serial.printf("node %08x %s, %.3f MHz, %d dBm out (%d dBm drive), radio %s, crc err %u, tx err %u\n",
                g_router->id(), GW_BOARD_NAME, g_set.freqMHz, g_radio.outputDbm(), g_radio.driveDbm(),
                g_radioOk ? "ok" : "FAILED", g_radio.crcErrors(), g_radio.txErrors());
  if (g_radio.duty().capped())
    Serial.printf("region %s, duty cycle %lu of %lu ms this hour, %u frames dropped at the cap\n",
                  gw::mcu::regionInfo(g_set.region).name, static_cast<unsigned long>(g_radio.duty().usedMs(nowMs())),
                  static_cast<unsigned long>(g_radio.duty().limitMs()), static_cast<unsigned>(g_radio.dutyDropped()));
  else
    Serial.printf("region %s, no duty-cycle cap\n", gw::mcu::regionInfo(g_set.region).name);
  Serial.printf("tables: store %u/%u seen %u/%u neighbors %u/%u sos %u/%u, peer keys %u stored\n",
                static_cast<unsigned>(g_router->storeSize()), static_cast<unsigned>(g_cfg.storeCapacity),
                static_cast<unsigned>(g_router->seenSize()), static_cast<unsigned>(g_cfg.seenCapacity),
                static_cast<unsigned>(g_router->neighborTableSize()), static_cast<unsigned>(kLocCapacity),
                static_cast<unsigned>(g_router->sosCount()), static_cast<unsigned>(g_cfg.sosCapacity),
                static_cast<unsigned>(g_set.peerCount));
  Serial.printf("heap: free %u, min free %u, largest block %u, tables worst case ~%u; uptime %lus\n",
                static_cast<unsigned>(gw::mcu::freeHeap()), static_cast<unsigned>(gw::mcu::minFreeHeap()),
                static_cast<unsigned>(gw::mcu::largestFreeBlock()), static_cast<unsigned>(g_tableBudget),
                static_cast<unsigned long>(nowMs() / 1000));
  Serial.printf("channel key %s, %s%s\n", g_set.havePsk ? "on" : "off",
                g_set.requireEnc ? "plaintext DATA refused" : "plaintext DATA accepted",
                g_set.responder ? ", SOS responder" : "");
  Serial.print("pos ");
  printPos();
#if GW_HAS_UI
  Serial.printf("battery %lu mV (%u%%, rough while charging)\n", static_cast<unsigned long>(gw::mcu::ui::batteryMv()),
                static_cast<unsigned>(gw::mcu::ui::batteryPct()));
#endif
#if GW_HAS_BLE
  Serial.printf("%s; %u app events held\n", g_ble.describe().c_str(), static_cast<unsigned>(g_handler->queued()));
#endif
}

bool txOpen() { return gw::mcu::txGateOpen(g_set.txOn, g_router->sosActive()); }

void printTxState() {
  if (g_set.txOn) Serial.println("tx on");
  else if (g_router->sosActive()) Serial.println("tx off, but transmitting while our SOS runs");
  else Serial.printf("TX OFF: receiving only, %u frames not sent. Check the antenna and region, then: tx on\n",
                     static_cast<unsigned>(g_radio.txRefused()));
}

void printHelp() {
  Serial.print(
      "range test: rangetest <hex-id> [seconds] | rangetest stop | rangetest\n"
      "commands: send <hex-id> <text> | known <hex-id> <lat> <lon> | stats | status | pos\n"
      "          keys | peer <hex-id> <hex-pubkey> | sos <text> | sosstop | sosack <hex-id>\n"
      "settings (saved): name [text] | name clear | setpos <lat> <lon> | setpos clear | psk <64 hex> | psk gen | psk off\n"
      "          tx on|off | power <dBm> | freq <MHz> | region us915|eu868 | responder on|off | requireenc on|off | reboot\n"
#if GW_HAS_BLE
      "app link: ble | ble on|off (saved) | ble clear (forget paired phones) | ble pin [6 digits]\n"
#if GW_HAS_OLED
      "screen: display (wake it; it sleeps 10 minutes after the last event)\n"
#endif
#endif
  );
}

bool parseOnOff(const std::string& s, bool& v) {
  if (s == "on") v = true;
  else if (s == "off") v = false;
  else return false;
  return true;
}

enum class Rename { Ok, NoIdentity, BadName, Failed };

// Re-signs IDENT with the new name, saves it and announces it. The seed is
// read again rather than kept in memory.
Rename renameNode(const std::string& name) {
  if (!g_signing) return Rename::NoIdentity;
  if (!gw::mcu::validNodeName(name)) return Rename::BadName;
  Key32 seed{};
  const bool ok = gw::mcu::loadIdentitySeed(seed) && g_router->setSigningKey(seed.data(), name);
  gw::wipe(seed.data(), seed.size());
  if (!ok) return Rename::Failed;
  g_set.name = name;
  if (!gw::mcu::saveName(g_set)) Serial.println("warning: name not saved, it lasts until reboot");
  g_router->announceIdent(nowMs());
  Serial.printf("renamed to \"%s\"\n", name.c_str());
  return Rename::Ok;
}

void handleCommand(std::string line) {
  gw::Router& r = *g_router;
  std::string cmd = word(line);
  if (cmd.empty()) return;
  if (cmd == "send") {
    std::string id = word(line);
    uint32_t dst;
    while (!line.empty() && line[0] == ' ') line.erase(0, 1);
    if (!parseId(id, dst) || line.empty()) {
      Serial.println("usage: send <hex-id> <text>");
      return;
    }
    if (!r.canSealTo(dst)) {
      r.requestIdent(dst, nowMs());
      Serial.printf("no key for %08x yet, so nothing was sent (DMs are never sent unencrypted). Asked for its key: try again once \"IDENT\" shows it, or add it with peer.\n", dst);
      return;
    }
    uint32_t mid = r.send(dst, std::vector<uint8_t>(line.begin(), line.end()), nowMs());
    if (mid) {
      Serial.printf("queued id %08x -> %08x\n", mid, dst);
      if (!txOpen()) Serial.println("TX is off, so this will not be sent (tx on)");
    } else {
      Serial.println("too long to send");
    }
  } else if (cmd == "rangetest") {
    std::string a = word(line);
    uint32_t dst;
    if (a == "stop") {
      g_rt.stop();
      Serial.printf("range test stopped: %u of %u delivered\n", static_cast<unsigned>(g_rt.delivered()),
                    static_cast<unsigned>(g_rt.sent()));
    } else if (a.empty()) {
      Serial.printf("range test %s: %u of %u delivered\n", g_rt.active() ? "running" : "not running",
                    static_cast<unsigned>(g_rt.delivered()), static_cast<unsigned>(g_rt.sent()));
    } else if (!parseId(a, dst)) {
      Serial.println("usage: rangetest <hex-id> [seconds] | rangetest stop | rangetest");
    } else if (!txOpen()) {
      Serial.println("TX is off: type tx on first");
    } else if (!r.canSealTo(dst)) {
      r.requestIdent(dst, nowMs());
      Serial.printf("no key for %08x yet: asked for it; start the range test once its IDENT arrives\n", dst);
    } else {
      std::string sec = word(line);
      uint32_t ms = sec.empty() ? gw::mcu::RangeTest::kDefaultIntervalMs : static_cast<uint32_t>(std::atoi(sec.c_str())) * 1000u;
      g_rt.start(dst, ms, nowMs());
      Serial.printf("range test to %08x every %u s; rangetest stop ends it\n", dst,
                    static_cast<unsigned>(g_rt.intervalMs() / 1000));
    }
  } else if (cmd == "known") {
    std::string id = word(line), la = word(line), lo = word(line);
    uint32_t nid;
    double lat, lon;
    if (!parseId(id, nid) || !parseDouble(la, lat) || !parseDouble(lo, lon)) {
      Serial.println("usage: known <hex-id> <lat> <lon>");
      return;
    }
    r.addKnownPosition(nid, {lat, lon, true}, nowMs());
    Serial.println("ok");
  } else if (cmd == "stats") {
    printStats();
  } else if (cmd == "status") {
    printStatus();
  } else if (cmd == "pos") {
    printPos();
  } else if (cmd == "keys") {
    // same format as a `peer` argument, so it can be pasted on the other node
    Serial.printf("%08x %s\n", r.id(), toHex(g_pub.data(), g_pub.size()).c_str());
  } else if (cmd == "peer") {
    std::string id = word(line), hex = word(line);
    uint32_t pid;
    Key32 pub;
    if (!parseId(id, pid) || !fromHex(hex, pub.data(), pub.size()) || !r.addPeerKey(pid, pub.data())) {
      Serial.println("bad peer (want <hex-id> <64 hex chars>)");
    } else if (!gw::mcu::savePeer(g_set, pid, pub)) {
      Serial.printf("ok, but not saved (%u peer keys already stored)\n",
                    static_cast<unsigned>(gw::mcu::kMaxStoredPeers));
    } else {
      Serial.println("ok");
    }
  } else if (cmd == "sos") {
    while (!line.empty() && line[0] == ' ') line.erase(0, 1);
    if (r.startSos(line, ownBattery(), 0xFF, nowMs()))
      Serial.printf("SOS on%s, repeating until sosstop\n",
                    line.size() > gw::kSosTextMax ? " (text cut to 60 bytes)" : "");
    else
      Serial.println("SOS rate limited, try again in a minute");
  } else if (cmd == "sosstop") {
    r.stopSos(nowMs());
    Serial.println("SOS off");
  } else if (cmd == "sosack") {
    uint32_t src;
    if (!parseId(word(line), src)) Serial.println("usage: sosack <hex-id>");
    else if (r.ackSos(src, nowMs())) Serial.printf("acked SOS from %08x\n", src);
    else Serial.printf("no SOS held from %08x\n", src);
  } else if (cmd == "setpos") {
    std::string a = word(line), b = word(line);
    double lat, lon;
    if (a == "clear") {
      g_set.fixedPos = false;
      Serial.println(gw::mcu::saveFixedPos(g_set) ? "stored position cleared (takes effect on reboot)"
                                                   : "save failed");
    } else if (parseDouble(a, lat) && parseDouble(b, lon) && lat >= -90 && lat <= 90 && lon >= -180 &&
               lon <= 180) {
      g_set.fixedPos = true;
      g_set.lat = lat;
      g_set.lon = lon;
      if (!g_gpsFix) {
        g_pos = {lat, lon, true};
        r.setPosition(g_pos, nowMs());
      }
      Serial.println(gw::mcu::saveFixedPos(g_set) ? "ok" : "save failed");
    } else {
      Serial.println("usage: setpos <lat> <lon> | setpos clear");
    }
  } else if (cmd == "psk") {
    std::string a = word(line);
    if (a == "off") {
      g_set.havePsk = false;
      gw::wipe(g_set.psk.data(), g_set.psk.size());
      Serial.println(gw::mcu::savePsk(g_set) ? "channel key removed (takes effect on reboot)" : "save failed");
      return;
    }
    Key32 k;
    if (a == "gen") {
      gw::mcu::secureRandom(k.data(), k.size());
      Serial.printf("new channel key, set it on every node: psk %s\n", toHex(k.data(), k.size()).c_str());
    } else if (!fromHex(a, k.data(), k.size())) {
      Serial.println("usage: psk <64 hex chars> | psk gen | psk off");
      return;
    }
    g_set.psk = k;
    g_set.havePsk = true;
    r.setChannelKey(k.data());
    gw::wipe(k.data(), k.size());
    Serial.println(gw::mcu::savePsk(g_set) ? "channel key on" : "channel key on, but save failed");
  } else if (cmd == "power") {
    double v;
    if (!parseDouble(word(line), v) || v < -9 || v > 40) {
      Serial.printf("usage: power <dBm at the antenna port, max %d>\n", kMaxOutputDbm);
      return;
    }
    g_set.outputDbm = static_cast<int8_t>(g_radio.setOutputDbm(static_cast<int>(v)));
    Serial.printf("%d dBm out (%d dBm drive)%s\n", g_radio.outputDbm(), g_radio.driveDbm(),
                  gw::mcu::saveRadio(g_set) ? "" : ", save failed");
  } else if (cmd == "freq") {
    double v;
    const gw::mcu::RegionInfo& reg = gw::mcu::regionInfo(g_set.region);
    if (!parseDouble(word(line), v) || v < reg.minMHz || v > reg.maxMHz) {
      Serial.printf("usage: freq <MHz, %.4f..%.4f in %s> (takes effect on reboot)\n", reg.minMHz, reg.maxMHz, reg.name);
      return;
    }
    g_set.freqMHz = static_cast<float>(v);
    Serial.println(gw::mcu::saveRadio(g_set) ? "saved, takes effect on reboot" : "save failed");
  } else if (cmd == "region") {
    const std::string name = word(line);
    if (name.empty()) {
      Serial.printf("region %s\n", gw::mcu::regionInfo(g_set.region).name);
      return;
    }
    gw::mcu::Region next;
    if (!gw::mcu::regionFromName(name.c_str(), next)) {
      Serial.println("usage: region us915|eu868 (takes effect on reboot; check your board's antenna and RF path suit the band)");
      return;
    }
    const gw::mcu::RegionInfo& reg = gw::mcu::regionInfo(next);
    g_set.region = next;
    if (g_set.freqMHz < reg.minMHz || g_set.freqMHz > reg.maxMHz) g_set.freqMHz = reg.defaultMHz;
    Serial.printf(gw::mcu::saveRadio(g_set) ? "%s, %.3f MHz: saved, takes effect on reboot\n" : "%s, %.3f MHz: save failed\n",
                  reg.name, g_set.freqMHz);
  } else if (cmd == "tx") {
    std::string arg = word(line);
    bool v;
    if (arg.empty()) {
      printTxState();
    } else if (!parseOnOff(arg, v)) {
      Serial.println("usage: tx on|off");
    } else {
      g_set.txOn = v;
      if (!gw::mcu::saveFlags(g_set)) Serial.println("save failed: this lasts until reboot");
      printTxState();
      if (v) Serial.printf("region %s, %.3f MHz, %d dBm out\n", gw::mcu::regionInfo(g_set.region).name, g_set.freqMHz,
                           g_radio.outputDbm());
    }
  } else if (cmd == "responder" || cmd == "requireenc") {
    bool v;
    if (!parseOnOff(word(line), v)) {
      Serial.printf("usage: %s on|off\n", cmd.c_str());
      return;
    }
    (cmd == "responder" ? g_set.responder : g_set.requireEnc) = v;
    Serial.println(gw::mcu::saveFlags(g_set) ? "saved, takes effect on reboot" : "save failed");
#if GW_HAS_BLE
  } else if (cmd == "ble") {
    std::string a = word(line);
    if (a.empty()) {
      Serial.println(g_ble.describe().c_str());
    } else if (a == "on" || a == "off") {
      g_set.bleOn = a == "on";
      g_ble.setEnabled(g_set.bleOn);
      Serial.printf("BLE %s%s\n", g_set.bleOn ? "on, advertising" : "off", gw::mcu::saveBle(g_set) ? "" : " (save failed)");
    } else if (a == "pin") {
      std::string pin = word(line);
      if (pin.empty()) {
        char now[7];
        gw::mcu::loadBlePin(now);
        Serial.printf("pairing key %s%s\n", now, std::strcmp(now, gw::mcu::kDefaultBlePin) ? "" : " (the default)");
      } else if (!gw::mcu::blePinValid(pin.c_str())) {
        Serial.println("the pairing key must be exactly 6 digits");
      } else {
        Serial.println(gw::mcu::saveBlePin(pin.c_str()) ? "saved, takes effect on reboot; phones already paired keep working"
                                                        : "save failed");
      }
    } else if (a == "clear") {
      g_ble.clearBonds();
      Serial.println("forgot every paired phone; remove \"GhostWave\" from the phone's Bluetooth list too");
    } else {
      Serial.println("usage: ble | ble on | ble off | ble clear | ble pin <6 digits>");
    }
#endif
  } else if (cmd == "name") {
    while (!line.empty() && line[0] == ' ') line.erase(0, 1);
    if (line.empty()) {
      if (g_signing) Serial.printf("name \"%s\"\n", g_set.name.c_str());
      else Serial.println("no name: this node has an older X25519 identity and sends no IDENT");
      return;
    }
    switch (renameNode(line == "clear" ? std::string() : line)) {
      case Rename::Ok: break;
      case Rename::NoIdentity: Serial.println("cannot rename: this node has an older X25519 identity and sends no IDENT"); break;
      case Rename::BadName: Serial.printf("name must be at most %u bytes, no control characters\n", static_cast<unsigned>(gw::kIdentNameMax)); break;
      case Rename::Failed: Serial.println("could not re-sign the identity"); break;
    }
#if GW_HAS_OLED
  } else if (cmd == "display") {
    gw::mcu::oled::wake();
    Serial.println("display: awake");
#endif
  } else if (cmd == "reboot") {
    Serial.println("rebooting");
    Serial.flush();
    delay(50);
    gw::mcu::reboot();
  } else {
    printHelp();
  }
}

void pollSerial() {
  while (Serial.available()) {
    char c = static_cast<char>(Serial.read());
    if (c == '\r' || c == '\n') {
      if (!g_cmdLine.empty()) handleCommand(g_cmdLine);
      g_cmdLine.clear();
    } else if (c == '\b' || c == 0x7F) {
      if (!g_cmdLine.empty()) g_cmdLine.pop_back();
    } else if (g_cmdLine.size() < 200) {
      g_cmdLine += c;
    }
  }
}

#if GW_HAS_GPS
void pollGps(uint64_t now) {
  while (Serial1.available()) {
    char c = static_cast<char>(Serial1.read());
    if (c == '\n') {
      gw::Position p;
      if (gw::parseNmea(g_gpsLine, p)) {
        ++g_nmeaGood;
        g_gpsFix = true;
        g_gpsFixMs = now;
        g_pos = p;
        g_router->setPosition(g_pos, now);
      }
      g_gpsLine.clear();
    } else if (g_gpsLine.size() < 120) {
      g_gpsLine += c;
    }
  }
}
#endif

#if GW_HAS_BLE
// AddContact from the app: an Ed25519 key (its node ID is derived from it) or,
// for a legacy node, an X25519 key plus the node ID. Saved like `peer`.
// Only pins whose peer key is itself stored are kept: the pin is only
// meaningful next to that key, and it bounds the file.
bool saveEdPins() {
  std::map<uint32_t, std::array<uint8_t, 32>> keep;
  for (size_t i = 0; i < g_set.peerCount; ++i) {
    auto it = g_edKeys.find(g_set.peers[i].id);
    if (it != g_edKeys.end()) keep.insert(*it);
  }
  return gw::mcu::saveEdKeys(keep);
}

// A pin is restored only if it still converts to the stored X25519 key: the
// `peer` CLI command can replace that key without touching the pin.
void loadEdPins() {
  std::map<uint32_t, std::array<uint8_t, 32>> saved;
  if (!gw::mcu::loadEdKeys(saved)) return;
  for (const auto& e : saved) {
    Key32 x{};
    gw::ed25519ToX25519(e.second.data(), x.data());
    for (size_t i = 0; i < g_set.peerCount; ++i)
      if (g_set.peers[i].id == e.first && g_set.peers[i].pub == x) g_edKeys[e.first] = e.second;
  }
}

uint32_t addPeerFromApp(uint32_t id, const gw::client::Bytes& ed, const gw::client::Bytes& x, std::string& err) {
  Key32 xPub;
  if (ed.size() == gw::kKeySize && x.empty()) {
    uint32_t keyId = gw::nodeIdOf(ed.data());
    if (!id) id = keyId;
    if (id != keyId || !gw::nodeIdUsable(keyId)) {
      char b[96];
      std::snprintf(b, sizeof b, "Ed25519 key belongs to node %08x, not %08x", static_cast<unsigned>(keyId),
                    static_cast<unsigned>(id));
      err = b;
      return 0;
    }
    gw::ed25519ToX25519(ed.data(), xPub.data());
  } else if (x.size() == gw::kKeySize && ed.empty()) {
    if (!id || id == gw::kBroadcast) {
      err = "an x25519 key needs its node id";
      return 0;
    }
    std::copy(x.begin(), x.end(), xPub.begin());
  } else {
    err = "want one 32-byte key: ed25519_pub, or x25519_pub for a legacy node";
    return 0;
  }
  if (!g_router->addPeerKey(id, xPub.data())) {
    err = "key rejected (low-order key, or peer table full)";
    return 0;
  }
  if (ed.size() == gw::kKeySize) std::copy(ed.begin(), ed.end(), g_edKeys[id].begin());
  else g_edKeys.erase(id);
  if (!gw::mcu::savePeer(g_set, id, xPub))
    Serial.printf("app added %08x, but not saved (%u peer keys already stored)\n", static_cast<unsigned>(id),
                  static_cast<unsigned>(gw::mcu::kMaxStoredPeers));
  if (!saveEdPins()) Serial.println("contact key pin not saved: it lasts until the next reboot");
  return id;
}

void startBle() {
  char name[16];
  std::snprintf(name, sizeof name, "GhostWave-%04x", static_cast<unsigned>(g_cfg.nodeId & 0xFFFF));
  gw::client::NodeIdentity self;
  self.id = g_cfg.nodeId;
  self.name = g_set.name;
  self.legacy = !g_signing;
  self.edPub = g_edPub;
  self.xPub = g_pub;
  self.firmware = "ghostwave-" GW_BOARD_NAME " " GW_FW_VERSION;
  gw::client::Handler::Hooks hooks;
  hooks.addPeer = addPeerFromApp;
  hooks.setOwnPosition = [](const gw::Position& p) {
    // The phone's GPS. Not saved: `setpos` is the stored position.
    g_pos = p.valid ? p : (g_set.fixedPos ? gw::Position{g_set.lat, g_set.lon, true} : gw::Position{});
    g_router->setPosition(g_pos, nowMs());
  };
  hooks.batteryPct = ownBattery;
  hooks.txOff = [] { return !txOpen(); };
  hooks.edKeys = &g_edKeys;
  loadEdPins();
  g_channels.reset(new SavedChannelBook(*g_router));
  g_channels->load();
  hooks.channels = g_channels.get();
  hooks.setName = [](const std::string& newName, std::string& err) -> gw::client::ErrorCode {
    switch (renameNode(newName)) {
      case Rename::Ok: return gw::client::ErrorCode::None;
      case Rename::NoIdentity:
        err = "this node has an older X25519 identity, so no IDENT and no name";
        return gw::client::ErrorCode::NoIdentity;
      case Rename::BadName:
        err = "name must be at most " + std::to_string(gw::kIdentNameMax) + " bytes, no control characters";
        return gw::client::ErrorCode::BadArgument;
      case Rename::Failed: break;
    }
    err = "could not re-sign the identity";
    return gw::client::ErrorCode::SendFailed;
  };
  // 32 held events, not ghostwaved's 64: each can hold a 128-byte text in RAM.
  g_handler.reset(new gw::client::Handler(*g_router, self, g_pos, hooks, g_bootMs, g_ble, 32));
  g_ble.attach(g_handler.get());
  char pin[7];
  gw::mcu::loadBlePin(pin);
  if (g_ble.begin(name, g_set.bleOn, pin)) {
    // Pairings left by earlier firmware (Meshtastic, say) share this radio's
    // address, so a phone would reuse its old bond and cached service list and
    // fail with "characteristic not found". Start clean on first boot.
    if (gw::mcu::settingsWereFresh()) {
      g_ble.clearBonds();
      Serial.println("BLE: first boot, cleared pairings from earlier firmware; forget this node on old phones");
    }
    g_link = g_handler.get();
    Serial.printf("BLE \"%s\" %s\n", name, g_set.bleOn ? "advertising; pair with the key from `ble pin`" : "off (ble on)");
  } else {
    Serial.println("BLE failed to start");
  }
}
#endif

void gwSetup() {
#if GW_HAS_BLE
  g_bootMs = nowMs();
#endif
#if defined(GW_BOARD_RAK4631) || defined(GW_BOARD_RAK3401_1W)
  pinMode(kPin3v3SEnable, OUTPUT);
  digitalWrite(kPin3v3SEnable, HIGH);
#elif defined(GW_BOARD_T1000E)
  pinMode(kPinSensorPower, OUTPUT);
  digitalWrite(kPinSensorPower, HIGH);
  gw::mcu::ui::begin();
#else
  if (kPinVext >= 0) {
    pinMode(kPinVext, OUTPUT);
    digitalWrite(kPinVext, kVextOn ? HIGH : LOW);
  }
#endif
#ifdef GW_HAS_BOARD_POWER
  gwBoardPower();
#endif

  // Keys first (secureRandom borrows the ADC, before anything else uses it).
  bool nvsOk = gw::mcu::loadSettings(g_set);
  if (!nvsOk) {
    Serial.println("settings storage unavailable: settings and keys will not persist");
    g_set.txOn = false;   // nothing says this board was ever enabled
  }
  if (g_set.edIdentity) {
    gw::ed25519Public(g_set.secret.data(), g_edPub.data());
    gw::ed25519ToX25519(g_edPub.data(), g_pub.data());
  } else {
    gw::x25519Public(g_set.secret.data(), g_pub.data());
  }

  g_cfg.nodeId = g_set.nodeId;
  g_cfg.requireEncryption = g_set.requireEnc;
  g_cfg.responder = g_set.responder;
  g_cfg.seenCapacity = kSeenCapacity;
  uint32_t seed[2];
  gw::mcu::secureRandom(reinterpret_cast<uint8_t*>(seed), sizeof seed);
  g_cfg.rngSeed = static_cast<uint64_t>(seed[0]) << 32 | seed[1];
  g_router.reset(new gw::Router(g_cfg, g_radio, g_app));
  g_signing = g_set.edIdentity && g_router->setSigningKey(g_set.secret.data(), g_set.name);
  if (g_set.edIdentity && !g_signing) {
    // Should not happen. Keep the key so messages still decrypt, without IDENT.
    Serial.println("identity does not match the node ID: IDENT off");
    Key32 x{};
    gw::ed25519SecretToX25519(g_set.secret.data(), x.data());
    g_router->setIdentityKey(x.data());
    gw::wipe(x.data(), x.size());
  } else if (!g_set.edIdentity) {
    g_router->setIdentityKey(g_set.secret.data());
  }
  gw::wipe(g_set.secret.data(), g_set.secret.size());   // the router keeps its own copy
  if (g_set.havePsk) g_router->setChannelKey(g_set.psk.data());
  for (size_t i = 0; i < g_set.peerCount; ++i) g_router->addPeerKey(g_set.peers[i].id, g_set.peers[i].pub.data());

  const gw::mcu::RegionInfo& region = gw::mcu::regionInfo(g_set.region);
  if (g_set.freqMHz < region.minMHz || g_set.freqMHz > region.maxMHz) g_set.freqMHz = region.defaultMHz;
  g_radio.setTxGate(txOpen);
#if GW_HAS_OLED
  Serial.println(gw::mcu::oled::begin(GW_FW_VERSION) ? "display: RAK1921 found" : "display: none found");
#endif
  int16_t st = g_radio.begin(g_cfg.phy, g_set.freqMHz, g_set.outputDbm, region.dutyPermille);
  g_radioOk = st == 0;
  if (!g_radioOk) Serial.printf("radio init failed: %d\n", st);

  if (g_set.fixedPos) {
    g_pos = {g_set.lat, g_set.lon, true};
    g_router->setPosition(g_pos, nowMs());
  }
#if GW_HAS_GPS && defined(GW_BOARD_T1000E)
  // AG3335 power-up, the same levels as Meshtastic's T1000-E initVariant().
  pinMode(kPinGpsVrtc, OUTPUT);
  digitalWrite(kPinGpsVrtc, HIGH);
  pinMode(kPinGpsResetbOut, INPUT_PULLUP);
  pinMode(kPinGpsSleepInt, OUTPUT);
  digitalWrite(kPinGpsSleepInt, HIGH);   // awake
  pinMode(kPinGpsRtcInt, OUTPUT);
  digitalWrite(kPinGpsRtcInt, LOW);
  pinMode(kPinGpsReset, OUTPUT);
  digitalWrite(kPinGpsReset, LOW);       // not in reset (reset is active HIGH)
  pinMode(kPinGpsPower, OUTPUT);
  digitalWrite(kPinGpsPower, HIGH);
  Serial1.begin(kGpsBaud);               // variant pins: RX P0.14, TX P0.13
#elif GW_HAS_GPS
  pinMode(kPinGpsReset, OUTPUT);
  digitalWrite(kPinGpsReset, HIGH);   // out of reset (GPS_RESET_MODE is LOW)
  Serial1.begin(kGpsBaud, SERIAL_8N1, kPinGpsRx, kPinGpsTx);
#endif

  g_tableBudget = worstCaseTableBytes(g_cfg);
  Serial.printf("GhostWave node %08x (%s) on %.3f MHz, %d dBm out\n", g_cfg.nodeId, GW_BOARD_NAME,
                g_set.freqMHz, g_radio.outputDbm());
  Serial.printf("key %s, channel key %s, %u peer key%s%s%s\n", toHex(g_pub.data(), g_pub.size()).c_str(),
                g_set.havePsk ? "on" : "off", static_cast<unsigned>(g_set.peerCount),
                g_set.peerCount == 1 ? "" : "s", g_set.requireEnc ? ", plaintext DATA refused" : "",
                g_set.responder ? ", SOS responder" : "");
#if GW_HAS_BLE
  startBle();
#endif
  Serial.printf("free heap %u, router tables need up to ~%u%s\n", static_cast<unsigned>(gw::mcu::freeHeap()),
                static_cast<unsigned>(g_tableBudget),
                g_tableBudget + 32 * 1024 > gw::mcu::freeHeap() ? "  WARNING: may not fit" : "");
  printTxState();
  printHelp();
}

#if GW_HAS_UI
[[noreturn]] void powerDown() {
  Serial.println("powering off; press the button to wake");
  Serial.flush();
  if (g_radioOk) g_radio.sleep();
  gw::mcu::ui::powerOff();
}

// Button: hold ~3 s = SOS on, double press = SOS off, three quick presses =
// power off (on battery, with no SOS running), single press = a chirp
// and the status on the console. The buzzer marks SOS on / off whoever
// started it (button, CLI or app), so it watches the router's state.
void pollUi(uint64_t now) {
  using Ev = gw::mcu::ButtonGesture::Event;
  static bool lastSos = false;
  static uint64_t sosStoppedAt = 0;
  gw::Router& r = *g_router;
  Ev ev = gw::mcu::ui::poll(static_cast<uint32_t>(now), r.sosActive());
  if (ev == Ev::Long) {
    if (r.sosActive()) {
      Serial.println("button: SOS already on (double press stops it)");
      GW_SOUND(SosOn);
    } else if (r.startSos("SOS (button)", ownBattery(), 0xFF, now)) {
      Serial.println("button: SOS on, repeating until a double press or sosstop");
    } else {
      Serial.println("button: SOS rate limited, try again in a minute");
      GW_SOUND(Refused);
    }
  } else if (ev == Ev::Double) {
    if (r.sosActive()) {
      r.stopSos(nowMs());
      sosStoppedAt = now;
      Serial.println("button: SOS off");
    } else {
      GW_SOUND(Refused);
    }
  } else if (ev == Ev::Triple) {
    // sosStoppedAt: a double press that just ended an SOS must not run on into a shutdown
    if (r.sosActive() || (sosStoppedAt && now - sosStoppedAt < 5000)) {
      Serial.println("button: not powering off during an SOS");
      GW_SOUND(Refused);
    } else if (gw::mcu::ui::usbPowered()) {
      Serial.println("button: on USB power, staying on");
      GW_SOUND(Refused);
    } else {
      powerDown();
    }
  } else if (ev == Ev::Single) {
    GW_SOUND(Alive);
    printStats();
  }
  bool sos = r.sosActive();
  if (sos != lastSos) {
    if (sos) GW_SOUND(SosOn);
    else GW_SOUND(SosOff);
    lastSos = sos;
  }
}
#endif

void gwLoop() {
  static uint64_t lastTick = 0;
  static uint8_t buf[256];
  uint64_t now = nowMs();
  size_t len;
  float rssi;
  if (g_radioOk && g_radio.poll(buf, sizeof buf, len, rssi)) {
    g_lastRssi = rssi;
    g_router->onReceive(buf, len, rssi, now);
  }
  if (g_rt.due(now)) {
    char ping[16];
    int n = std::snprintf(ping, sizeof ping, "RT %u", static_cast<unsigned>(g_rt.nextSeq()));
    const uint32_t seq = g_rt.nextSeq();
    const uint32_t mid = g_router->send(g_rt.dst(), std::vector<uint8_t>(ping, ping + n), now);
    g_rt.onSent(mid, now);
    Serial.printf("RANGE ping %u %s\n", static_cast<unsigned>(seq), mid ? "sent" : "refused");
    if (!g_rt.active()) Serial.println("range test finished: reached its limit of pings");
  }
#if GW_HAS_GPS
  pollGps(now);
#endif
  pollSerial();
  {
    // An SOS can start from the console, the button or the app.
    static bool overriding = false;
    const bool o = !g_set.txOn && g_router->sosActive();
    if (o && !overriding) Serial.println("SOS: transmitting although TX is off, until the SOS stops");
    overriding = o;
  }
#if GW_HAS_BLE
  g_ble.poll(now);
#endif
#if GW_HAS_UI
  pollUi(now);
#endif
#if GW_HAS_OLED
  if (gw::mcu::oled::due(static_cast<uint32_t>(now))) {
    auto& st = g_router->stats();
    gw::mcu::oled::Status os{};
    os.name = g_set.name.c_str();
    os.nodeId = g_cfg.nodeId;
    os.radioOk = g_radioOk;
    os.txOn = g_set.txOn;
    os.sosOwn = g_router->sosActive();
    os.sosHeard = static_cast<uint32_t>(g_router->sosCount());
    os.outputDbm = g_radio.outputDbm();
    os.neighbors = static_cast<uint32_t>(g_router->neighborCount(now));
    os.tx = st.tx;
    os.rx = st.rx;
    os.bleEnabled = g_ble.enabled();
    os.bleConnected = g_ble.connected();
    os.batteryPct = ownBattery();
    os.rangeShow = g_rt.active() || now < g_rtShowUntil;
    os.rangeSender = g_rt.sent() > 0 || g_rt.active();
    os.rangeSent = g_rt.sent();
    os.rangeDelivered = g_rt.delivered();
    os.rangeRxSeq = g_rtRxSeq;
    os.rangeRxCount = g_rtRxCount;
    os.rangeRssi = static_cast<int>(g_lastRssi);
    os.neighborIdCount =
        static_cast<uint8_t>(g_router->freshNeighbors(now, os.neighborIds, gw::mcu::oled::kNeighborRows));
    gw::mcu::oled::draw(static_cast<uint32_t>(now), os);
  }
#endif
  if (now - lastTick >= 2) {
    lastTick = now;
    if (g_radioOk) g_router->tick(now);
  }
  delay(1);
}

}  // namespace

#if GW_NRF52
// The Adafruit core runs loop() on a 4 KB stack. X25519 / Ed25519 and the
// router need more, so GhostWave gets its own 16 KB task and loop() idles.
namespace {
void gwTask(void*) {
  gwSetup();
  for (;;) gwLoop();
}
}  // namespace

void setup() {
  Serial.begin(115200);
  uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 2000) delay(10);   // native USB: give the host a moment
  xTaskCreate(gwTask, "gw", 4096, nullptr, TASK_PRIO_LOW, nullptr);   // depth in 32-bit words
}

void loop() { delay(1000); }
#else
void setup() {
  Serial.begin(115200);
  uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 2000) delay(10);   // native USB: give the host a moment
  gwSetup();
}

void loop() { gwLoop(); }
#endif
