// Transport-independent half of the client link (docs/CLIENT_PROTOCOL.md):
// request handling, the offline event queue and its replay on Hello. The Pi
// daemon's TCP listener (firmware/pi/client_link.cpp) and the MCU firmware's
// BLE service both drive one of these; they only move bytes.
//
// Portable: no I/O and no OS calls. Not thread safe: call it from the thread
// that owns the Router.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>
#include <map>
#include <string>
#include <vector>

#include "ghostwave/client_proto.h"
#include "ghostwave/router.h"

namespace gw {
namespace client {

// What NodeInfo says about this node.
struct NodeIdentity {
  uint32_t id = 0;
  std::string name;
  std::array<uint8_t, 32> edPub{}, xPub{};
  bool legacy = false;              // X25519 identity only (no IDENT)
  std::string firmware = "ghostwaved";
};

// One connected app, as the handler sees it. The transport owns it.
struct Conn {
  bool hello = false;     // sent a good Hello
  bool closing = false;   // the transport closes it once its output drains
  std::string peer;       // for log lines ("127.0.0.1:5123", "ble")
};

// What the handler needs from a transport.
class Transport {
 public:
  virtual ~Transport() = default;
  // Queue one whole frame (header included) for `c`.
  virtual void write(Conn& c, const uint8_t* frame, size_t n) = 0;
  // Calls `fn` for every open connection, hello or not.
  virtual void forEachConn(const std::function<void(Conn&)>& fn) = 0;
  // Whether events should be held while no app is connected (the link is up).
  virtual bool holdEvents() const = 0;
  // One log line, no trailing newline.
  virtual void log(const std::string& line) { (void)line; }
};

class Handler {
 public:
  struct Hooks {
    // Pins a contact key: (id or 0, ed25519 or empty, x25519 or empty) ->
    // node id, or 0 with `err` set.
    std::function<uint32_t(uint32_t, const Bytes&, const Bytes&, std::string&)> addPeer;
    // Our own position from the app (valid = false clears it).
    std::function<void(const gw::Position&)> setOwnPosition;
    // Ed25519 keys of pinned peers, for ListContacts.
    const std::map<uint32_t, std::array<uint8_t, 32>>* edKeys = nullptr;
  };

  static constexpr size_t kDefaultQueueMax = 64;
  // A DM always fits: 128-byte frame - 19 header - 20 positions - 16 tag.
  static constexpr uint32_t kMaxTextBytes = 73;

  Handler(gw::Router& router, const NodeIdentity& self, const gw::Position& pos, Hooks hooks, uint64_t startMs,
          Transport& transport, size_t queueMax = kDefaultQueueMax);
  Handler(const Handler&) = delete;
  Handler& operator=(const Handler&) = delete;

  // Handles every whole frame buffered in `in` for `c`. Stops early once `c`
  // is closing (bad version).
  void receive(Conn& c, FrameReader& in, uint64_t nowMs);
  void handle(Conn& c, const ToRadio& m, uint64_t nowMs);

  void send(Conn& c, const FromRadio& m);
  void reply(Conn& c, uint32_t reqId, FromKind kind);
  void error(Conn& c, uint32_t reqId, ErrorCode code, const std::string& detail);

  // Connections past Hello and not closing.
  size_t ready();
  size_t queued() const { return queue_.size(); }

  // Router events.
  void onMessage(uint32_t src, uint32_t msgId, const std::vector<uint8_t>& payload);
  void onDelivered(uint32_t dst, uint32_t msgId);
  void onSos(const gw::SosInfo& s);
  void onSosAck(uint32_t responder, uint16_t seq);
  void onPeerIdent(uint32_t id, const std::string& name, bool firstSeen);
  void onKeyChange(uint32_t id, const uint8_t edPub[32], const std::string& name);
  void onNeighbor(uint32_t id, const gw::Position& pos, bool isNew);

 private:
  // Sends to every connection past Hello, or holds it if there is none (`hold`).
  void event(const FromRadio& m, bool hold);

  gw::Router& r_;
  NodeIdentity self_;
  const gw::Position& pos_;
  Hooks hooks_;
  uint64_t startMs_;
  Transport& t_;
  size_t queueMax_;
  std::deque<FromRadio> queue_;
  std::map<uint32_t, uint32_t> clientIds_;   // mesh msg id -> client_msg_id
  std::deque<uint32_t> clientIdOrder_;
};

}  // namespace client
}  // namespace gw
