#!/usr/bin/env python3
"""clientlink_e2e.py: the client-link scenario run by clientlink_e2e.sh.

  clientlink_e2e.py WORKDIR A_ADDR B_ADDR C_ADDR PIN_ADDR AUTO_ADDR

Three ghostwaved nodes on the virtual radio (A 0 km, B 1.5 km, C 3 km), each
with --client-tcp. Drives them only through the client link (gwclient.py):
handshake, contact exchange (what a QR scan does), a DM from A's client to B's
client with a delivery receipt keyed by client_msg_id, a DM to C while C has no
client (queued, then replayed on connect), an SOS that B's client sees and
acks, group channels (protocol 1.1: join, list, a channel message that only
members can read, leave, errors), renaming a node, and the error paths.
Exits nonzero on the first failed check.
"""
import os
import socket
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gwclient as g  # noqa: E402

work, addr_a, addr_b, addr_c, addr_pin, addr_auto = sys.argv[1:7]
t0 = time.time()
failed = []


def say(msg):
    print("[%3ds] %s" % (time.time() - t0, msg), flush=True)


def check(cond, what):
    say(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)
    return cond


def must(cond, what):
    if not check(cond, what):
        say("stopping: later steps depend on this")
        sys.exit(1)


def log_has(node, text):
    try:
        with open(os.path.join(work, node + ".log"), errors="replace") as f:
            return text in f.read()
    except OSError:
        return False


def raw(addr):
    host, _, port = addr.rpartition(":")
    s = socket.create_connection((host, int(port)), timeout=5)
    return s


_raw = {}


def raw_reply(s, timeout=5):
    """Next message on a raw socket, or None on timeout / close."""
    r, pending = _raw.setdefault(s, (g.FrameReader(), []))
    end = time.time() + timeout
    while not pending and time.time() < end:
        s.settimeout(max(0.1, end - time.time()))
        try:
            data = s.recv(4096)
        except socket.timeout:
            break
        if not data:
            return None
        r.push(data)
        pending.extend(g.decode_from_radio(body) for _, body in r.frames())
    return pending.pop(0) if pending else None


# ------------------------------------------------------------- handshake --
a = g.Client(addr_a, "e2e A")
b = g.Client(addr_b, "e2e B")
ia, ib = a.info, b.info
say(g.fmt(ia))
say(g.fmt(ib))
must(ia["protocol_version"] == 1 and ia["node_id"] and len(ia["ed25519_pub"]) == 32 and len(ia["x25519_pub"]) == 32,
     "A: Hello -> NodeInfo with version, node ID and both public keys")
check(ia["name"] == b"A" and ib["name"] == b"B", "NodeInfo carries the IDENT name")
check(ia["max_text_bytes"] == 73, "NodeInfo.max_text_bytes = 73")

# C: read its card, then disconnect so C has no client
c = g.Client(addr_c, "e2e C (card only)")
ic = c.info
c.close()
say(g.fmt(ic))

# ---------------------------------------------------------- error paths --
s = raw(addr_a)
s.sendall(g.frame(g.encode_to_radio("get_status", 9)))
m = raw_reply(s)
check(m and m["kind"] == "error" and m["code_name"] == "NEED_HELLO" and m["req_id"] == 9,
      "request before Hello -> NEED_HELLO, req_id echoed")
s.sendall(g.frame(g.encode_to_radio("hello", 10, protocol_version=1)))
m = raw_reply(s)
check(m and m["kind"] == "node_info", "raw Hello -> NodeInfo")
s.sendall(g.frame(bytes([0x08, 11]) + g._tag(99, 2) + b"\x00"))  # a request from the future
m = raw_reply(s)
check(m and m["code_name"] == "UNKNOWN_REQUEST" and m["req_id"] == 11, "unknown request -> UNKNOWN_REQUEST")
s.sendall(b"\x94\xc3\xff\x00" + g.frame(g.encode_to_radio("get_position", 12)))  # bad length, then a good frame
m1, m2 = raw_reply(s), raw_reply(s)
got = [x for x in (m1, m2) if x]
check(any(x["kind"] == "error" and x["code_name"] == "BAD_FRAME" for x in got) and
      any(x["kind"] == "position" and x["req_id"] == 12 for x in got),
      "oversized frame length -> BAD_FRAME, stream resyncs on the next frame")
