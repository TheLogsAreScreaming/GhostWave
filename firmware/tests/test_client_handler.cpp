// Host tests for the transport-independent client-link handler
// (firmware/core/src/client_handler.cpp), which ghostwaved's TCP link and the
// MCU firmware's BLE link share: Hello gating, replies, the offline event
// queue and its replay on Hello, bad frames, multi-connection fan-out, and the
// protocol 1.1 requests (group channels, SetName).
#include <cstdio>
#include <cstring>
#include <deque>
#include <string>
#include <vector>

#include "ghostwave/channel_book.h"
#include "ghostwave/client_handler.h"
#include "ghostwave/crypto.h"
#include "ghostwave/client_proto.h"
#include "ghostwave/router.h"

using namespace gw::client;

static int g_fail = 0, g_pass = 0;
#define CHECK(cond)                                                     \
  do {                                                                  \
    if (cond) {                                                         \
      ++g_pass;                                                         \
    } else {                                                            \
      ++g_fail;                                                         \
      std::printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond);     \
    }                                                                   \
  } while (0)

namespace {

struct NullRadio : gw::RadioPort {
  bool channelBusy() override { return false; }
  bool transmit(const uint8_t*, size_t) override { return true; }
};
struct NullApp : gw::AppPort {
  void onMessage(uint32_t, uint32_t, const std::vector<uint8_t>&) override {}
};

// A transport with N connections whose output is decoded back to FromRadio.
struct FakeTransport : Transport {
  struct C {
    Conn conn;
    bool open = true;
    Bytes out;
    uint64_t seenTx = 0, sentRx = 0;
  };
  std::deque<C> conns;
  bool hold = true;
  std::vector<std::string> logs;

  C& add(const std::string& peer) {
    conns.emplace_back();
    conns.back().conn.peer = peer;
    return conns.back();
  }
  void write(Conn& c, const uint8_t* f, size_t n) override {
    for (auto& x : conns)
      if (&x.conn == &c) x.out.insert(x.out.end(), f, f + n);
  }
  void forEachConn(const std::function<void(Conn&)>& fn) override {
    for (auto& x : conns)
      if (x.open) fn(x.conn);
  }
  bool holdEvents() const override { return hold; }
  void log(const std::string& line) override { logs.push_back(line); }

  // Every frame written to `c` since the last call.
  static std::vector<FromRadio> drain(C& c) {
    std::vector<FromRadio> v;
    FrameReader r;
    r.push(c.out.data(), c.out.size());
    c.out.clear();
    uint8_t ver;
    Bytes body;
    while (r.next(ver, body) == FrameReader::Result::Frame) {
      FromRadio m;
      if (ver == kSecureVersion && c.conn.secure) {   // sealed by the node: open as a client would
        Bytes plain(body.size() - gw::kLinkTagSize);
        if (gw::linkOpen(c.conn.txKey.data(), c.seenTx++, body.data(), body.size(), plain.data()) &&
            decodeFrom(plain.data(), plain.size(), m))
          v.push_back(m);
        else
          v.push_back(FromRadio());
      } else if (ver == kProtocolVersion && decodeFrom(body.data(), body.size(), m)) v.push_back(m);
      else v.push_back(FromRadio());   // kind None marks a bad frame
    }
    return v;
  }
};

struct Rig {
  NullRadio radio;
  NullApp app;
  gw::Config cfg;
  gw::Router router;
  gw::Position pos;
  FakeTransport t;
  Handler::Hooks hooks;
  NodeIdentity self;
  Handler h;
  std::vector<gw::Position> ownPos;

  static gw::Config mkCfg() {
    gw::Config c;
    c.nodeId = 0x11111111;
    c.rngSeed = 7;
    return c;
  }
  explicit Rig(size_t queueMax = 64)
      : cfg(mkCfg()), router(cfg, radio, app), h(router, ident(), pos, mkHooks(), 0, t, queueMax) {}

  static NodeIdentity ident() {
    NodeIdentity s;
    s.id = 0x11111111;
    s.name = "GhostWave-1111";
    s.legacy = true;
    for (int i = 0; i < 32; ++i) s.xPub[i] = static_cast<uint8_t>(i + 1);
    s.firmware = "ghostwave-test 1";
    return s;
  }
  Handler::Hooks mkHooks() {
    Handler::Hooks k;
    k.addPeer = [](uint32_t id, const Bytes& ed, const Bytes& x, std::string& err) -> uint32_t {
      if (ed.empty() && x.size() == 32 && id) return id;
      err = "nope";
      return 0;
    };
    k.setOwnPosition = [this](const gw::Position& p) {
      ownPos.push_back(p);
      pos = p;
    };
    return k;
  }

