// An in-memory node for session and link tests: decodes ToRadio frames and
// lets the test answer them.
import 'dart:async';
import 'dart:typed_data';

import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:ghostwave_app/src/link/frame_codec.dart';
import 'package:ghostwave_app/src/link/link_crypto.dart';
import 'package:ghostwave_app/src/link/transport.dart';

class FakeConnection implements TransportConnection {
  FakeConnection(this.node);

  final FakeNode node;
  final StreamController<Uint8List> _in = StreamController<Uint8List>();
  final FrameReader _reader = FrameReader();
  bool closed = false;

  /// Set once the PIN handshake succeeds; frames are then sealed both ways.
  LinkCipher? rx;
  LinkCipher? tx;

  /// Frames that failed to open, and plain frames after the handshake.
  int badFrames = 0;
  int plainAfterKeys = 0;

  /// The node's handshake secret and share, while a challenge is out.
  List<int>? share;

  @override
  Stream<Uint8List> get input => _in.stream;

  @override
  void write(List<int> bytes) {
    _reader.push(bytes);
    for (final e in _reader.drain()) {
      if (e is! Frame) continue;
      if (e.version == kSecureVersion) {
        final plain = rx?.open(e.body);
        if (plain == null) {
          badFrames++;
          continue;
        }
        node._onRequest(this, pb.ToRadio.fromBuffer(plain));
      } else {
        if (rx != null) plainAfterKeys++;
        node._onRequest(this, pb.ToRadio.fromBuffer(e.body));
      }
    }
  }

  /// Sends raw bytes to the app.
  void sendRaw(List<int> bytes) {
    if (!closed) _in.add(Uint8List.fromList(bytes));
  }

  void send(pb.FromRadio m, {int version = kProtocolVersion}) {
    final sealer = tx;
    if (sealer != null && version == kProtocolVersion) {
      sendRaw(encodeFrame(sealer.seal(m.writeToBuffer()), version: kSecureVersion));
    } else {
      sendRaw(encodeFrame(m.writeToBuffer(), version: version));
    }
  }

  /// The node drops the link.
  Future<void> drop() async {
    if (closed) return;
    closed = true;
    await _in.close();
  }

  @override
  Future<void> close() => drop();
}

class FakeNode implements Transport {
  FakeNode({this.nodeId = 0x11223344, this.autoHello = true, this.protocolMinor = 0});

  final int nodeId;
  final bool autoHello;

  /// NodeInfo.protocol_minor (1 = channels, SetName).
  int protocolMinor;

  /// When set, Hello must prove this PIN.
  String? pin;

  /// [Transport.needsEncryption].
  bool encryptionRequired = false;

  /// Leaves the share out of the challenge, as a node from before 1.3 would.
  bool oldChallenge = false;

  /// NodeInfo.firmware.
  String firmware = 'fake';

  /// NodeInfo.name.
  String name = 'N1';
  final List<FakeConnection> connections = <FakeConnection>[];
  final List<pb.ToRadio> requests = <pb.ToRadio>[];
  final StreamController<(FakeConnection, pb.ToRadio)> _reqs = StreamController.broadcast(sync: true);
  int failOpens = 0;
  int opens = 0;

  Stream<(FakeConnection, pb.ToRadio)> get onRequest => _reqs.stream;

  FakeConnection get last => connections.last;

  pb.NodeInfo get info => pb.NodeInfo(
    protocolVersion: 1,
    nodeId: nodeId,
    name: name.codeUnits,
    ed25519Pub: List.filled(32, 7),
    x25519Pub: List.filled(32, 8),
    firmware: firmware,
    maxTextBytes: 73,
    protocolMinor: protocolMinor,
    maxChannelTextBytes: protocolMinor >= 1 ? 86 : 0,
  );

  @override
  String get label => 'fake:${nodeId.toRadixString(16)}';

  @override
  bool get needsEncryption => encryptionRequired;

  @override
  Future<TransportConnection> open() async {
    opens++;
    if (failOpens > 0) {
      failOpens--;
      throw StateError('connection refused');
    }
    final c = FakeConnection(this);
    connections.add(c);
    return c;
  }

  void _onRequest(FakeConnection c, pb.ToRadio r) {
    requests.add(r);
    final needed = pin;
    if (autoHello && r.hasHello() && needed != null && c.rx == null) {
      unawaited(_pinHandshake(c, r, needed));
    } else if (autoHello && r.hasHello()) {
      scheduleMicrotask(() => c.send(pb.FromRadio(reqId: r.reqId, nodeInfo: info)));
    }
    _reqs.add((c, r));
  }

  static final List<int> _nonce = List<int>.filled(16, 0x42);
  static final List<int> _secret = List<int>.filled(32, 0x33);

  Future<void> _pinHandshake(FakeConnection c, pb.ToRadio r, String pin) async {
    if (r.hello.pinProof.isEmpty) {
      final share = await linkShare(pin, _nonce, _secret);
      c.share = share;
      c.send(
        pb.FromRadio(
          reqId: r.reqId,
          pinChallenge: pb.PinChallenge(nonce: _nonce, serverShare: oldChallenge ? const <int>[] : share),
        ),
      );
      return;
    }
    final share = c.share!;
    final keys = await linkKeys(
      secret: _secret,
      theirShare: r.hello.clientShare,
      nonce: _nonce,
      serverShare: share,
      clientShare: r.hello.clientShare,
    );
    if (keys == null || !listEquals(keys.confirm, r.hello.pinProof)) {
      c.send(
        pb.FromRadio(
          reqId: r.reqId,
          error: pb.Error(code: pb.Error_Code.BAD_PIN),
        ),
      );
      return;
    }
    c
      ..rx = LinkCipher(keys.clientToNode)
      ..tx = LinkCipher(keys.nodeToClient)
      ..send(pb.FromRadio(reqId: r.reqId, nodeInfo: info));
  }
}