s.sendall(g.frame(g.encode_to_radio("get_status", 13), version=2))
m = raw_reply(s)
check(m and m["code_name"] == "BAD_VERSION", "frame version 2 -> BAD_VERSION")
check(raw_reply(s, 3) is None, "...and the node closes the connection")
s.close()

r = a.request("send_text", dest=ib["node_id"], text=b"x" * 74, client_msg_id=1)
check(r[0]["kind"] == "error" and r[0]["code_name"] == "TOO_LONG", "74-byte text -> TOO_LONG")
r = a.request("add_contact", node_id=ib["node_id"], ed25519_pub=ic["ed25519_pub"])
check(r[0]["code_name"] == "KEY_REJECTED", "contact key that does not hash to the ID -> KEY_REJECTED")
r = a.request("sos_ack", node_id=0x12345678)
check(r[0]["code_name"] == "NOT_FOUND", "SOS ack with no SOS held -> NOT_FOUND")

# ---------------------------------------------- contacts (the QR exchange) --
for cl, other, nm in ((a, ib, "Bee"), (b, ia, "Ay"), (a, ic, "Cee")):
    r = cl.request("add_contact", node_id=other["node_id"], ed25519_pub=other["ed25519_pub"], name=nm)
    must(r[0]["kind"] == "ok", "add contact %08x (%s)" % (other["node_id"], nm))
r = a.request("list_contacts")
ct = {m["node_id"]: m for m in r if m["kind"] == "contact"}
check(r[-1]["kind"] == "contacts_end" and r[-1]["count"] == len(ct) >= 2, "ListContacts -> Contact..., ContactsEnd")
cb = ct.get(ib["node_id"])
check(cb is not None and cb["pinned"] and cb["ed25519_pub"] == ib["ed25519_pub"] and cb["name"] == b"Bee"
      and cb["x25519_pub"] == ib["x25519_pub"], "B listed as pinned, with its keys and our label")
# C learns A's key the same way, through a short-lived client
c = g.Client(addr_c, "e2e C (contact)")
must(c.request("add_contact", node_id=ia["node_id"], ed25519_pub=ia["ed25519_pub"])[0]["kind"] == "ok",
     "C pins A's key")
c.close()

# ----------------------------------------------------- position requests --
r = a.request("get_position")
check(r[0]["kind"] == "position" and r[0]["pos"] and abs(r[0]["pos"][0] - 46.87) < 1e-6, "GetPosition -> A's fix")
r = a.request("set_known_position", node_id=ib["node_id"], pos=(46.87 + 1.5 * 0.0089932, -113.99))
check(r[0]["kind"] == "ok", "SetKnownPosition for B")

# -------------------------------------------- DM A -> B, receipt to A --
time.sleep(3)   # start-up beacons
CMID = 4242
r = a.request("send_text", dest=ib["node_id"], text="hello B, from A's app".encode(), client_msg_id=CMID)
must(r[0]["kind"] == "send_queued" and r[0]["client_msg_id"] == CMID and r[0]["msg_id"],
     "SendText -> SendQueued with the mesh msg_id")
mid = r[0]["msg_id"]
e = b.wait_event(lambda e: e["kind"] == "text" and e["src"] == ia["node_id"], 60)
check(e is not None and e["text"] == b"hello B, from A's app" and e["msg_id"] == mid,
      "B's client got the DM (msg_id %08x)" % mid)
check(e is not None and isinstance(e["rssi_dbm"], int) and -200 <= e["rssi_dbm"] <= 50,
      "the DM carries the signal it was heard at (1.7): %s dBm" % (e or {}).get("rssi_dbm"))