  // Sends one ToRadio from connection `c` as a frame.
  // A plain frame as an authenticated client would send it.
  static Bytes sealed(FakeTransport::C& c, const Bytes& f) {
    size_t pb = f.size() - kFrameHeader - 1, len = 1 + pb + gw::kLinkTagSize;
    Bytes s(kFrameHeader + len);
    s[0] = kMagic0, s[1] = kMagic1, s[2] = static_cast<uint8_t>(len), s[3] = 0, s[4] = kSecureVersion;
    gw::linkSeal(c.conn.rxKey.data(), c.sentRx++, f.data() + kFrameHeader + 1, pb, s.data() + kFrameHeader + 1);
    return s;
  }
  void req(FakeTransport::C& c, const ToRadio& m, uint64_t now = 1000) {
    Bytes f;
    frameTo(m, f);
    if (c.conn.secure) f = sealed(c, f);
    FrameReader in;
    in.push(f.data(), f.size());
    h.receive(c.conn, in, now);
  }
  void hello(FakeTransport::C& c, uint32_t reqId = 1) {
    ToRadio m;
    m.reqId = reqId;
    m.kind = ToKind::Hello;
    m.protocolVersion = 1;
    m.clientName = "test";
    req(c, m);
  }
};

void testHelloGate() {
  Rig r;
  auto& c = r.t.add("a");
  ToRadio m;
  m.reqId = 9;
  m.kind = ToKind::GetStatus;
  r.req(c, m);
  auto v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].kind == FromKind::Error && v[0].error == ErrorCode::NeedHello && v[0].reqId == 9);

  r.hello(c, 3);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].kind == FromKind::NodeInfo && v[0].reqId == 3);
  CHECK(v[0].nodeId == 0x11111111 && v[0].legacy && v[0].ed25519Pub.empty() && v[0].x25519Pub.size() == 32);
  CHECK(v[0].firmware == "ghostwave-test 1" && v[0].maxTextBytes == 73 && v[0].name == "GhostWave-1111");
  CHECK(c.conn.hello && !c.conn.closing);

  ToRadio bad;
  bad.kind = ToKind::Hello;
  bad.protocolVersion = 2;
  auto& c2 = r.t.add("b");
  r.req(c2, bad);
  v = FakeTransport::drain(c2);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadVersion && c2.conn.closing && !c2.conn.hello);
}

void testQueueAndReplay() {
  Rig r;
  r.h.onMessage(0xAAAA0001, 1, {'h', 'i'});
  r.h.onSos(gw::SosInfo{0xBBBB0002, 5, {}, 0xFF, 50, "help"});
  r.h.onNeighbor(0xCCCC0003, {1, 2, true}, true);   // live only: not held
  CHECK(r.h.queued() == 2);

  auto& c = r.t.add("a");
  r.h.onDelivered(0xDDDD0004, 77);   // connected but no Hello yet: still held
  CHECK(r.h.queued() == 3 && c.out.empty());
  r.hello(c);
  auto v = FakeTransport::drain(c);
  CHECK(v.size() == 4);
  if (v.size() == 4) {
    CHECK(v[0].kind == FromKind::NodeInfo && !v[0].replayed);
    CHECK(v[1].kind == FromKind::Text && v[1].replayed && v[1].src == 0xAAAA0001 && v[1].text == Bytes({'h', 'i'}));
    CHECK(v[2].kind == FromKind::Sos && v[2].replayed && v[2].src == 0xBBBB0002 && v[2].batteryPct.has &&
          v[2].batteryPct.v == 50 && !v[2].accuracyM.has);
    CHECK(v[3].kind == FromKind::Delivered && v[3].replayed && v[3].msgId == 77);
  }
  CHECK(r.h.queued() == 0);
  CHECK(!r.t.logs.empty() && r.t.logs.back() == "client a hello \"test\", replaying 3 held events");

  // live now, not replayed, neighbors included
  r.h.onNeighbor(0xCCCC0003, {1, 2, true}, false);
  r.h.onSosAck(0xEEEE0005, 9);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 2 && v[0].kind == FromKind::Neighbor && !v[0].replayed && v[1].kind == FromKind::SosAck &&
        v[1].seq == 9 && v[1].src == 0xEEEE0005);
  CHECK(r.h.queued() == 0);

  // a second Hello on the same connection does not replay again
  c.conn.hello = true;
  r.h.onMessage(1, 2, {'x'});
  FakeTransport::drain(c);
  r.hello(c);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].kind == FromKind::NodeInfo);
}

void testQueueEviction() {
  Rig r(4);
  r.h.onSos(gw::SosInfo{0x5001, 1, {}, 0xFF, 0xFF, "a"});
  r.h.onMessage(0x7001, 1, {'1'});
  r.h.onSos(gw::SosInfo{0x5002, 1, {}, 0xFF, 0xFF, "b"});
  r.h.onMessage(0x7002, 2, {'2'});
  r.h.onMessage(0x7003, 3, {'3'});   // full: the oldest non-SOS (0x7001) goes
  r.h.onSos(gw::SosInfo{0x5003, 1, {}, 0xFF, 0xFF, "c"});   // then 0x7002
  CHECK(r.h.queued() == 4);
  auto& c = r.t.add("a");
  r.hello(c);
  auto v = FakeTransport::drain(c);
  CHECK(v.size() == 5);
  if (v.size() == 5) {
    CHECK(v[1].kind == FromKind::Sos && v[1].src == 0x5001);
    CHECK(v[2].kind == FromKind::Sos && v[2].src == 0x5002);
    CHECK(v[3].kind == FromKind::Text && v[3].src == 0x7003);
    CHECK(v[4].kind == FromKind::Sos && v[4].src == 0x5003);
  }

  // all SOS: the oldest SOS goes
  Rig s(2);
  s.h.onSos(gw::SosInfo{0x5001, 1, {}, 0xFF, 0xFF, "a"});
  s.h.onSos(gw::SosInfo{0x5002, 1, {}, 0xFF, 0xFF, "b"});
  s.h.onSos(gw::SosInfo{0x5003, 1, {}, 0xFF, 0xFF, "c"});
  auto& d = s.t.add("a");
  s.hello(d);
  v = FakeTransport::drain(d);
  CHECK(v.size() == 3 && v[1].src == 0x5002 && v[2].src == 0x5003);

  // link down (BLE off): nothing is held
  Rig off;
  off.t.hold = false;
  off.h.onMessage(1, 1, {'x'});
  CHECK(off.h.queued() == 0);
}

void testFanOut() {
  Rig r;
  auto& a = r.t.add("a");
  auto& b = r.t.add("b");
  auto& c = r.t.add("c");
  r.hello(a);
  r.hello(b);
  FakeTransport::drain(a);
  FakeTransport::drain(b);
  r.h.onPeerIdent(0x1234, "bob", true);
  CHECK(FakeTransport::drain(a).size() == 1 && FakeTransport::drain(b).size() == 1 && c.out.empty());
  CHECK(r.h.queued() == 0);   // someone was there: not held
  b.conn.closing = true;
  r.h.onPeerIdent(0x1234, "bob2", false);
  CHECK(FakeTransport::drain(a).size() == 1 && b.out.empty());
  CHECK(r.h.ready() == 1);
}

