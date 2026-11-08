// Group channels joined by ghostwaved (DESIGN §9.3): name -> key, mirrored
// into the Router, kept in a file next to the identity key so they survive a
// restart. Used by the client link (AddChannel / RemoveChannel / ListChannels).
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "ghostwave/router.h"

struct ChannelEntry {
  std::string name;
  std::array<uint8_t, 32> key{};
  uint32_t id = 0;   // gw::groupChannelId(key)
};

class ChannelStore {
 public:
  enum class Result { Ok, Unchanged, BadName, BadKey, NameTaken, KeyTaken, Full, NotFound, IoError };
  static constexpr size_t kNameMax = 16;   // bytes, UTF-8

  // `path` empty: kept in memory only.
  ChannelStore(gw::Router& router, std::string path);
  ~ChannelStore();
  ChannelStore(const ChannelStore&) = delete;
  ChannelStore& operator=(const ChannelStore&) = delete;

  // Reads the file (a missing file is an empty list) and joins its channels.
  // False with `err` set on a malformed or unreadable file.
  bool load(std::string& err);
  // Joins a channel and saves. Unchanged: the same name with the same key is
  // already joined. NameTaken / KeyTaken: the name or key is in use by
  // another channel.
  Result add(const std::string& name, const uint8_t* key, size_t keyLen);
  Result remove(const std::string& name);
  const ChannelEntry* byName(const std::string& name) const;
  const ChannelEntry* byId(uint32_t id) const;
  const std::vector<ChannelEntry>& list() const { return chans_; }
  static bool validName(const std::string& name);
  static const char* describe(Result r);

 private:
  bool save() const;

  gw::Router& r_;
  std::string path_;
  std::vector<ChannelEntry> chans_;
};