e = a.wait_event(lambda e: e["kind"] == "delivered" and e["msg_id"] == mid, 60)
check(e is not None and e["client_msg_id"] == CMID and e["dest"] == ib["node_id"],
      "A's client got Delivered with client_msg_id %d" % CMID)
check(not log_has("A", "hello B, from A") and log_has("B", "MSG from %08x" % ia["node_id"]),
      "stdout logging unchanged: B's log prints the MSG line")

# ------------------------------- DM A -> C while C has no client: replay --
# C is 3 km out, past A's reliable range: give A its position (as a contact
# card would), so the DM goes geographic via B instead of waiting in spray mode
a.request("set_known_position", node_id=ic["node_id"], pos=(46.87 + 3 * 0.0089932, -113.99))
r = a.request("send_text", dest=ic["node_id"], text=b"for C, held until its app connects", client_msg_id=7)
must(r[0]["kind"] == "send_queued", "SendText to C queued")
end = time.time() + 90
while time.time() < end and not log_has("C", "MSG from %08x" % ia["node_id"]):
    time.sleep(0.5)
must(log_has("C", "MSG from %08x" % ia["node_id"]), "C's daemon received the DM (no client connected)")
c = g.Client(addr_c, "e2e C (late)")
e = c.wait_event(lambda e: e["kind"] == "text", 5)
check(e is not None and e["replayed"] and e["text"] == b"for C, held until its app connects",
      "C's client got the held DM on Hello, flagged replayed")
st = c.request("get_status")[0]
check(st["kind"] == "status" and st["queued"] == 0 and st["clients"] == 1, "C status: queue drained, 1 client")
c.close()

# -------------------------------------------- SOS from A's client, B acks --
t_sos = time.time()
r = a.request("sos_start", text=b"e2e: twisted ankle", battery_pct=55, accuracy_m=10)
must(r[0]["kind"] == "ok", "SosStart -> Ok")
e = b.wait_event(lambda e: e["kind"] == "sos" and e["src"] == ia["node_id"], 70)
must(e is not None, "B's client got the SOS")
check(e["text"] == b"e2e: twisted ankle" and e["battery_pct"] == 55 and e["accuracy_m"] == 12 and e["pos"]
      and abs(e["pos"][0] - 46.87) < 1e-4, "SOS carries text, battery, accuracy (4 m steps) and position")
r = b.request("sos_ack", node_id=ia["node_id"])
check(r[0]["kind"] == "ok", "B's client acks the SOS")
# The router sends an SOS ack once, with no retry, right as A and its neighbors
# are busiest (B's relay, C's relay, A's next frame), so it can be lost to a
# collision or A's half-duplex radio. Ack again, as a responder would.
e = None
for _ in range(3):
    e = a.wait_event(lambda e: e["kind"] == "sos_ack" and e["responder"] == ib["node_id"], 20)
    if e is not None:
        break
    b.request("sos_ack", node_id=ia["node_id"])
check(e is not None, "A's client got SosAckReceived from B")
st = a.request("get_status")[0]
check(st["sos_active"] and st["tx"] > 0 and st["clients"] == 1, "A status: SOS active, frames sent")
check(a.request("sos_stop")[0]["kind"] == "ok" and not a.request("get_status")[0]["sos_active"], "SosStop")
e = b.wait_event(lambda e: e["kind"] == "sos_cancelled" and e["src"] == ia["node_id"], 30)
check(e is not None and e["verified"], "B's client hears the signed SOS cancel, verified")
check(not b.request("get_status")[0]["sos_held"], "B dropped the cancelled SOS")
if time.time() - t_sos < 55:
    r = a.request("sos_start", text=b"again")
    check(r[0].get("code_name") == "RATE_LIMITED", "second SOS within a minute -> RATE_LIMITED")
else:   # a slow step above used up the minute: the check would be meaningless
    say("skip  second SOS within a minute (over a minute since SosStart)")

# -------------------------------------------- group channels (protocol 1.1) --
check(ia.get("protocol_minor") == 12 and ia.get("max_channel_text_bytes") == 86,
      "NodeInfo: protocol_minor 12, max_channel_text_bytes 86")
