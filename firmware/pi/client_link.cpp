// Client link for ghostwaved: TCP transport and request handling
// (docs/CLIENT_PROTOCOL.md).
#include "client_link.h"

#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstring>

using namespace gw::client;

namespace {

#ifdef MSG_NOSIGNAL
constexpr int kSendFlags = MSG_NOSIGNAL;
#else
constexpr int kSendFlags = 0;   // macOS: SO_NOSIGPIPE on each socket instead
#endif

void setNonBlocking(int fd) { fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK); }

void noSigPipe(int fd) {
#ifdef SO_NOSIGPIPE
  int one = 1;
  setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#else
  (void)fd;
#endif
}

std::string sockName(const sockaddr* sa) {
  char host[INET6_ADDRSTRLEN] = "?";
  int port = 0;
  if (sa->sa_family == AF_INET) {
    auto* in = reinterpret_cast<const sockaddr_in*>(sa);
    inet_ntop(AF_INET, &in->sin_addr, host, sizeof host);
    port = ntohs(in->sin_port);
    return std::string(host) + ":" + std::to_string(port);
  }
  if (sa->sa_family == AF_INET6) {
    auto* in6 = reinterpret_cast<const sockaddr_in6*>(sa);
    inet_ntop(AF_INET6, &in6->sin6_addr, host, sizeof host);
    port = ntohs(in6->sin6_port);
  }
  return "[" + std::string(host) + "]:" + std::to_string(port);
}

}  // namespace

ClientLink::ClientLink(gw::Router& router, const ClientNodeIdentity& self, const gw::Position& pos,
                       Hooks hooks, uint64_t startMs)
    : h_(router, self, pos, std::move(hooks), startMs, *this, kQueueMax) {}

ClientLink::~ClientLink() {
  for (auto& c : clients_) close(c.fd);
  if (lfd_ >= 0) close(lfd_);
}

bool ClientLink::listen(const std::string& spec, std::string& err) {
  std::string host = "127.0.0.1", port = spec;
  size_t colon = spec.rfind(':');
  if (colon != std::string::npos) {
    host = spec.substr(0, colon);
    port = spec.substr(colon + 1);
    if (host.size() >= 2 && host.front() == '[' && host.back() == ']') host = host.substr(1, host.size() - 2);
    if (host.empty()) host = "127.0.0.1";
  }
  if (port.empty() || port.size() > 5 || port.find_first_not_of("0123456789") != std::string::npos ||
      std::stoul(port) > 65535) {
    err = "bad port in '" + spec + "' (want PORT or HOST:PORT)";
    return false;
  }
  addrinfo hints{}, *res = nullptr;
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_PASSIVE | AI_NUMERICSERV;
  int rc = getaddrinfo(host.c_str(), port.c_str(), &hints, &res);
  if (rc != 0) {
    err = "cannot resolve " + host + ": " + gai_strerror(rc);
    return false;
  }
  for (addrinfo* a = res; a; a = a->ai_next) {
    int fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
    if (fd < 0) continue;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (bind(fd, a->ai_addr, a->ai_addrlen) == 0 && ::listen(fd, 4) == 0) {
      setNonBlocking(fd);
      sockaddr_storage ss{};
      socklen_t sl = sizeof ss;
      getsockname(fd, reinterpret_cast<sockaddr*>(&ss), &sl);
      addr_ = sockName(reinterpret_cast<sockaddr*>(&ss));
      lfd_ = fd;
      break;
    }
    err = std::string("cannot listen on ") + spec + ": " + std::strerror(errno);
    close(fd);
  }
  freeaddrinfo(res);
  if (lfd_ < 0 && err.empty()) err = "cannot listen on " + spec;
  return lfd_ >= 0;
}

void ClientLink::poll(uint64_t now) {
  if (lfd_ < 0) return;
  accept();
  for (size_t i = 0; i < clients_.size(); ++i) {
    if (clients_[i].fd >= 0 && !clients_[i].conn.closing) readFrom(clients_[i], now);
    if (clients_[i].fd >= 0) flush(clients_[i]);
  }
  dropClosed();
}

void ClientLink::accept() {
  for (int n = 0; n < 4; ++n) {
    sockaddr_storage ss{};
    socklen_t sl = sizeof ss;
    int fd = ::accept(lfd_, reinterpret_cast<sockaddr*>(&ss), &sl);
    if (fd < 0) return;
    setNonBlocking(fd);
    noSigPipe(fd);
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    Client c;
    c.fd = fd;
    c.conn.peer = sockName(reinterpret_cast<sockaddr*>(&ss));
    size_t open = std::count_if(clients_.begin(), clients_.end(), [](const Client& x) { return x.fd >= 0; });
    clients_.push_back(std::move(c));
    Client& nc = clients_.back();
    if (open >= kMaxClients) {
      h_.error(nc.conn, 0, ErrorCode::TooManyClients, "at most 4 clients");
      nc.conn.closing = true;
      std::printf("client %s refused: %zu already connected\n", nc.conn.peer.c_str(), open);
    } else {
      std::printf("client %s connected\n", nc.conn.peer.c_str());
    }
    std::fflush(stdout);
  }
}

void ClientLink::readFrom(Client& c, uint64_t now) {
  uint8_t buf[512];
  for (int n = 0; n < 8; ++n) {
    ssize_t got = recv(c.fd, buf, sizeof buf, 0);
    if (got == 0 || (got < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)) {
      std::printf("client %s disconnected\n", c.conn.peer.c_str());
      std::fflush(stdout);
      close(c.fd);
      c.fd = -1;
      return;
    }
    if (got < 0) break;
    c.in.push(buf, static_cast<size_t>(got));
    h_.receive(c.conn, c.in, now);
    if (c.conn.closing) return;
    if (static_cast<size_t>(got) < sizeof buf) break;
  }
}

void ClientLink::flush(Client& c) {
  while (!c.out.empty()) {
    ssize_t n = ::send(c.fd, c.out.data(), c.out.size(), kSendFlags);
    if (n <= 0) {
      if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) break;
      close(c.fd);
      c.fd = -1;
      return;
    }
    c.out.erase(c.out.begin(), c.out.begin() + n);
  }
  if (c.out.size() > kOutMax) {
    std::printf("client %s dropped: not reading (%zu bytes backlog)\n", c.conn.peer.c_str(), c.out.size());
    std::fflush(stdout);
    close(c.fd);
    c.fd = -1;
    return;
  }
  if (c.conn.closing && c.out.empty()) {
    close(c.fd);
    c.fd = -1;
  }
}

void ClientLink::dropClosed() {
  clients_.erase(std::remove_if(clients_.begin(), clients_.end(), [](const Client& c) { return c.fd < 0; }),
                 clients_.end());
}

void ClientLink::write(gw::client::Conn& conn, const uint8_t* frame, size_t n) {
  for (auto& c : clients_)
    if (&c.conn == &conn) {
      if (c.fd >= 0) c.out.insert(c.out.end(), frame, frame + n);
      return;
    }
}

void ClientLink::forEachConn(const std::function<void(gw::client::Conn&)>& fn) {
  for (auto& c : clients_)
    if (c.fd >= 0) fn(c.conn);
}

void ClientLink::log(const std::string& line) {
  std::printf("%s\n", line.c_str());
  std::fflush(stdout);
}
