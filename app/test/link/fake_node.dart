// An in-memory node for session and link tests: decodes ToRadio frames and
// lets the test answer them.
import 'dart:async';
import 'dart:typed_data';

import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/frame_codec.dart';
import 'package:ghostwave_app/src/link/transport.dart';

class FakeConnection implements TransportConnection {
  FakeConnection(this.node);

  final FakeNode node;
  final StreamController<Uint8List> _in = StreamController<Uint8List>();
  final FrameReader _reader = FrameReader();
  bool closed = false;

  @override
  Stream<Uint8List> get input => _in.stream;

  @override
  void write(List<int> bytes) {
    _reader.push(bytes);
    for (final e in _reader.drain()) {
      if (e is Frame) node._onRequest(this, pb.ToRadio.fromBuffer(e.body));
    }
  }

  /// Sends raw bytes to the app.
  void sendRaw(List<int> bytes) {
    if (!closed) _in.add(Uint8List.fromList(bytes));
  }

  void send(pb.FromRadio m, {int version = kProtocolVersion}) =>
      sendRaw(encodeFrame(m.writeToBuffer(), version: version));

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
  FakeNode({this.nodeId = 0x11223344, this.autoHello = true});

  final int nodeId;
  final bool autoHello;
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
    name: 'N1'.codeUnits,
    ed25519Pub: List.filled(32, 7),
    x25519Pub: List.filled(32, 8),
    firmware: 'fake',
    maxTextBytes: 73,
  );

  @override
  String get label => 'fake:${nodeId.toRadixString(16)}';

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
    if (autoHello && r.hasHello()) {
      scheduleMicrotask(() => c.send(pb.FromRadio(reqId: r.reqId, nodeInfo: info)));
    }
    _reqs.add((c, r));
  }
}
