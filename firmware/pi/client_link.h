// Client link for ghostwaved (docs/CLIENT_PROTOCOL.md): a TCP listener that
// speaks the framed protobuf protocol in ghostwave/client_proto.h. Single
// threaded and non-blocking: the daemon's main loop calls poll() each turn.
// Request handling and the event queue live in ghostwave/client_handler.h,
// shared with the MCU firmware's BLE transport; this file only moves bytes.
#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

#include "ghostwave/client_handler.h"
#include "ghostwave/client_proto.h"
#include "ghostwave/router.h"

using ClientNodeIdentity = gw::client::NodeIdentity;

class ClientLink : private gw::client::Transport {
 public:
  using Hooks = gw::client::Handler::Hooks;

  static constexpr size_t kMaxClients = 4;
  static constexpr size_t kQueueMax = 64;            // events held with no client connected
  static constexpr size_t kOutMax = 64 * 1024;       // per-client send backlog before we drop it
  static constexpr uint32_t kMaxTextBytes = gw::client::Handler::kMaxTextBytes;

  ClientLink(gw::Router& router, const ClientNodeIdentity& self, const gw::Position& pos, Hooks hooks,
             uint64_t startMs);
  ~ClientLink();
  ClientLink(const ClientLink&) = delete;
  ClientLink& operator=(const ClientLink&) = delete;

  // "PORT", "HOST:PORT" or "[V6HOST]:PORT". Host defaults to 127.0.0.1.
  bool listen(const std::string& spec, std::string& err);
  const std::string& address() const { return addr_; }
  void poll(uint64_t nowMs);
  // Clients must prove they know `pin` in Hello.
  void requirePin(const std::string& pin, std::function<void(uint8_t*, size_t)> random) {
    h_.requirePin(pin, std::move(random));
  }

  // Router events (forwarded from the daemon's AppPort).
  void onMessage(uint32_t src, uint32_t msgId, const std::vector<uint8_t>& payload) {
    h_.onMessage(src, msgId, payload);
  }
  void onDelivered(uint32_t dst, uint32_t msgId) { h_.onDelivered(dst, msgId); }
  void onSos(const gw::SosInfo& s) { h_.onSos(s); }
  void onSosAck(uint32_t responder, uint16_t seq) { h_.onSosAck(responder, seq); }
  void onSosCancelled(uint32_t src, uint16_t seq, bool verified) { h_.onSosCancelled(src, seq, verified); }
  void onPeerIdent(uint32_t id, const std::string& name, bool firstSeen) { h_.onPeerIdent(id, name, firstSeen); }
  void onKeyChange(uint32_t id, const uint8_t edPub[32], const std::string& name) {
    h_.onKeyChange(id, edPub, name);
  }
  void onNeighbor(uint32_t id, const gw::Position& pos, bool isNew) { h_.onNeighbor(id, pos, isNew); }
  void onLinkPing(uint32_t node, bool answered, int fwd, int rev) { h_.onLinkPing(node, answered, fwd, rev); }
  void onChannelMessage(uint32_t chanId, uint32_t src, uint32_t msgId, const std::vector<uint8_t>& payload) {
    h_.onChannelMessage(chanId, src, msgId, payload);
  }

 private:
  struct Client {
    int fd = -1;
    gw::client::Conn conn;   // hello / closing (close once `out` drains) / peer
    gw::client::FrameReader in;
    gw::client::Bytes out;
  };

  // gw::client::Transport
  void write(gw::client::Conn& c, const uint8_t* frame, size_t n) override;
  void forEachConn(const std::function<void(gw::client::Conn&)>& fn) override;
  bool holdEvents() const override { return lfd_ >= 0; }
  void log(const std::string& line) override;

  void accept();
  void readFrom(Client& c, uint64_t now);
  void flush(Client& c);
  void dropClosed();

  gw::client::Handler h_;
  int lfd_ = -1;
  std::string addr_;
  std::vector<Client> clients_;
};