void testRequests() {
  Rig r;
  auto& c = r.t.add("a");
  r.hello(c);
  FakeTransport::drain(c);

  ToRadio m;
  m.reqId = 20;
  m.kind = ToKind::SendText;
  m.dest = 0x11111111;   // ourselves
  m.text = {'x'};
  r.req(c, m);
  auto v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadArgument && v[0].reqId == 20);

  m.dest = 0x22222222;
  m.text.assign(74, 'y');
  r.req(c, m);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::TooLong);

  m.text.assign(73, 'y');
  m.clientMsgId = 4242;
  r.req(c, m);   // no key for 0x22222222 and no channel key: refused, never sent in the clear
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::NoKey);
  uint8_t peerPub[32];
  for (int i = 0; i < 32; ++i) peerPub[i] = static_cast<uint8_t>(i * 7 + 9);
  uint8_t ourSecret[32];
  for (int i = 0; i < 32; ++i) ourSecret[i] = static_cast<uint8_t>(i + 1);
  r.router.setIdentityKey(ourSecret);
  CHECK(r.router.addPeerKey(0x22222222, peerPub));
  r.req(c, m);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].kind == FromKind::SendQueued && v[0].msgId != 0 && v[0].clientMsgId == 4242 &&
        v[0].dest == 0x22222222);
  uint32_t mid = v.empty() ? 0 : v[0].msgId;
  r.h.onDelivered(0x22222222, mid);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].kind == FromKind::Delivered && v[0].clientMsgId == 4242 && v[0].msgId == mid);

  m = {};
  m.reqId = 21;
  m.kind = ToKind::SetOwnPosition;
  m.pos = posFromDegrees(44.5, -110.25);
  r.req(c, m);
  m = {};
  m.reqId = 22;
  m.kind = ToKind::GetPosition;
  r.req(c, m);
  v = FakeTransport::drain(c);
  CHECK(r.ownPos.size() == 1 && r.ownPos[0].valid && r.ownPos[0].lat > 44.49 && r.ownPos[0].lat < 44.51);
  CHECK(v.size() == 2 && v[0].kind == FromKind::Ok && v[0].reqId == 21 && v[1].kind == FromKind::Position &&
        v[1].pos == posFromDegrees(44.5, -110.25));

  m = {};
  m.reqId = 23;
  m.kind = ToKind::AddContact;
  m.nodeId = 0x33333333;
  m.ed25519Pub.assign(32, 1);
  r.req(c, m);
  m.ed25519Pub.clear();
  m.x25519Pub.assign(32, 9);
  m.reqId = 24;
  r.req(c, m);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 2 && v[0].error == ErrorCode::KeyRejected && v[0].detail == "nope" && v[1].kind == FromKind::Ok &&
        v[1].reqId == 24);

  r.h.onMessage(1, 2, {'z'});   // live, so not held
  m = {};
  m.reqId = 25;
  m.kind = ToKind::GetStatus;
  r.req(c, m, 61000);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 2 && v[1].kind == FromKind::Status && v[1].status.clients == 1 && v[1].status.queued == 0 &&
        v[1].status.uptimeS == 61);

  m = {};
  m.reqId = 26;
  m.kind = ToKind::SosAck;
  m.nodeId = 0x44444444;
  r.req(c, m);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::NotFound);

  m = {};
  m.reqId = 27;
  m.kind = ToKind::SosStart;
  m.text = {'h', 'e', 'l', 'p'};
  r.req(c, m);
  m.reqId = 28;
  r.req(c, m);   // within a minute: rate limited
  m = {};
  m.reqId = 29;
  m.kind = ToKind::SosStop;
  r.req(c, m);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 3 && v[0].kind == FromKind::Ok && v[1].error == ErrorCode::RateLimited &&
        v[2].kind == FromKind::Ok && !r.router.sosActive());
}

void testBadFrames() {
  Rig r;
  auto& c = r.t.add("a");
  FrameReader in;
  // bad length, then an undecodable body, then a good Hello: link stays up
  const uint8_t badLen[] = {0x94, 0xC3, 0xFF, 0x00};
  in.push(badLen, sizeof badLen);
  Bytes junk;
  const uint8_t pb[] = {0xFF, 0xFF, 0xFF};
  frame(pb, sizeof pb, junk);
  in.push(junk.data(), junk.size());
  ToRadio h;
  h.kind = ToKind::Hello;
  h.protocolVersion = 1;
  Bytes f;
  frameTo(h, f);
  in.push(f.data(), f.size());
  r.h.receive(c.conn, in, 0);
  auto v = FakeTransport::drain(c);
  CHECK(v.size() >= 3);
  CHECK(!v.empty() && v.front().error == ErrorCode::BadFrame);
  CHECK(!v.empty() && v.back().kind == FromKind::NodeInfo && c.conn.hello);

  // a frame with version 2 closes the link; what follows is not handled
  auto& d = r.t.add("b");
  FrameReader in2;
  Bytes v2;
  frame(pb, 1, v2, 2);
  in2.push(v2.data(), v2.size());
  in2.push(f.data(), f.size());
  r.h.receive(d.conn, in2, 0);
  v = FakeTransport::drain(d);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadVersion && d.conn.closing && !d.conn.hello);

  // unknown request (a newer client)
  ToRadio u;
  u.reqId = 5;
  Bytes uf;
  frameTo(u, uf);
  FrameReader in3;
  in3.push(uf.data(), uf.size());
  r.h.receive(c.conn, in3, 0);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::UnknownRequest && v[0].reqId == 5);
}

}  // namespace