PSK = bytes(range(1, 33))
for cl, who in ((a, "A"), (b, "B")):
    must(cl.request("add_channel", name="e2e crew", psk=PSK)[0]["kind"] == "ok", "%s joins #e2e crew" % who)
check(a.request("add_channel", name="e2e crew", psk=PSK)[0]["kind"] == "ok", "joining again with the same key -> Ok")
r = a.request("add_channel", name="e2e crew", psk=bytes(32))
check(r[0]["code_name"] == "BAD_ARGUMENT", "same name, another key -> BAD_ARGUMENT")
r = a.request("add_channel", name="short key", psk=b"x" * 31)
check(r[0]["code_name"] == "BAD_ARGUMENT", "31-byte key -> BAD_ARGUMENT")
r = a.request("list_channels")
check(r[-1]["kind"] == "channels_end" and r[-1]["count"] == 1 and r[0]["kind"] == "channel"
      and r[0]["name"] == "e2e crew" and r[0]["psk"] == PSK, "ListChannels -> Channel (with its key), ChannelsEnd")
r = a.request("send_channel_text", channel="nope", text=b"hi", client_msg_id=1)
check(r[0]["code_name"] == "NOT_FOUND", "unknown channel -> NOT_FOUND")
r = a.request("send_channel_text", channel="e2e crew", text=b"x" * 87, client_msg_id=1)
check(r[0]["code_name"] == "TOO_LONG", "87-byte channel text -> TOO_LONG")
# C joins a different channel: it relays A's frame but cannot read it
c = g.Client(addr_c, "e2e C (channel)")
must(c.request("add_channel", name="other", psk=bytes(range(100, 132)))[0]["kind"] == "ok", "C joins #other")
c.close()
r = a.request("send_channel_text", channel="e2e crew", text="crew: camp at the lake".encode(), client_msg_id=55)
must(r[0]["kind"] == "send_queued" and r[0]["dest"] == 0xFFFFFFFF and r[0]["client_msg_id"] == 55 and r[0]["msg_id"],
     "SendChannelText -> SendQueued (dest broadcast)")
cmid = r[0]["msg_id"]
e = b.wait_event(lambda e: e["kind"] == "channel_message", 30)
check(e is not None and e["channel"] == "e2e crew" and e["src"] == ia["node_id"] and e["msg_id"] == cmid
      and e["text"] == "crew: camp at the lake".encode(), "B's client got the channel message on #e2e crew")
time.sleep(2)
check(log_has("B", "CHAN #e2e crew from %08x" % ia["node_id"]) and not log_has("C", "crew: camp"),
      "B's daemon printed it; C (another channel) could not read it")
path = os.path.join(work, "A.key.channels")
check(os.path.exists(path) and (os.stat(path).st_mode & 0o077) == 0 and "e2e crew" in open(path).read(),
      "A keeps its channels in A.key.channels, mode 600")
c = g.Client(addr_c, "e2e C (leave)")
check(c.request("remove_channel", name="other")[0]["kind"] == "ok", "C leaves #other")
check(c.request("remove_channel", name="other")[0]["code_name"] == "NOT_FOUND", "leaving again -> NOT_FOUND")
c.close()

# ------------------------------------------------------ SetName (1.1) --
r = b.request("set_name", name="0123456789")
check(r[0]["code_name"] == "BAD_ARGUMENT", "10-byte name -> BAD_ARGUMENT")
must(b.request("set_name", name="Bee2")[0]["kind"] == "ok", "B renames itself Bee2")
b2 = g.Client(addr_b, "e2e B (after rename)")
check(b2.info["name"] == b"Bee2", "a new Hello reports the new name")
b2.close()
check(open(os.path.join(work, "B.key.name")).read().strip() == "Bee2", "B keeps the name in B.key.name")
e = a.wait_event(lambda e: e["kind"] == "peer_ident" and e["node_id"] == ib["node_id"] and e["name"] == b"Bee2", 45)
check(e is not None and not e["is_new"], "A's client hears B's new name over the air (IDENT, renamed)")

