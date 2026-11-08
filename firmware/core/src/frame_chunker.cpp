#include "ghostwave/frame_chunker.h"

namespace gw {
namespace client {

bool FrameChunker::push(const uint8_t* frame, size_t n) {
  if (!frame || n == 0 || n > cap_ - bytes_ || bytes_ > cap_) return false;
  frames_.emplace_back(frame, frame + n);
  bytes_ += n;
  return true;
}

bool FrameChunker::peek(size_t maxChunk, const uint8_t*& p, size_t& n) const {
  if (frames_.empty() || maxChunk == 0) return false;
  const auto& f = frames_.front();
  size_t left = f.size() - off_;
  n = left < maxChunk ? left : maxChunk;
  p = f.data() + off_;
  return true;
}

void FrameChunker::pop(size_t n) {
  if (frames_.empty()) return;
  size_t left = frames_.front().size() - off_;
  if (n > left) n = left;
  off_ += n;
  bytes_ -= n;
  if (off_ == frames_.front().size()) {
    frames_.pop_front();
    off_ = 0;
  }
}

void FrameChunker::clear() {
  frames_.clear();
  off_ = 0;
  bytes_ = 0;
}

}  // namespace client
}  // namespace gw
