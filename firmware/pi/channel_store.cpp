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
    Result r = restore(name, key);
    gw::wipe(key, sizeof key);
    if (r != Result::Ok) {
      err = path_ + ":" + std::to_string(n) + ": " + describe(r);
      return false;
    }
  }
  return true;
}

// Written to a temporary file (mode 600) and renamed over the old one, so a
// crash never leaves half a key file.
bool ChannelStore::persist() const {
  if (path_.empty()) return true;
  std::string tmp = path_ + ".tmp";
  int fd = open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (fd < 0) return false;
  fchmod(fd, 0600);
  std::string body = "# ghostwaved group channels: <64 hex key><TAB><name>. Keep this file private.\n";
  for (auto& c : list()) body += hex(c.key.data(), c.key.size()) + "\t" + c.name + "\n";
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
