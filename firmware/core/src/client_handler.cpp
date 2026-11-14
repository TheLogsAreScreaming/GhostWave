// Transport-independent client link: request handling and the event queue
// (docs/CLIENT_PROTOCOL.md §4–§6).
#include "ghostwave/client_handler.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

#include "ghostwave/crypto.h"

namespace gw {
namespace client {

namespace {

Pos toPos(const gw::Position& p) { return posFromDegrees(p.lat, p.lon, p.valid); }

gw::Position fromPos(const Pos& p) { return {latDeg(p), lonDeg(p), p.valid}; }

bool usableDest(uint32_t id) { return id != 0 && id != gw::kBroadcast; }
constexpr uint64_t kRequestKeyGapMs = 30 * 1000;   // RequestKey: IDENT costs airtime

std::string hex8(uint32_t v) {
  char b[9];
  std::snprintf(b, sizeof b, "%08x", static_cast<unsigned>(v));
  return b;
}

}  // namespace

Handler::Handler(gw::Router& router, const NodeIdentity& self, const gw::Position& pos, Hooks hooks,
                 uint64_t startMs, Transport& transport, size_t queueMax)
    : r_(router),
      self_(self),
      pos_(pos),
      hooks_(std::move(hooks)),
      startMs_(startMs),
      t_(transport),
      queueMax_(queueMax ? queueMax : 1) {}

void Handler::receive(Conn& c, FrameReader& in, uint64_t now) {
  uint8_t ver;
  Bytes body;
  while (!c.closing) {
    auto res = in.next(ver, body);
    if (res == FrameReader::Result::None) return;
    if (res == FrameReader::Result::BadLength) {
      error(c, 0, ErrorCode::BadFrame, "frame length too long or zero");
      continue;
    }
    if (c.secure) {
      // nothing unsealed is accepted once the link is encrypted: a bad frame
      // means tampering or a lost sync, and either way the link is over
      Bytes plain(body.size() < gw::kLinkTagSize ? 0 : body.size() - gw::kLinkTagSize);
      if (ver != kSecureVersion || !gw::linkOpen(c.rxKey.data(), c.rxSeq, body.data(), body.size(), plain.data())) {
        t_.log("client " + c.peer + " sent a frame that failed the link check");
        c.closing = true;
        return;
      }
      ++c.rxSeq;
      body = std::move(plain);
    } else if (ver != kProtocolVersion) {
      error(c, 0, ErrorCode::BadVersion, "this node speaks client protocol version 1");
      c.closing = true;
      return;
    }
    ToRadio m;
    if (!decodeTo(body.data(), body.size(), m)) {
      error(c, 0, ErrorCode::BadFrame, "undecodable ToRadio");
      continue;
    }
    handle(c, m, now);
  }
}

size_t Handler::ready() {
  size_t n = 0;
  t_.forEachConn([&n](Conn& c) {
    if (c.hello && !c.closing) ++n;
  });
  return n;
}

void Handler::send(Conn& c, const FromRadio& m) {
  Bytes f;
  if (!frameFrom(m, f)) {
    // only a too-long event (cannot happen for v1 messages); say so instead
    FromRadio e;
    e.reqId = m.reqId;
    e.kind = FromKind::Error;
    e.error = ErrorCode::TooLong;
    e.detail = "reply too long for a frame";
    frameFrom(e, f);
  }
  if (f.empty()) return;
  if (c.secure) {
    size_t pb = f.size() - kFrameHeader - 1, len = 1 + pb + gw::kLinkTagSize;
    Bytes s(kFrameHeader + len);
    s[0] = kMagic0, s[1] = kMagic1, s[2] = static_cast<uint8_t>(len & 0xFF), s[3] = static_cast<uint8_t>(len >> 8);
    s[kFrameHeader] = kSecureVersion;
    gw::linkSeal(c.txKey.data(), c.txSeq++, f.data() + kFrameHeader + 1, pb, s.data() + kFrameHeader + 1);
    f = std::move(s);
  }
  t_.write(c, f.data(), f.size());
}

void Handler::reply(Conn& c, uint32_t reqId, FromKind kind) {
  FromRadio m;
  m.reqId = reqId;
  m.kind = kind;
  send(c, m);
}

void Handler::error(Conn& c, uint32_t reqId, ErrorCode code, const std::string& detail) {
  FromRadio m;
  m.reqId = reqId;
  m.kind = FromKind::Error;
  m.error = code;
  m.detail = detail;
  send(c, m);
}

void Handler::handle(Conn& c, const ToRadio& m, uint64_t now) {
  const uint32_t req = m.reqId;
  if (m.kind == ToKind::None) {
    error(c, req, ErrorCode::UnknownRequest, "unknown request (newer client?)");
    return;
  }
  if (!c.hello && m.kind != ToKind::Hello) {
    error(c, req, ErrorCode::NeedHello, "send Hello first");
    return;
  }
  if (handleV11(c, m, now)) return;
  switch (m.kind) {
    case ToKind::Hello: {
      if (m.protocolVersion != kProtocolVersion) {
        error(c, req, ErrorCode::BadVersion, "this node speaks client protocol version 1");
        c.closing = true;
        return;
      }
      if (!pin_.empty() && !c.hello && !checkPin(c, m, now)) return;
      FromRadio info;
      info.reqId = req;
      info.kind = FromKind::NodeInfo;
      info.protocolVersion = kProtocolVersion;
      info.nodeId = self_.id;
      info.name = self_.name;
      if (!self_.legacy) info.ed25519Pub.assign(self_.edPub.begin(), self_.edPub.end());
      info.x25519Pub.assign(self_.xPub.begin(), self_.xPub.end());
      info.legacy = self_.legacy;
      info.firmware = self_.firmware;
      info.maxTextBytes = kMaxTextBytes;
      info.protocolMinor = kProtocolMinor;
      info.maxChannelTextBytes = hooks_.channels ? static_cast<uint32_t>(gw::Router::kChannelPayloadMax) : 0;
      send(c, info);
      bool first = !c.hello;
      c.hello = true;
      std::string who;
      for (unsigned char ch : m.clientName.substr(0, 32)) who += (ch >= 0x20 && ch < 0x7F) ? static_cast<char>(ch) : '?';
      t_.log("client " + c.peer + " hello \"" + who + "\"" +
             (first && !queue_.empty() ? ", replaying " + std::to_string(queue_.size()) + " held events" : ""));
      if (first) {
        for (auto& ev : queue_) send(c, ev);
        queue_.clear();
      }
      return;
    }
    case ToKind::SendText: {
      if (!usableDest(m.dest) || m.dest == self_.id) {
        error(c, req, ErrorCode::BadArgument, "bad dest");
        return;
      }
      if (m.text.empty()) {
        error(c, req, ErrorCode::BadArgument, "empty text");
        return;
      }
      if (m.text.size() > kMaxTextBytes) {
        error(c, req, ErrorCode::TooLong, "text over " + std::to_string(kMaxTextBytes) + " bytes");
        return;
      }
      if (!r_.canSealTo(m.dest)) {
        // never in the clear: ask for its key, and let the app retry once it arrives
        if (!r_.identAskedWithin(m.dest, now, kRequestKeyGapMs)) r_.requestIdent(m.dest, now);
        error(c, req, ErrorCode::NoKey, "no key for this node yet; asked for it");
        return;
      }
      uint32_t mid = r_.send(m.dest, m.text, now);
      if (!mid) {
        error(c, req, ErrorCode::SendFailed, "router refused the message");
        return;
      }
      if (clientIds_.size() >= 256) {
        clientIds_.erase(clientIdOrder_.front());
        clientIdOrder_.pop_front();
      }
      clientIds_[mid] = m.clientMsgId;
      clientIdOrder_.push_back(mid);
      t_.log("client queued id " + hex8(mid) + " -> " + hex8(m.dest));
      FromRadio q;
      q.reqId = req;
      q.kind = FromKind::SendQueued;
      q.dest = m.dest;
      q.msgId = mid;
      q.clientMsgId = m.clientMsgId;
      send(c, q);
      return;
    }
    case ToKind::AddContact: {
      if (m.name.size() > 32) {
        error(c, req, ErrorCode::BadArgument, "name over 32 bytes");
        return;
      }
      std::string err;
      uint32_t id = hooks_.addPeer ? hooks_.addPeer(m.nodeId, m.ed25519Pub, m.x25519Pub, err) : 0;
      if (!id) {
        error(c, req, ErrorCode::KeyRejected, err);
        return;
      }
      if (!m.name.empty()) r_.setPeerName(id, m.name);
      if (m.ed25519Pub.size() == 32) r_.setPeerEdPub(id, m.ed25519Pub.data());   // lets us check its SOS cancels
      t_.log("client added contact " + hex8(id));
      reply(c, req, FromKind::Ok);
      return;
    }
    case ToKind::ListContacts: {
      auto peers = r_.peerList();
      for (auto& p : peers) {
        FromRadio ct;
        ct.reqId = req;
        ct.kind = FromKind::Contact;
        ct.nodeId = p.id;
        ct.name = p.name;
        ct.x25519Pub.assign(p.xPub.begin(), p.xPub.end());
        ct.pinned = p.pinned;
        if (p.hasEdPub) {
          ct.ed25519Pub.assign(p.edPub.begin(), p.edPub.end());
        } else if (hooks_.edKeys) {
          auto it = hooks_.edKeys->find(p.id);
          if (it != hooks_.edKeys->end()) {
            uint8_t x[32];
            gw::ed25519ToX25519(it->second.data(), x);
            if (std::memcmp(x, p.xPub.data(), 32) == 0) ct.ed25519Pub.assign(it->second.begin(), it->second.end());
          }
        }
        send(c, ct);
      }
      FromRadio end;
      end.reqId = req;
      end.kind = FromKind::ContactsEnd;
      end.count = static_cast<uint32_t>(peers.size());
      send(c, end);
      return;
    }
    case ToKind::SetKnownPosition:
      if (!usableDest(m.nodeId) || !m.pos.valid) {
        error(c, req, ErrorCode::BadArgument, "need node_id and pos");
        return;
      }
      r_.addKnownPosition(m.nodeId, fromPos(m.pos), now);
      reply(c, req, FromKind::Ok);
      return;
    case ToKind::SosStart: {
      std::string text(m.text.begin(), m.text.end());
      uint8_t batt = m.batteryPct.has ? static_cast<uint8_t>(std::min<uint32_t>(m.batteryPct.v, 100)) : 0xFF;
      // 4 m steps; 0xFF = unknown, so cap at 0xFE (1016 m)
      uint8_t acc = m.accuracyM.has ? static_cast<uint8_t>(std::min<uint32_t>((m.accuracyM.v + 3) / 4, 0xFE)) : 0xFF;
      if (!r_.startSos(text, batt, acc, now)) {
        error(c, req, ErrorCode::RateLimited, "SOS rate limited, try again in a minute");
        return;
      }
      t_.log("client SOS on");
      reply(c, req, FromKind::Ok);
      return;
    }
    case ToKind::SosStop:
      r_.stopSos(now);
      t_.log("client SOS off");
      reply(c, req, FromKind::Ok);
      return;
    case ToKind::SosAck:
      if (!r_.ackSos(m.nodeId, now)) {
        error(c, req, ErrorCode::NotFound, "no SOS held from that node");
        return;
      }
      reply(c, req, FromKind::Ok);
      return;
    case ToKind::GetStatus: {
      auto& s = r_.stats();
      FromRadio st;
      st.reqId = req;
      st.kind = FromKind::Status;
      st.status.tx = s.tx;
      st.status.rx = s.rx;
      st.status.rxBad = s.rxBad;
      st.status.rxAuthFail = s.rxAuthFail;
      st.status.delivered = s.delivered;
      st.status.forwarded = s.forwarded;
      st.status.stored = s.stored;
      st.status.airMs = s.airMs;
      st.status.storeSize = static_cast<uint32_t>(r_.storeSize());
      st.status.neighbors = static_cast<uint32_t>(r_.neighborCount(now));
      st.status.sosHeld = static_cast<uint32_t>(r_.sosCount());
      st.status.sosActive = r_.sosActive();
      st.status.uptimeS = static_cast<uint32_t>((now - startMs_) / 1000);
      st.status.clients = static_cast<uint32_t>(ready());
      st.status.queued = static_cast<uint32_t>(queue_.size());
      int dbm = 0;
      uint64_t at = 0;
      if (r_.lastHeard(dbm, at)) {
        st.status.lastRssiDbm.set(dbm);
        st.status.lastHeardS.set(static_cast<uint32_t>((now > at ? now - at : 0) / 1000));
      }
      if (hooks_.batteryPct) {
        const uint8_t pct = hooks_.batteryPct();
        if (pct != 0xFF) st.status.batteryPct.set(std::min<uint8_t>(pct, 100));
      }
      if (hooks_.txOff) st.status.txOff = hooks_.txOff();
      send(c, st);
      return;
    }
    case ToKind::GetPosition: {
      FromRadio p;
      p.reqId = req;
      p.kind = FromKind::Position;
      p.pos = toPos(pos_);
      send(c, p);
      return;
    }
    case ToKind::SetOwnPosition:
      if (hooks_.setOwnPosition) hooks_.setOwnPosition(fromPos(m.pos));
      reply(c, req, FromKind::Ok);
      return;
    default:
      error(c, req, ErrorCode::UnknownRequest, "unknown request");
      return;
  }
}

// ------------------------------------------------------------------ events --

void Handler::event(const FromRadio& m, bool hold) {
  if (ready()) {
    t_.forEachConn([&](Conn& c) {
      if (c.hello && !c.closing) send(c, m);
    });
    return;
  }
  if (!hold || !t_.holdEvents()) return;
  if (queue_.size() >= queueMax_) {
    // make room: the oldest non-SOS event goes first
    auto victim = std::find_if(queue_.begin(), queue_.end(), [](const FromRadio& e) { return e.kind != FromKind::Sos; });
    queue_.erase(victim != queue_.end() ? victim : queue_.begin());
  }
  FromRadio held = m;
  held.replayed = true;
  queue_.push_back(std::move(held));
}

void Handler::onMessage(uint32_t src, uint32_t msgId, const std::vector<uint8_t>& payload) {
  FromRadio m;
  m.kind = FromKind::Text;
  m.src = src;
  m.msgId = msgId;
  m.text = payload;
  if (m.text.size() > 128) m.text.resize(128);   // cannot happen: radio frames are 128 bytes
  stampSignal(m);
  event(m, true);
}

void Handler::onDelivered(uint32_t dst, uint32_t msgId) {
  FromRadio m;
  m.kind = FromKind::Delivered;
  m.dest = dst;
  m.msgId = msgId;
  auto it = clientIds_.find(msgId);
  if (it != clientIds_.end()) m.clientMsgId = it->second;   // kept: a receipt can arrive twice
  stampSignal(m);
  event(m, true);
}

void Handler::onSos(const gw::SosInfo& s) {
  FromRadio m;
  m.kind = FromKind::Sos;
  m.src = s.src;
  m.seq = s.seq;
  m.pos = toPos(s.pos);
  if (s.accuracy != 0xFF) m.accuracyM.set(s.accuracy * 4u);
  if (s.battery != 0xFF) m.batteryPct.set(s.battery);
  m.text.assign(s.text.begin(), s.text.end());
  event(m, true);
}

void Handler::onSosAck(uint32_t responder, uint16_t seq) {
  FromRadio m;
  m.kind = FromKind::SosAck;
  m.src = responder;
  m.seq = seq;
  event(m, true);
}

void Handler::onSosCancelled(uint32_t src, uint16_t seq, bool verified) {
  FromRadio m;
  m.kind = FromKind::SosCancelled;
  m.src = src;
  m.seq = seq;
  m.verified = verified;
  event(m, true);
}

void Handler::onPeerIdent(uint32_t id, const std::string& name, bool firstSeen) {
  FromRadio m;
  m.kind = FromKind::PeerIdent;
  m.nodeId = id;
  m.name = name;
  m.isNew = firstSeen;
  uint8_t ed[32];
  if (r_.peerEdPub(id, ed)) m.ed25519Pub.assign(ed, ed + 32);
  event(m, true);
}

void Handler::onKeyChange(uint32_t id, const uint8_t edPub[32], const std::string& name) {
  FromRadio m;
  m.kind = FromKind::KeyChange;
  m.nodeId = id;
  m.ed25519Pub.assign(edPub, edPub + 32);
  m.name = name;
  event(m, true);
}

void Handler::onLinkPing(uint32_t node, bool answered, int forwardDbm, int reverseDbm) {
  FromRadio m;
  m.kind = FromKind::LinkPingResult;
  m.nodeId = node;
  m.answered = answered;
  if (answered) {
    m.rssiDbm.set(forwardDbm);
    m.reverseDbm.set(reverseDbm);
  }
  event(m, false);   // a stale result is useless: not held for a later app
}

void Handler::onTrace(const gw::TraceResult& r) {
  FromRadio m;
  m.kind = FromKind::TraceResult;
  m.nodeId = r.target;
  m.answered = r.answered;
  for (const auto& h : r.forward) m.fwdNodes.push_back(h.node), m.fwdRssi.push_back(h.rssiDbm);
  for (const auto& h : r.back) m.backNodes.push_back(h.node), m.backRssi.push_back(h.rssiDbm);
  event(m, false);   // a stale result is useless: not held for a later app
}

namespace {
// NodeTelemetry with only what the node reported (unknown fields absent).
FromRadio telemetryMsg(uint32_t id, const gw::Telemetry& t, uint32_t ageS) {
  FromRadio m;
  m.kind = FromKind::NodeTelemetry;
  m.nodeId = id;
  if (t.batteryPct <= 100) m.batteryPct.set(t.batteryPct);
  if (t.batteryMv) m.batteryMv.set(t.batteryMv);
  if (t.uptimeS != gw::Telemetry::kNoUptime) m.uptimeS.set(t.uptimeS);
  m.ageS = ageS;
  return m;
}
}  // namespace

void Handler::onTelemetry(uint32_t id, const gw::Telemetry& t) {
  FromRadio m = telemetryMsg(id, t, 0);
  stampSignal(m);
  event(m, false);   // live view only; GetTelemetry catches up
}

void Handler::onNeighbor(uint32_t id, const gw::Position& pos, bool isNew) {
  FromRadio m;
  m.kind = FromKind::Neighbor;
  m.nodeId = id;
  m.pos = toPos(pos);
  m.isNew = isNew;
  stampSignal(m);
  event(m, false);   // live view only: a stale neighbor list is worse than none
}


// ----------------------------------------------------- protocol 1.2 (PIN) --

void Handler::requirePin(const std::string& pin, std::function<void(uint8_t*, size_t)> random) {
  pin_ = pin;
  random_ = std::move(random);
}

bool Handler::checkPin(Conn& c, const ToRadio& m, uint64_t now) {
  const uint32_t req = m.reqId;
  if (m.pinProof.empty()) {   // first Hello: send a challenge
    random_(c.pinNonce.data(), c.pinNonce.size());
    random_(c.pakeSecret.data(), c.pakeSecret.size());
    gw::linkShare(pin_, c.pinNonce.data(), c.pakeSecret.data(), c.serverShare.data());
    c.pinNonceSet = true;
    FromRadio f;
    f.reqId = req;
    f.kind = FromKind::PinChallenge;
    f.nonce.assign(c.pinNonce.begin(), c.pinNonce.end());
    f.serverShare.assign(c.serverShare.begin(), c.serverShare.end());
    send(c, f);
    return false;
  }
  // Wrong guesses are counted across connections, so reconnecting does not
  // reset them. The third in a row starts a lockout: 1 s, doubling, at most 5 min.
  if (now < pinLockUntil_) {
    c.pinNonceSet = false;
    error(c, req, ErrorCode::RateLimited,
          "too many wrong PINs, try again in " + std::to_string((pinLockUntil_ - now) / 1000 + 1) + " s");
    return false;
  }
  bool good = false;
  gw::LinkKeys keys{};
  if (c.pinNonceSet && m.clientShare.size() == gw::kKeySize && m.pinProof.size() == gw::kPinProofSize) {
    good = gw::linkKeys(c.pakeSecret.data(), m.clientShare.data(), c.pinNonce.data(), c.serverShare.data(),
                        m.clientShare.data(), keys) &&
           gw::pinProofEqual(keys.confirm, m.pinProof.data());
  }
  c.pinNonceSet = false;   // each nonce works once
  gw::wipe(c.pakeSecret.data(), c.pakeSecret.size());
  if (good) {
    pinFails_ = 0;
    std::memcpy(c.rxKey.data(), keys.clientToNode, c.rxKey.size());
    std::memcpy(c.txKey.data(), keys.nodeToClient, c.txKey.size());
    c.rxSeq = c.txSeq = 0;
    c.secure = true;   // from here on, NodeInfo included
    gw::wipe(&keys, sizeof keys);
    return true;
  }
  gw::wipe(&keys, sizeof keys);
  ++pinFails_;
  if (pinFails_ >= 3) {
    uint32_t shift = std::min<uint32_t>(pinFails_ - 3, 9);
    pinLockUntil_ = now + std::min<uint64_t>(1000ull << shift, 300000);
  }
  t_.log("client " + c.peer + " sent a wrong PIN");
  error(c, req, ErrorCode::BadPin, "wrong PIN");
  return false;
}

// ------------------------------------------------- protocol 1.1 (channels) --

bool Handler::handleV11(Conn& c, const ToRadio& m, uint64_t now) {
  const uint32_t req = m.reqId;
  gw::ChannelBook* ch = hooks_.channels;
  using R = gw::ChannelBook::Result;
  switch (m.kind) {
    case ToKind::SendChannelText:
    case ToKind::AddChannel:
    case ToKind::RemoveChannel:
    case ToKind::ListChannels:
      if (!ch) {
        error(c, req, ErrorCode::UnknownRequest, "group channels are not available on this node");
        return true;
      }
      break;
    case ToKind::SetName:
    case ToKind::RequestKey:
    case ToKind::SetTx:
    case ToKind::LinkPing:
    case ToKind::Traceroute:
    case ToKind::GetTelemetry: break;
    default: return false;
  }
  switch (m.kind) {
    case ToKind::SendChannelText: {
      const gw::ChannelBook::Entry* e = ch->byName(m.channel);
      if (!e) {
        error(c, req, ErrorCode::NotFound, "no such channel");
      } else if (m.text.empty()) {
        error(c, req, ErrorCode::BadArgument, "empty text");
      } else if (m.text.size() > gw::Router::kChannelPayloadMax) {
        error(c, req, ErrorCode::TooLong, "text over " + std::to_string(gw::Router::kChannelPayloadMax) + " bytes");
      } else if (uint32_t mid = r_.sendChannel(e->id, m.text, now); !mid) {
        error(c, req, ErrorCode::SendFailed, "router refused the message");
      } else {
        char id[9];
        std::snprintf(id, sizeof id, "%08x", mid);
        t_.log(std::string("client channel message ") + id + " -> #" + e->name);
        FromRadio q;
        q.reqId = req;
        q.kind = FromKind::SendQueued;
        q.dest = gw::kBroadcast;
        q.msgId = mid;
        q.clientMsgId = m.clientMsgId;
        send(c, q);
      }
      return true;
    }
    case ToKind::AddChannel: {
      R r = ch->add(m.channel, m.psk.data(), m.psk.size());
      if (r == R::Ok || r == R::Unchanged) {
        if (r == R::Ok) t_.log("client joined channel #" + m.channel);
        reply(c, req, FromKind::Ok);
      } else {
        error(c, req, r == R::Full ? ErrorCode::ChannelLimit : r == R::IoError ? ErrorCode::SendFailed
                                                                                : ErrorCode::BadArgument,
              gw::ChannelBook::describe(r));
      }
      return true;
    }
    case ToKind::RemoveChannel: {
      R r = ch->remove(m.channel);
      if (r == R::Ok) {
        t_.log("client left channel #" + m.channel);
        reply(c, req, FromKind::Ok);
      } else {
        error(c, req, r == R::NotFound ? ErrorCode::NotFound : ErrorCode::SendFailed, gw::ChannelBook::describe(r));
      }
      return true;
    }
    case ToKind::ListChannels: {
      for (auto& e : ch->list()) {
        FromRadio f;
        f.reqId = req;
        f.kind = FromKind::Channel;
        f.channel = e.name;
        f.psk.assign(e.key.begin(), e.key.end());
        send(c, f);
      }
      FromRadio end;
      end.reqId = req;
      end.kind = FromKind::ChannelsEnd;
      end.count = static_cast<uint32_t>(ch->list().size());
      send(c, end);
      return true;
    }
    case ToKind::SetName: {
      if (!hooks_.setName) {
        error(c, req, ErrorCode::NoIdentity, "this node cannot be renamed from the app");
        return true;
      }
      std::string err;
      ErrorCode code = hooks_.setName(m.name, err);
      if (code != ErrorCode::None) {
        error(c, req, code, err.empty() ? "cannot rename this node" : err);
        return true;
      }
      self_.name = m.name;
      reply(c, req, FromKind::Ok);
      return true;
    }
    case ToKind::LinkPing: {
      using PR = gw::Router::PingResult;
      switch (r_.linkPing(m.nodeId, now)) {
        case PR::Sent: reply(c, req, FromKind::Ok); break;
        case PR::Busy: error(c, req, ErrorCode::RateLimited, "a ping is already out; wait for its result"); break;
        case PR::TooSoon: error(c, req, ErrorCode::RateLimited, "one ping every 5 seconds"); break;
        case PR::NotNeighbor: error(c, req, ErrorCode::NotFound, "not heard directly: a link ping is one hop"); break;
        case PR::BadNode: error(c, req, ErrorCode::BadArgument, "bad node ID"); break;
      }
      return true;
    }
    case ToKind::Traceroute: {
      using TS = gw::Router::TraceStart;
      if (m.maxHops > 255) {
        error(c, req, ErrorCode::BadArgument, "max_hops is 1 to 8");
        return true;
      }
      switch (r_.traceroute(m.nodeId, static_cast<uint8_t>(m.maxHops), now)) {
        case TS::Sent: reply(c, req, FromKind::Ok); break;
        case TS::Busy: error(c, req, ErrorCode::RateLimited, "a trace is already out; wait for its result"); break;
        case TS::TooSoon: error(c, req, ErrorCode::RateLimited, "one trace every 30 seconds"); break;
        case TS::BadHops: error(c, req, ErrorCode::BadArgument, "max_hops is 1 to 8"); break;
        case TS::BadNode: error(c, req, ErrorCode::BadArgument, "bad node ID"); break;
      }
      return true;
    }
    case ToKind::GetTelemetry: {
      gw::Telemetry t;
      uint64_t heard = now;
      bool own = m.nodeId == self_.id;
      if (!usableDest(m.nodeId) && !own) {
        error(c, req, ErrorCode::BadArgument, "bad node ID");
      } else if (own ? !r_.ownTelemetry(now, t) : !r_.neighborTelemetry(m.nodeId, t, heard)) {
        error(c, req, ErrorCode::NotFound,
              own ? "this node reports no telemetry" : "no telemetry heard from that node");
      } else {
        FromRadio q = telemetryMsg(m.nodeId, t, static_cast<uint32_t>((now > heard ? now - heard : 0) / 1000));
        q.reqId = req;
        send(c, q);
      }
      return true;
    }
    case ToKind::SetTx: {
      if (!hooks_.setTx) {
        error(c, req, ErrorCode::UnknownRequest, "this node has no transmit switch");
        return true;
      }
      if (!hooks_.setTx(m.on)) {
        error(c, req, ErrorCode::SendFailed, "could not save the setting");
        return true;
      }
      t_.log(std::string("client turned transmit ") + (m.on ? "on" : "off"));
      reply(c, req, FromKind::Ok);
      return true;
    }
    case ToKind::RequestKey: {
      if (!usableDest(m.nodeId) || m.nodeId == self_.id) {
        error(c, req, ErrorCode::BadArgument, "bad node ID");
        return true;
      }
      if (r_.hasPeerKey(m.nodeId)) {   // nothing to ask; ListContacts has it
        reply(c, req, FromKind::Ok);
        return true;
      }
      if (r_.identAskedWithin(m.nodeId, now, kRequestKeyGapMs)) {
        error(c, req, ErrorCode::RateLimited, "asked for this key moments ago");
        return true;
      }
      if (!r_.requestIdent(m.nodeId, now)) {
        error(c, req, ErrorCode::NoIdentity, "this node cannot ask for a key");
        return true;
      }
      t_.log("client asked for the key of " + hex8(m.nodeId));
      reply(c, req, FromKind::Ok);
      return true;
    }
    default: return false;
  }
}

void Handler::onChannelMessage(uint32_t chanId, uint32_t src, uint32_t msgId, const std::vector<uint8_t>& payload) {
  const gw::ChannelBook::Entry* e = hooks_.channels ? hooks_.channels->byId(chanId) : nullptr;
  if (!e) return;
  FromRadio m;
  m.kind = FromKind::ChannelMessage;
  m.channel = e->name;
  m.src = src;
  m.msgId = msgId;
  m.text = payload;
  stampSignal(m);
  event(m, true);
}

void Handler::stampSignal(FromRadio& m) const {
  int dbm = 0;
  if (r_.rxSignal(dbm)) m.rssiDbm.set(dbm);
}

}  // namespace client
}  // namespace gw