// Protocol 1.1 on the shared handler: what TCP (ghostwaved) and BLE (MCU)
// clients both get. A node without a ChannelBook / setName hook says so.
void testProtocol11() {
  std::printf("client handler: protocol 1.1 (channels, SetName)\n");
  NullRadio radio;
  NullApp app;
  gw::Config cfg = Rig::mkCfg();
  gw::Router router(cfg, radio, app);
  gw::Position pos;
  FakeTransport t;
  gw::ChannelBook book(router);   // RAM only, as on the MCU
  std::string renamed;
  Handler::Hooks hooks;
  hooks.channels = &book;
  hooks.setName = [&](const std::string& n, std::string& err) -> ErrorCode {
    if (n.size() > 9) {
      err = "too long";
      return ErrorCode::BadArgument;
    }
    renamed = n;
    return ErrorCode::None;
  };
  Handler h(router, Rig::ident(), pos, hooks, 0, t);
  auto& c = t.add("ble");
  auto send = [&](const ToRadio& m) {
    Bytes f;
    frameTo(m, f);
    FrameReader in;
    in.push(f.data(), f.size());
    h.receive(c.conn, in, 1000);
    return FakeTransport::drain(c);
  };
  ToRadio m;
  m.reqId = 1, m.kind = ToKind::Hello, m.protocolVersion = 1;
  auto v = send(m);
  CHECK(v.size() == 1 && v[0].protocolMinor == kProtocolMinor && v[0].maxChannelTextBytes == 86);

  Bytes psk(32);
  for (int i = 0; i < 32; ++i) psk[i] = static_cast<uint8_t>(i * 3 + 1);
  m = {}, m.reqId = 2, m.kind = ToKind::AddChannel, m.channel = "crew", m.psk = psk;
  v = send(m);
  CHECK(v.size() == 1 && v[0].kind == FromKind::Ok && v[0].reqId == 2);
  CHECK(router.hasGroupChannel(gw::groupChannelId(psk.data())));
  v = send(m);   // again, same key
  CHECK(v.size() == 1 && v[0].kind == FromKind::Ok);
  m.psk[0] ^= 1;   // same name, other key
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadArgument);
  m = {}, m.reqId = 3, m.kind = ToKind::AddChannel, m.channel = "short", m.psk = Bytes(31, 1);
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadArgument);
  for (int i = 0; i < 7; ++i) {
    m = {}, m.kind = ToKind::AddChannel, m.channel = "c" + std::to_string(i), m.psk = Bytes(32, static_cast<uint8_t>(50 + i));
    v = send(m);
    CHECK(v.size() == 1 && v[0].kind == FromKind::Ok);
  }
  m = {}, m.reqId = 4, m.kind = ToKind::AddChannel, m.channel = "ninth", m.psk = Bytes(32, 99);
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::ChannelLimit);

  m = {}, m.reqId = 5, m.kind = ToKind::ListChannels;
  v = send(m);
  CHECK(v.size() == 9 && v.back().kind == FromKind::ChannelsEnd && v.back().count == 8 && v.back().reqId == 5);
  CHECK(v[0].kind == FromKind::Channel && v[0].channel == "crew" && v[0].psk == psk);

  m = {}, m.reqId = 6, m.kind = ToKind::SendChannelText, m.channel = "crew", m.text = {'h', 'i'}, m.clientMsgId = 77;
  v = send(m);
  CHECK(v.size() == 1 && v[0].kind == FromKind::SendQueued && v[0].dest == gw::kBroadcast && v[0].clientMsgId == 77 &&
        v[0].msgId != 0);
  m.text = Bytes(87, 'x');
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::TooLong);
  m.channel = "nope", m.text = {'h'};
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::NotFound);

  // a channel message from the router reaches the app under the channel's name
  h.onChannelMessage(gw::groupChannelId(psk.data()), 0x22222222, 0x1234, {'y', 'o'});
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].kind == FromKind::ChannelMessage && v[0].channel == "crew" && v[0].src == 0x22222222 &&
        v[0].msgId == 0x1234 && v[0].text == Bytes({'y', 'o'}));
  h.onChannelMessage(0xDEADBEEF, 1, 1, {'x'});   // not a channel we know: dropped
  CHECK(FakeTransport::drain(c).empty());

  m = {}, m.reqId = 7, m.kind = ToKind::RemoveChannel, m.channel = "crew";
  v = send(m);
  CHECK(v.size() == 1 && v[0].kind == FromKind::Ok && !router.hasGroupChannel(gw::groupChannelId(psk.data())));
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::NotFound);

  m = {}, m.reqId = 8, m.kind = ToKind::SetName, m.name = "toolongname";
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadArgument && renamed.empty());
  m.name = "Ridge1";
  v = send(m);
  CHECK(v.size() == 1 && v[0].kind == FromKind::Ok && renamed == "Ridge1");
  m = {}, m.reqId = 9, m.kind = ToKind::Hello, m.protocolVersion = 1;
  v = send(m);
  CHECK(v.size() == 1 && v[0].name == "Ridge1");   // the next NodeInfo has it

  // RequestKey (1.4)
  m = {}, m.reqId = 10, m.kind = ToKind::RequestKey, m.nodeId = 0;
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadArgument);
  m.nodeId = 0x33333333;
  v = send(m);   // no signing key to ask with
  CHECK(v.size() == 1 && v[0].error == ErrorCode::NoIdentity);
  uint8_t peerKey[32];
  for (int i = 0; i < 32; ++i) peerKey[i] = static_cast<uint8_t>(i + 9);
  router.setIdentityKey(peerKey);
  CHECK(router.addPeerKey(0x44444444, peerKey));
  m.nodeId = 0x44444444;
  v = send(m);   // already held: nothing to ask
  CHECK(v.size() == 1 && v[0].kind == FromKind::Ok && v[0].reqId == 10);

  {   // with a signing key: asks once, then refuses for 30 s
    uint8_t seed[32], pub[32];
    for (int i = 0; i < 32; ++i) seed[i] = static_cast<uint8_t>(i + 40);
    gw::ed25519Public(seed, pub);
    gw::Config scfg = Rig::mkCfg();
    scfg.nodeId = gw::nodeIdOf(pub);
    gw::Router srouter(scfg, radio, app);
    CHECK(srouter.setSigningKey(seed, "s"));
    FakeTransport st;
    Handler sh(srouter, Rig::ident(), pos, hooks, 0, st);
    auto& sc = st.add("ble");
    auto ask = [&](ToKind kind, uint32_t id, uint64_t at) {
      ToRadio q;
      q.reqId = 1, q.kind = kind, q.protocolVersion = 1, q.nodeId = id;
      Bytes f;
      frameTo(q, f);
      FrameReader in;
      in.push(f.data(), f.size());
      sh.receive(sc.conn, in, at);
      return FakeTransport::drain(sc);
    };
    ask(ToKind::Hello, 0, 1000);
    auto r = ask(ToKind::RequestKey, 0x55555555, 2000);
    CHECK(r.size() == 1 && r[0].kind == FromKind::Ok);
    r = ask(ToKind::RequestKey, 0x55555555, 10000);
    CHECK(r.size() == 1 && r[0].error == ErrorCode::RateLimited);
    r = ask(ToKind::RequestKey, 0x55555555, 33000);
    CHECK(r.size() == 1 && r[0].kind == FromKind::Ok);
  }

  // a node without channels or renaming (no hooks): says so, NodeInfo shows no channel limit
  Rig plain;
  auto& pc = plain.t.add("tcp");
  plain.hello(pc);
  v = FakeTransport::drain(pc);
  CHECK(v.size() == 1 && v[0].protocolMinor == kProtocolMinor && v[0].maxChannelTextBytes == 0);
  ToRadio q;
  q.reqId = 10, q.kind = ToKind::ListChannels;
  plain.req(pc, q);
  v = FakeTransport::drain(pc);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::UnknownRequest);
  q.kind = ToKind::SetName, q.name = "x";
  plain.req(pc, q);
  v = FakeTransport::drain(pc);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::NoIdentity);
}