# ------------------------------------------------- client PIN (protocol 1.2) --
PIN = "424242"
try:
    g.Client(addr_pin, "no pin")
    check(False, "a PIN node refuses a client with no PIN")
except g.ClientError:
    check(True, "a PIN node refuses a client with no PIN")
s = raw(addr_pin)
s.sendall(g.frame(g.encode_to_radio("hello", 1, protocol_version=1)))
m = raw_reply(s)
check(m and m["kind"] == "pin_challenge" and len(m["nonce"]) == 16 and len(m["server_share"]) == 32,
      "Hello -> PinChallenge with a 16-byte nonce and a 32-byte share")
s.sendall(g.frame(g.encode_to_radio("get_status", 2)))
m2 = raw_reply(s)
check(m2 and m2["code_name"] == "NEED_HELLO", "a challenge alone opens nothing -> NEED_HELLO")
secret = b"\x11" * 32
share = g.link_share("000000", m["nonce"], secret)
keys = g.link_keys(secret, m["server_share"], m["nonce"], m["server_share"], share)
s.sendall(g.frame(g.encode_to_radio("hello", 3, protocol_version=1, client_share=share,
                                    pin_proof=keys["confirm"])))
m3 = raw_reply(s)
check(m3 and m3["code_name"] == "BAD_PIN", "wrong PIN -> BAD_PIN")
s.close()
p = g.Client(addr_pin, "right pin", pin=PIN)
check(p.info["kind"] == "node_info" and p.request("get_status")[0]["kind"] == "status",
      "right PIN -> NodeInfo, and requests work")
check(p.encrypted, "...over an encrypted link")
p.sock.sendall(g.frame(g.encode_to_radio("get_status", 999)))
try:
    gone = not p.pump(2.0)
except g.ClientError:
    gone = True
check(gone, "a plain frame on the encrypted link closes it")
p.close()
check(log_has("P", "client PIN: " + PIN), "the daemon prints the PIN it was given")
path = os.path.join(work, "Q.key.pin")
auto = open(path).read().strip() if os.path.exists(path) else ""
check(len(auto) == 6 and auto.isdigit() and (os.stat(path).st_mode & 0o077) == 0,
      "bound to the network: a 6-digit PIN is made, in a mode 600 file")
check(log_has("Q", "client PIN: " + auto) and log_has("Q", "PIN required"), "...printed at start")
try:
    g.Client(addr_auto, "no pin")
    check(False, "...and required")
except g.ClientError:
    check(True, "...and required")
q = g.Client(addr_auto, "auto pin", pin=auto)
check(q.info["kind"] == "node_info", "...and accepted")
q.close()

# --------------------------------------------------- telemetry (1.12) --
r = a.request("get_telemetry", node_id=ia["node_id"])
check(r[0]["kind"] == "node_telemetry" and r[0]["uptime_s"] is not None and r[0]["battery_pct"] is None
      and r[0]["battery_mv"] is None, "GetTelemetry (own): uptime, and no battery on a daemon")
r = a.request("get_telemetry", node_id=0x0BADF00D)
check(r[0].get("code_name") == "NOT_FOUND", "GetTelemetry for a node never heard -> NOT_FOUND")

# ---------------------------------------------------- other live events --
nb = [e for e in a.events + b.events if e["kind"] == "neighbor"]
say("neighbor events seen: %d (beacons are minutes apart; not required)" % len(nb))
for e in nb[:4]:
    say("  " + g.fmt(e))
tl = [e for e in a.events + b.events if e["kind"] == "node_telemetry"]
for e in tl[:4]:
    check(e["uptime_s"] is not None and e["battery_pct"] is None, "neighbor telemetry: uptime only (%08x)" % e["node_id"])

a.close()
b.close()
print()
if failed:
    say("FAIL: %d check(s) failed: %s" % (len(failed), "; ".join(failed)))
    sys.exit(1)
say("PASS: client link end to end (handshake, contacts, DM + receipt, offline replay, SOS + ack, channels, "
    "rename, PIN, errors)")
