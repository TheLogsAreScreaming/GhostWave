// Outgoing side of a packet transport with a small payload (BLE notifications,
// docs/CLIENT_PROTOCOL.md "BLE transport"): holds whole client-link frames and
// hands them out in pieces of at most `maxChunk` bytes. A piece never spans
// two frames, so at ATT MTU >= 183 every notification is exactly one frame;
// below that a frame goes out in several pieces and the app reassembles it by
// the length prefix (FrameReader does the same on the node for writes).
//
// peek() / pop() are split so a piece the radio stack refuses (no buffer)
// stays queued for the next try. Portable, no locking.
#pragma once

#include <cstddef>
#include <cstdint>
#include <deque>
#include <vector>

namespace gw {
namespace client {

class FrameChunker {
 public:
  explicit FrameChunker(size_t capacityBytes) : cap_(capacityBytes) {}

  // Queues one whole frame. False (nothing queued) if it would exceed the
  // capacity or is empty.
  bool push(const uint8_t* frame, size_t n);
  // The next piece: at most `maxChunk` bytes, all from the front frame.
  // False when empty or maxChunk is 0.
  bool peek(size_t maxChunk, const uint8_t*& p, size_t& n) const;
  // Drops the first `n` bytes of the front frame (n from the last peek).
  void pop(size_t n);

  size_t pendingBytes() const { return bytes_; }
  size_t pendingFrames() const { return frames_.size(); }
  void clear();

 private:
  size_t cap_;
  std::deque<std::vector<uint8_t>> frames_;
  size_t off_ = 0;     // bytes of frames_.front() already handed out
  size_t bytes_ = 0;   // unsent bytes in total
};

}  // namespace client
}  // namespace gw