// Settings (1.11): GetSettings returns the board's values, SetSettings goes
// through the board's hook and its error comes back; a node without the hooks
// says settings are unavailable.
static void testSettings() {
  std::printf("client handler: Settings\n");
  NullRadio radio;
  NullApp app;
  gw::Config cfg = Rig::mkCfg();
  gw::Router router(cfg, radio, app);
  gw::Position pos;
  int dbm = 10;
  FakeTransport t;
  Handler::Hooks hooks;
  hooks.getSettings = [&](SettingsMsg& s) {
    s.outputDbm.set(dbm);
    s.minOutputDbm.set(-9), s.maxOutputDbm.set(30);
    s.hasLeds = true, s.leds.set(true);
  };
  hooks.setSettings = [&](const SettingsMsg& s, std::string& err) {
    if (s.outputDbm.has && s.outputDbm.v > 30) {
      err = "output_dbm: at most 30";
      return ErrorCode::BadArgument;
    }
    if (s.outputDbm.has) dbm = s.outputDbm.v;
    return ErrorCode::None;
  };
  Handler h(router, Rig::ident(), pos, hooks, 0, t);
  auto& c = t.add("ble");
  auto send = [&](const ToRadio& m) {
    Bytes f;
    frameTo(m, f);
    FrameReader in;
    in.push(f.data(), f.size());
    h.receive(c.conn, in, 1000);
    return FakeTransport::drain(c);
  };
  ToRadio m;
  m.reqId = 1, m.kind = ToKind::Hello, m.protocolVersion = 1;
  send(m);
  m = {}, m.reqId = 2, m.kind = ToKind::GetSettings;
  auto v = send(m);
  CHECK(v.size() == 1 && v[0].kind == FromKind::Settings && v[0].reqId == 2 && v[0].settings.outputDbm.v == 10 &&
        v[0].settings.maxOutputDbm.v == 30 && v[0].settings.hasLeds);
  m = {}, m.reqId = 3, m.kind = ToKind::SetSettings, m.settings.outputDbm.set(27);
  v = send(m);
  CHECK(v.size() == 1 && v[0].kind == FromKind::Ok && dbm == 27);
  m.reqId = 4, m.settings.outputDbm.set(33);
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadArgument && v[0].detail == "output_dbm: at most 30" && dbm == 27);

  Handler::Hooks none;
  FakeTransport t2;
  Handler h2(router, Rig::ident(), pos, none, 0, t2);
  auto& c2 = t2.add("ble");
  auto send2 = [&](const ToRadio& x) {
    Bytes f;
    frameTo(x, f);
    FrameReader in;
    in.push(f.data(), f.size());
    h2.receive(c2.conn, in, 1000);
    return FakeTransport::drain(c2);
  };
  m = {}, m.reqId = 1, m.kind = ToKind::Hello, m.protocolVersion = 1;
  send2(m);
  m = {}, m.reqId = 5, m.kind = ToKind::GetSettings;
  v = send2(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::UnknownRequest);
}

