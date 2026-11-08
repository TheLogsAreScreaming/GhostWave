// Group channels a node has joined (DESIGN §9.3): name -> key, mirrored into
// the Router. Portable; the client handler (client_handler.h) serves the
// protocol 1.1 channel requests from it on every transport. Storage is the
// host's: override persist() (the Pi daemon saves a file next to its key,
// pi/channel_store.h); the default keeps channels in RAM only.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "ghostwave/router.h"

namespace gw {

class ChannelBook {
 public:
  struct Entry {
    std::string name;
    std::array<uint8_t, 32> key{};
    uint32_t id = 0;   // groupChannelId(key)
  };
  enum class Result { Ok, Unchanged, BadName, BadKey, NameTaken, KeyTaken, Full, NotFound, IoError };
  static constexpr size_t kNameMax = 16;   // bytes, UTF-8

  explicit ChannelBook(Router& router) : r_(router) {}
  virtual ~ChannelBook();
  ChannelBook(const ChannelBook&) = delete;
  ChannelBook& operator=(const ChannelBook&) = delete;

  // Joins a channel and persists. Unchanged: the same name with the same key
  // is already joined. NameTaken / KeyTaken: the name or key is in use by
  // another channel. IoError: persist() failed (nothing changed).
  Result add(const std::string& name, const uint8_t* key, size_t keyLen);
  Result remove(const std::string& name);
  const Entry* byName(const std::string& name) const;
  const Entry* byId(uint32_t id) const;
  const std::vector<Entry>& list() const { return chans_; }
  static bool validName(const std::string& name);
  static const char* describe(Result r);

 protected:
  // Joins without persisting (loading saved channels).
  Result restore(const std::string& name, const uint8_t key[32]);
  // Saves list(); false on failure. Default: nothing to save.
  virtual bool persist() const { return true; }

 private:
  Result join(const std::string& name, const uint8_t* key, size_t keyLen);

  Router& r_;
  std::vector<Entry> chans_;
};

}  // namespace gw
