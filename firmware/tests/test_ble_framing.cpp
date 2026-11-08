// Host tests for the BLE framing (docs/CLIENT_PROTOCOL.md "BLE transport"):
// FromRadio frames split into notifications by FrameChunker and rebuilt by a
// FrameReader on the app side, and ToRadio frames the app splits arbitrarily
// rebuilt by the node's FrameReader, at the MTUs phones actually negotiate.
#include <cstdio>
#include <cstring>
#include <random>
#include <vector>

#include "ghostwave/client_proto.h"
#include "ghostwave/frame_chunker.h"

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

// A few FromRadio frames of different sizes, the largest at kMaxFrame.
std::vector<Bytes> sampleFrames() {
  std::vector<Bytes> v;
  for (size_t textLen : {0u, 1u, 19u, 20u, 73u, 128u}) {
    FromRadio m;
    m.kind = FromKind::Text;
    m.src = 0xA1B2C3D4;
    m.msgId = static_cast<uint32_t>(textLen + 1);
    m.text.assign(textLen, static_cast<uint8_t>('a' + textLen % 26));
    Bytes f;
    if (frameFrom(m, f)) v.push_back(f);
  }
  // pad a body to exactly the 180-byte maximum
  Bytes body(kMaxBody - 1, 0x00);   // protobuf field 0 bytes are not valid, but framing does not care
  Bytes f;
  if (frame(body.data(), body.size(), f)) v.push_back(f);
  return v;
}

// Pushes frames through a chunker at `mtu`, reassembles, and checks.
void roundTrip(size_t mtu) {
  const size_t chunk = mtu - 3;
  auto frames = sampleFrames();
  CHECK(frames.size() == 7 && frames.back().size() == kMaxFrame);
  FrameChunker out(8 * 1024);
  for (auto& f : frames) CHECK(out.push(f.data(), f.size()));

  FrameReader app;
  std::vector<Bytes> got;
  size_t notifications = 0, frameIdx = 0, inFrame = 0;
  const uint8_t* p;
  size_t n;
  while (out.peek(chunk, p, n)) {
    CHECK(n > 0 && n <= chunk);
    // a notification never spans two frames
    CHECK(frameIdx < frames.size() && inFrame + n <= frames[frameIdx].size());
    if (frameIdx < frames.size()) {
      inFrame += n;
      if (inFrame == frames[frameIdx].size()) ++frameIdx, inFrame = 0;
    }
    app.push(p, n);
    out.pop(n);
    ++notifications;
    uint8_t ver;
    Bytes body;
    while (app.next(ver, body) == FrameReader::Result::Frame) {
      Bytes again;
      frame(body.data(), body.size(), again, ver);
      got.push_back(again);
    }
  }
  CHECK(got == frames);
  CHECK(out.pendingBytes() == 0 && out.pendingFrames() == 0);
  size_t expect = 0;
  for (auto& f : frames) expect += (f.size() + chunk - 1) / chunk;
  CHECK(notifications == expect);
  if (chunk >= kMaxFrame) CHECK(notifications == frames.size());   // one frame per notification
}

void testChunkerBasics() {
  FrameChunker c(100);
  const uint8_t a[60] = {1}, b[50] = {2};
  CHECK(c.push(a, sizeof a));
  CHECK(!c.push(b, sizeof b));   // 110 > 100: refused whole
  CHECK(c.pendingBytes() == 60 && c.pendingFrames() == 1);
  CHECK(!c.push(a, 0));

  const uint8_t* p;
  size_t n;
  CHECK(!c.peek(0, p, n));
  CHECK(c.peek(20, p, n) && n == 20 && p[0] == 1);
  // the stack refused it: nothing popped, the same piece comes back
  const uint8_t* p2;
  size_t n2;
  CHECK(c.peek(20, p2, n2) && p2 == p && n2 == 20);
  c.pop(20);
  CHECK(c.pendingBytes() == 40);
  CHECK(c.push(b, 50) && c.pendingBytes() == 90);
  CHECK(c.peek(100, p, n) && n == 40);   // stops at the frame end
  c.pop(1000);                            // clamped to the frame
  CHECK(c.pendingFrames() == 1 && c.pendingBytes() == 50);
  CHECK(c.peek(100, p, n) && n == 50 && p[0] == 2);
  c.clear();
  CHECK(!c.peek(100, p, n) && c.pendingBytes() == 0);
}

// The app splits ToRadio frames at arbitrary points (MTU 23 phones, or a
// client that writes byte by byte); the node rebuilds every one.
void testWritesSplitAnywhere() {
  std::vector<Bytes> sent;
  Bytes stream;
  for (int i = 0; i < 20; ++i) {
    ToRadio m;
    m.reqId = static_cast<uint32_t>(i + 1);
    m.kind = ToKind::SendText;
    m.dest = 0x01020304;
    m.text.assign(static_cast<size_t>(i * 3 % 74), 'q');
    Bytes f;
    CHECK(frameTo(m, f));
    sent.push_back(f);
    stream.insert(stream.end(), f.begin(), f.end());
  }
  std::mt19937 rng(42);
  for (size_t maxPiece : {1u, 2u, 20u, 64u, 182u, 244u}) {
    FrameReader node;
    std::vector<uint32_t> ids;
    size_t off = 0;
    while (off < stream.size()) {
      size_t n = 1 + rng() % maxPiece;
      if (n > stream.size() - off) n = stream.size() - off;
      node.push(stream.data() + off, n);
      off += n;
      uint8_t ver;
      Bytes body;
      while (node.next(ver, body) == FrameReader::Result::Frame) {
        ToRadio m;
        CHECK(ver == kProtocolVersion && decodeTo(body.data(), body.size(), m));
        ids.push_back(m.reqId);
      }
    }
    CHECK(ids.size() == sent.size());
    for (size_t i = 0; i < ids.size(); ++i) CHECK(ids[i] == i + 1);
    CHECK(node.buffered() == 0);
  }
}

}  // namespace

int main() {
  testChunkerBasics();
  for (size_t mtu : {23u, 27u, 64u, 100u, 185u, 247u, 517u}) roundTrip(mtu);
  testWritesSplitAnywhere();
  std::printf("ble framing: %d passed, %d failed\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}