// SetTx (1.8): the app's transmit switch goes through the board's hook, and
// Status then reports it; a node without the hook says it has none.
static void testSetTx() {
  std::printf("client handler: SetTx\n");
  NullRadio radio;
  NullApp app;
  gw::Config cfg = Rig::mkCfg();
  gw::Router router(cfg, radio, app);
  gw::Position pos;
  bool tx = false, saveOk = true;
  int calls = 0;
  FakeTransport t;
  Handler::Hooks hooks;
  hooks.txOff = [&] { return !tx; };
  hooks.setTx = [&](bool on) {
    ++calls;
    tx = on;
    return saveOk;
  };
  Handler h(router, Rig::ident(), pos, hooks, 0, t);
  auto& c = t.add("ble");
  auto send = [&](const ToRadio& m) {
    Bytes f;
    frameTo(m, f);
    FrameReader in;
    in.push(f.data(), f.size());
    h.receive(c.conn, in, 1000);
    return FakeTransport::drain(c);
  };
  ToRadio m;
  m.reqId = 1, m.kind = ToKind::Hello, m.protocolVersion = 1;
  auto v = send(m);
  CHECK(v.size() == 1 && v[0].protocolMinor == 11);
  m = {}, m.reqId = 2, m.kind = ToKind::SetTx, m.on = true;
  v = send(m);
  CHECK(v.size() == 1 && v[0].kind == FromKind::Ok && v[0].reqId == 2 && tx && calls == 1);
  m = {}, m.reqId = 3, m.kind = ToKind::GetStatus;
  v = send(m);
  CHECK(v.size() == 1 && !v[0].status.txOff);
  saveOk = false;
  m = {}, m.reqId = 4, m.kind = ToKind::SetTx, m.on = false;
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::SendFailed && !tx);   // off now, but not saved: says so

  // LinkPing (1.9): a node not heard directly is refused, and the result
  // event carries both readings only when answered.
  m = {}, m.reqId = 6, m.kind = ToKind::LinkPing, m.nodeId = 0x77777777;
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::NotFound);
  m.nodeId = 0;
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadArgument);
  h.onLinkPing(0x77777777, true, -97, -101);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].kind == FromKind::LinkPingResult && v[0].answered && v[0].rssiDbm.has &&
        v[0].rssiDbm.v == -97 && v[0].reverseDbm.v == -101);
  h.onLinkPing(0x77777777, false, 0, 0);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && !v[0].answered && !v[0].rssiDbm.has && !v[0].reverseDbm.has);

  // Traceroute (1.10): any node, 1-8 hops; the result lists both ways.
  m = {}, m.reqId = 7, m.kind = ToKind::Traceroute, m.nodeId = 0x77777777, m.maxHops = 9;
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadArgument);
  m.maxHops = 300;
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadArgument);
  m.maxHops = 0, m.nodeId = 0;
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadArgument);
  m.nodeId = 0x77777777;   // not heard at all: still allowed, the flood may find it
  v = send(m);
  CHECK(v.size() == 1 && v[0].kind == FromKind::Ok && v[0].reqId == 7);
  v = send(m);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::RateLimited);   // one out at a time
  gw::TraceResult tr;
  tr.target = 0x77777777, tr.answered = true;
  tr.forward = {{0x11, -101}, {0x77777777, -95}};
  tr.back = {{0x11, -99}, {0x22, -103}};
  h.onTrace(tr);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].kind == FromKind::TraceResult && v[0].answered && v[0].nodeId == 0x77777777 &&
        v[0].fwdNodes == std::vector<uint32_t>({0x11, 0x77777777}) && v[0].fwdRssi == std::vector<int32_t>({-101, -95}) &&
        v[0].backNodes == std::vector<uint32_t>({0x11, 0x22}) && v[0].backRssi == std::vector<int32_t>({-99, -103}));
  h.onTrace(gw::TraceResult{0x77777777, false, {}, {}});
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && !v[0].answered && v[0].fwdNodes.empty() && v[0].backNodes.empty());

  Rig plain;   // ghostwaved and other nodes with no gate
  auto& pc = plain.t.add("tcp");
  plain.hello(pc);
  FakeTransport::drain(pc);
  ToRadio q;
  q.reqId = 5, q.kind = ToKind::SetTx, q.on = true;
  plain.req(pc, q);
  v = FakeTransport::drain(pc);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::UnknownRequest);
}

