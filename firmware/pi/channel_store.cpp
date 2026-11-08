#include "channel_store.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <fstream>

#include "ghostwave/crypto.h"

namespace {

std::string hex(const uint8_t* p, size_t n) {
  static const char d[] = "0123456789abcdef";
  std::string s;
  for (size_t i = 0; i < n; ++i) s += d[p[i] >> 4], s += d[p[i] & 15];
  return s;
}

bool unhex(const std::string& s, uint8_t* out, size_t n) {
  if (s.size() != 2 * n) return false;
  auto v = [](char c) -> int {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
  };
  for (size_t i = 0; i < n; ++i) {
    int hi = v(s[2 * i]), lo = v(s[2 * i + 1]);
    if (hi < 0 || lo < 0) return false;
    out[i] = static_cast<uint8_t>(hi << 4 | lo);
  }
  return true;
}

}  // namespace

ChannelStore::ChannelStore(gw::Router& router, std::string path) : r_(router), path_(std::move(path)) {}

ChannelStore::~ChannelStore() {
  for (auto& c : chans_) gw::wipe(c.key.data(), c.key.size());
}

bool ChannelStore::validName(const std::string& name) {
  if (name.empty() || name.size() > kNameMax) return false;
  for (unsigned char c : name)
    if (c < 0x20 || c == 0x7F) return false;   // control bytes, tab, newline: not in a name
  return true;
}

const char* ChannelStore::describe(Result r) {
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

bool ChannelStore::load(std::string& err) {
  if (path_.empty()) return true;
  std::ifstream f(path_);
  if (!f) return true;   // none yet
  struct stat st {};
  if (stat(path_.c_str(), &st) == 0 && (st.st_mode & 077))
    std::fprintf(stderr, "warning: %s is readable by others; chmod 600 it\n", path_.c_str());
  std::string line;
  int n = 0;
  while (std::getline(f, line)) {
    ++n;
    if (line.empty() || line[0] == '#') continue;
    size_t tab = line.find('\t');
    uint8_t key[32];
    if (tab == std::string::npos || !unhex(line.substr(0, tab), key, sizeof key)) {
      err = path_ + ":" + std::to_string(n) + ": want \"<64 hex key><TAB><name>\"";
      return false;
    }
    std::string name = line.substr(tab + 1);
    Result r = Result::Ok;
    if (!validName(name)) r = Result::BadName;
    else if (byName(name)) r = Result::NameTaken;
    else {
      uint32_t id = r_.addGroupChannel(key);
      if (!id) r = Result::Full;
      else if (byId(id)) r = Result::KeyTaken;
      else {
        ChannelEntry e;
        e.name = name;
        std::memcpy(e.key.data(), key, 32);
        e.id = id;
        chans_.push_back(e);
      }
    }
    gw::wipe(key, sizeof key);
    if (r != Result::Ok) {
      err = path_ + ":" + std::to_string(n) + ": " + describe(r);
      return false;
    }
  }
  return true;
}

ChannelStore::Result ChannelStore::add(const std::string& name, const uint8_t* key, size_t keyLen) {
  if (!validName(name)) return Result::BadName;
  if (keyLen != 32) return Result::BadKey;
  uint32_t id = gw::groupChannelId(key);
  const ChannelEntry* byN = byName(name);
  if (byN) return byN->id == id ? Result::Unchanged : Result::NameTaken;
  if (byId(id)) return Result::KeyTaken;
  if (chans_.size() >= gw::kMaxGroupChannels || !r_.addGroupChannel(key)) return Result::Full;
  ChannelEntry e;
  e.name = name;
  std::memcpy(e.key.data(), key, 32);
  e.id = id;
  chans_.push_back(e);
  if (!save()) {
    r_.removeGroupChannel(id);
    gw::wipe(chans_.back().key.data(), 32);
    chans_.pop_back();
    return Result::IoError;
  }
  return Result::Ok;
}

ChannelStore::Result ChannelStore::remove(const std::string& name) {
  for (auto it = chans_.begin(); it != chans_.end(); ++it) {
    if (it->name != name) continue;
    r_.removeGroupChannel(it->id);
    gw::wipe(it->key.data(), it->key.size());
    chans_.erase(it);
    return save() ? Result::Ok : Result::IoError;
  }
  return Result::NotFound;
}

const ChannelEntry* ChannelStore::byName(const std::string& name) const {
  for (auto& c : chans_)
    if (c.name == name) return &c;
  return nullptr;
}

const ChannelEntry* ChannelStore::byId(uint32_t id) const {
  for (auto& c : chans_)
    if (c.id == id) return &c;
  return nullptr;
}

// Written to a temporary file (mode 600) and renamed over the old one, so a
// crash never leaves half a key file.
bool ChannelStore::save() const {
  if (path_.empty()) return true;
  std::string tmp = path_ + ".tmp";
  int fd = open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (fd < 0) return false;
  fchmod(fd, 0600);
  std::string body = "# ghostwaved group channels: <64 hex key><TAB><name>. Keep this file private.\n";
  for (auto& c : chans_) body += hex(c.key.data(), c.key.size()) + "\t" + c.name + "\n";
  bool ok = write(fd, body.data(), body.size()) == static_cast<ssize_t>(body.size());
  ok = fsync(fd) == 0 && ok;
  close(fd);
  gw::wipe(&body[0], body.size());
  if (!ok || rename(tmp.c_str(), path_.c_str()) != 0) {
    unlink(tmp.c_str());
    return false;
  }
  return true;
}
