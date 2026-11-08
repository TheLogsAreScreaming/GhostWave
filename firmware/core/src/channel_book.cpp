#include "ghostwave/channel_book.h"

#include <cstring>

#include "ghostwave/crypto.h"

namespace gw {

ChannelBook::~ChannelBook() {
  for (auto& c : chans_) wipe(c.key.data(), c.key.size());
}

bool ChannelBook::validName(const std::string& name) {
  if (name.empty() || name.size() > kNameMax) return false;
  for (unsigned char c : name)
    if (c < 0x20 || c == 0x7F) return false;   // control bytes, tab, newline: not in a name
  return true;
}

const char* ChannelBook::describe(Result r) {
  switch (r) {
    case Result::Ok: return "ok";
    case Result::Unchanged: return "already joined";
    case Result::BadName: return "channel name must be 1-16 bytes, no control characters";
    case Result::BadKey: return "channel key must be 32 bytes";
    case Result::NameTaken: return "a channel with that name uses another key";
    case Result::KeyTaken: return "that key is already joined under another name";
    case Result::Full: return "the node holds the most channels it can";
    case Result::NotFound: return "no such channel";
    case Result::IoError: return "could not save the channel list";
  }
  return "?";
}

ChannelBook::Result ChannelBook::join(const std::string& name, const uint8_t* key, size_t keyLen) {
  if (!validName(name)) return Result::BadName;
  if (keyLen != 32) return Result::BadKey;
  uint32_t id = groupChannelId(key);
  const Entry* byN = byName(name);
  if (byN) return byN->id == id ? Result::Unchanged : Result::NameTaken;
  if (byId(id)) return Result::KeyTaken;
  if (chans_.size() >= kMaxGroupChannels || !r_.addGroupChannel(key)) return Result::Full;
  Entry e;
  e.name = name;
  std::memcpy(e.key.data(), key, 32);
  e.id = id;
  chans_.push_back(e);
  return Result::Ok;
}

ChannelBook::Result ChannelBook::restore(const std::string& name, const uint8_t key[32]) {
  return join(name, key, 32);
}

ChannelBook::Result ChannelBook::add(const std::string& name, const uint8_t* key, size_t keyLen) {
  Result r = join(name, key, keyLen);
  if (r != Result::Ok) return r;
  if (!persist()) {
    Entry& e = chans_.back();
    r_.removeGroupChannel(e.id);
    wipe(e.key.data(), e.key.size());
    chans_.pop_back();
    return Result::IoError;
  }
  return Result::Ok;
}

ChannelBook::Result ChannelBook::remove(const std::string& name) {
  for (auto it = chans_.begin(); it != chans_.end(); ++it) {
    if (it->name != name) continue;
    Entry gone = *it;
    chans_.erase(it);
    if (!persist()) {
      chans_.push_back(gone);   // keep both lists in step: still joined
      wipe(gone.key.data(), gone.key.size());
      return Result::IoError;
    }
    r_.removeGroupChannel(gone.id);
    wipe(gone.key.data(), gone.key.size());
    return Result::Ok;
  }
  return Result::NotFound;
}

const ChannelBook::Entry* ChannelBook::byName(const std::string& name) const {
  for (auto& c : chans_)
    if (c.name == name) return &c;
  return nullptr;
}

const ChannelBook::Entry* ChannelBook::byId(uint32_t id) const {
  for (auto& c : chans_)
    if (c.id == id) return &c;
  return nullptr;
}

}  // namespace gw