// The PIN handshake (protocol 1.2).
void testPin() {
  std::printf("client handler: PIN\n");
  // golden vector: the Dart app and gwclient.py check the same values
  {
    uint8_t nonce[16], a[32], b[32], ya[32], yb[32], sealedText[5 + 16];
    for (int i = 0; i < 16; ++i) nonce[i] = static_cast<uint8_t>(i);
    for (int i = 0; i < 32; ++i) a[i] = static_cast<uint8_t>(0x20 + i), b[i] = static_cast<uint8_t>(0x40 + i);
    gw::linkShare("424242", nonce, a, ya);
    gw::linkShare("424242", nonce, b, yb);
    gw::LinkKeys ka{}, kb{};
    CHECK(gw::linkKeys(a, yb, nonce, ya, yb, ka) && gw::linkKeys(b, ya, nonce, ya, yb, kb));
    CHECK(std::memcmp(&ka, &kb, sizeof ka) == 0);
    uint8_t other[32];
    gw::linkShare("000000", nonce, b, other);
    gw::LinkKeys wrong{};
    CHECK(gw::linkKeys(a, other, nonce, ya, other, wrong) && std::memcmp(wrong.confirm, ka.confirm, 32) != 0);
    gw::linkSeal(ka.clientToNode, 1, reinterpret_cast<const uint8_t*>("hello"), 5, sealedText);
    uint8_t opened[5];
    CHECK(gw::linkOpen(kb.clientToNode, 1, sealedText, sizeof sealedText, opened) && !std::memcmp(opened, "hello", 5));
    CHECK(!gw::linkOpen(kb.clientToNode, 2, sealedText, sizeof sealedText, opened));
    auto hex = [](const char* n, const uint8_t* p, size_t l) {
      std::printf("  %s ", n);
      for (size_t i = 0; i < l; ++i) std::printf("%02x", p[i]);
      std::printf("\n");
    };
    hex("server_share", ya, 32), hex("client_share", yb, 32), hex("c2s", ka.clientToNode, 32);
    hex("s2c", ka.nodeToClient, 32), hex("confirm", ka.confirm, 32), hex("sealed", sealedText, sizeof sealedText);
  }

  Rig r;
  uint8_t counter = 0;
  r.h.requirePin("424242", [&](uint8_t* p, size_t n) { std::memset(p, ++counter, n); });
  auto& c = r.t.add("tcp");
  struct Challenge { Bytes nonce, share; };
  struct Answer { Bytes share, proof; };
  auto hello = [&](uint64_t now, const Answer& a) {
    ToRadio m;
    m.reqId = 5, m.kind = ToKind::Hello, m.protocolVersion = 1, m.clientShare = a.share, m.pinProof = a.proof;
    r.req(c, m, now);
    return FakeTransport::drain(c);
  };
  auto challenge = [&](uint64_t now) {
    auto v = hello(now, {});
    CHECK(v.size() == 1 && v[0].kind == FromKind::PinChallenge && v[0].reqId == 5 && v[0].nonce.size() == 16 &&
          v[0].serverShare.size() == 32);
    return v.empty() ? Challenge{Bytes(16), Bytes(32)} : Challenge{v[0].nonce, v[0].serverShare};
  };
  auto answer = [&](const Challenge& ch, const std::string& pin) {
    Bytes secret(32, 0x77), share(32), proof(32);
    gw::linkShare(pin, ch.nonce.data(), secret.data(), share.data());
    gw::LinkKeys k{};
    CHECK(gw::linkKeys(secret.data(), ch.share.data(), ch.nonce.data(), ch.share.data(), share.data(), k));
    std::memcpy(proof.data(), k.confirm, 32);
    return Answer{share, proof};
  };

  r.h.onMessage(0xAAAA0001, 1, {'s', 'e', 'c', 'r', 'e', 't'});   // held for an authenticated client

  Challenge n = challenge(1000);
  CHECK(!c.conn.hello);
  ToRadio st;
  st.reqId = 6, st.kind = ToKind::GetStatus;
  r.req(c, st, 1000);
  auto v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].error == ErrorCode::NeedHello);   // a challenge opens nothing

  v = hello(1000, answer(n, "000000"));
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadPin && !c.conn.hello);
  // the nonce is spent: even the right PIN needs a new challenge (replay)
  v = hello(1000, answer(n, "424242"));
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadPin);
  CHECK(r.h.queued() == 1);   // nothing leaked

  // malformed proofs are wrong PINs, not crashes (third failure: 1 s lockout)
  n = challenge(1000);
  v = hello(1000, Answer{Bytes(3, 1), Bytes(5, 1)});
  CHECK(v.size() == 1 && v[0].error == ErrorCode::BadPin);
  n = challenge(1000);
  v = hello(1500, answer(n, "424242"));
  CHECK(v.size() == 1 && v[0].error == ErrorCode::RateLimited);   // locked, even with the right PIN
  // the lockout covers other connections too
  auto& c2 = r.t.add("tcp2");
  ToRadio h2;
  h2.reqId = 1, h2.kind = ToKind::Hello, h2.protocolVersion = 1;
  r.req(c2, h2, 1500);
  auto w = FakeTransport::drain(c2);
  CHECK(w.size() == 1 && w[0].kind == FromKind::PinChallenge);
  { auto an = answer({w[0].nonce, w[0].serverShare}, "424242"); h2.clientShare = an.share, h2.pinProof = an.proof; }
  r.req(c2, h2, 1500);
  w = FakeTransport::drain(c2);
  CHECK(w.size() == 1 && w[0].error == ErrorCode::RateLimited);

  n = challenge(2100);   // lockout over
  v = hello(2100, answer(n, "424242"));
  CHECK(v.size() >= 1 && v[0].kind == FromKind::NodeInfo && c.conn.hello && c.conn.secure);
  CHECK(v.size() == 2 && v[1].kind == FromKind::Text);   // held events only now
  r.req(c, st, 2100);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].kind == FromKind::Status);
  ToRadio again;   // a later Hello on an authenticated link (after a rename) needs no proof
  again.reqId = 9, again.kind = ToKind::Hello, again.protocolVersion = 1;
  r.req(c, again, 2200);
  v = FakeTransport::drain(c);
  CHECK(v.size() == 1 && v[0].kind == FromKind::NodeInfo);

  // once encrypted, a plain frame, a replay or a tampered frame ends the link
  auto sendRaw = [&](FakeTransport::C& to, const Bytes& f) {
    FrameReader in;
    in.push(f.data(), f.size());
    r.h.receive(to.conn, in, 2300);
  };
  {
    Bytes plain;
    frameTo(st, plain);
    auto& s1 = c;
    Bytes sealedFrame = Rig::sealed(s1, plain);
    sendRaw(s1, sealedFrame);
    auto ok = FakeTransport::drain(s1);
    CHECK(ok.size() == 1 && ok[0].kind == FromKind::Status && !s1.conn.closing);
    sendRaw(s1, sealedFrame);   // same counter value again
    CHECK(s1.conn.closing);
    CHECK(FakeTransport::drain(s1).empty());
  }
  auto secureConn = [&](const std::string& name, uint64_t t) -> FakeTransport::C& {
    auto& d = r.t.add(name);
    ToRadio m;
    m.kind = ToKind::Hello, m.protocolVersion = 1;
    r.req(d, m, t);
    auto got2 = FakeTransport::drain(d);
    auto an = answer({got2[0].nonce, got2[0].serverShare}, "424242");
    m.clientShare = an.share, m.pinProof = an.proof;
    r.req(d, m, t);
    FakeTransport::drain(d);
    CHECK(d.conn.secure);
    return d;
  };
  {
    auto& d = secureConn("plain-after", 2400);
    Bytes plain;
    frameTo(st, plain);
    sendRaw(d, plain);
    CHECK(d.conn.closing && FakeTransport::drain(d).empty());
    auto& e2 = secureConn("tamper", 2400);
    Bytes f;
    frameTo(st, f);
    f = Rig::sealed(e2, f);
    f.back() ^= 1;
    sendRaw(e2, f);
    CHECK(e2.conn.closing && FakeTransport::drain(e2).empty());
  }
  // a low-order share is a wrong PIN, and never yields keys
  {
    auto& d = r.t.add("low-order");
    ToRadio m;
    m.kind = ToKind::Hello, m.protocolVersion = 1;
    r.req(d, m, 2500);
    FakeTransport::drain(d);
    m.clientShare = Bytes(32, 0), m.pinProof = Bytes(32, 0);
    r.req(d, m, 2500);
    auto got3 = FakeTransport::drain(d);
    CHECK(got3.size() == 1 && got3[0].error == ErrorCode::BadPin && !d.conn.secure);
  }

  // lockouts double, capped at 5 minutes, and success resets the count
  uint64_t now = 10000;
  for (int i = 0; i < 12; ++i) {
    auto& d = r.t.add("x" + std::to_string(i));
    ToRadio bad;
    bad.kind = ToKind::Hello, bad.protocolVersion = 1;
    r.req(d, bad, now);
    auto got = FakeTransport::drain(d);
    { auto an = answer({got[0].nonce, got[0].serverShare}, "111111"); bad.clientShare = an.share, bad.pinProof = an.proof; }
    r.req(d, bad, now);
    got = FakeTransport::drain(d);
    CHECK(got.size() == 1 && got[0].error == ErrorCode::BadPin);
    now += 300001;
  }
  auto& e = r.t.add("late");
  ToRadio q;
  q.kind = ToKind::Hello, q.protocolVersion = 1;
  r.req(e, q, now - 1);
  auto got = FakeTransport::drain(e);
  { auto an = answer({got[0].nonce, got[0].serverShare}, "424242"); q.clientShare = an.share, q.pinProof = an.proof; }
  r.req(e, q, now - 1);
  got = FakeTransport::drain(e);
  CHECK(got.size() >= 1 && got[0].kind == FromKind::NodeInfo);   // 5 min cap held

  // without requirePin (BLE) Hello needs no proof
  Rig open;
  auto& oc = open.t.add("ble");
  open.hello(oc);
  auto ov = FakeTransport::drain(oc);
  CHECK(ov.size() == 1 && ov[0].kind == FromKind::NodeInfo);
}

void testBattery() {
  std::printf("client handler: Status battery\n");
  NullRadio radio;
  NullApp app;
  gw::Config cfg = Rig::mkCfg();
  gw::Router router(cfg, radio, app);
  gw::Position pos;
  auto status = [&](std::function<uint8_t()> battery) {
    FakeTransport t;
    Handler::Hooks hooks;
    hooks.batteryPct = battery;
    Handler h(router, Rig::ident(), pos, hooks, 0, t);
    auto& c = t.add("ble");
    auto send = [&](const ToRadio& m) {
      Bytes f;
      frameTo(m, f);
      FrameReader in;
      in.push(f.data(), f.size());
      h.receive(c.conn, in, 1000);
      return FakeTransport::drain(c);
    };
    ToRadio m;
    m.reqId = 1, m.kind = ToKind::Hello, m.protocolVersion = 1;
    send(m);
    m = {}, m.reqId = 2, m.kind = ToKind::GetStatus;
    auto v = send(m);
    CHECK(v.size() == 1 && v[0].kind == FromKind::Status);
    return v.empty() ? OptU32{} : v[0].status.batteryPct;
  };
  CHECK(!status(nullptr).has);
  CHECK(!status([] { return uint8_t(0xFF); }).has);
  OptU32 zero = status([] { return uint8_t(0); });
  CHECK(zero.has && zero.v == 0);
  OptU32 most = status([] { return uint8_t(87); });
  CHECK(most.has && most.v == 87);
  OptU32 over = status([] { return uint8_t(140); });
  CHECK(over.has && over.v == 100);
}

static void testStatusTxOff() {
  std::printf("client handler: Status tx_off\n");
  NullRadio radio;
  NullApp app;
  gw::Config cfg = Rig::mkCfg();
  gw::Router router(cfg, radio, app);
  gw::Position pos;
  auto txOff = [&](std::function<bool()> hook) {
    FakeTransport t;
    Handler::Hooks hooks;
    hooks.txOff = hook;
    Handler h(router, Rig::ident(), pos, hooks, 0, t);
    auto& c = t.add("ble");
    auto send = [&](const ToRadio& m) {
      Bytes f;
      frameTo(m, f);
      FrameReader in;
      in.push(f.data(), f.size());
      h.receive(c.conn, in, 1000);
      return FakeTransport::drain(c);
    };
    ToRadio m;
    m.reqId = 1, m.kind = ToKind::Hello, m.protocolVersion = 1;
    send(m);
    m = {}, m.reqId = 2, m.kind = ToKind::GetStatus;
    auto v = send(m);
    CHECK(v.size() == 1 && v[0].kind == FromKind::Status);
    return !v.empty() && v[0].status.txOff;
  };
  CHECK(!txOff(nullptr));
  CHECK(!txOff([] { return false; }));
  CHECK(txOff([] { return true; }));
}

int main() {
  testStatusTxOff();
  testHelloGate();
  testQueueAndReplay();
  testQueueEviction();
  testFanOut();
  testRequests();
  testBadFrames();
  testProtocol11();
  testSetTx();
  testSettings();
  testPin();
  testBattery();
  std::printf("client handler: %d passed, %d failed\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}
