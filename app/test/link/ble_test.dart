// The Bluetooth transport against a fake radio: MTU sizes, fragmentation both
// ways, pairing failure, Bluetooth off, drop and reconnect.
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/ble.dart';
import 'package:ghostwave_app/src/link/frame_codec.dart';
import 'package:ghostwave_app/src/link/node_link.dart';

/// A node at the far end of a fake GATT link.
class FakeLink implements BleLink {
  FakeLink(this.radio);

  final FakeRadio radio;
  final StreamController<Uint8List> _notes = StreamController<Uint8List>.broadcast(sync: true);
  final Completer<void> _gone = Completer<void>();
  final List<int> writeSizes = <int>[];
  final FrameReader _reader = FrameReader();
  bool subscribed = false;
  bool closed = false;
  bool silent = false;

  @override
  Future<int> negotiateMtu(int want) async {
    if (radio.mtu == null) throw StateError('no MTU exchange');
    return radio.mtu!;
  }

  @override
  Stream<Uint8List> get notifications => _notes.stream;

  @override
  Future<void> subscribe() async {
    if (radio.pairingFails) throw const BleAuthException();
    if (radio.staleBond) throw const BleStaleBondException();
    subscribed = true;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    if (radio.failWrites) throw StateError('write failed');
    writeSizes.add(bytes.length);
    _reader.push(bytes);
    for (final e in _reader.drain()) {
      if (e is Frame) _request(pb.ToRadio.fromBuffer(e.body));
    }
  }

  void _request(pb.ToRadio r) {
    radio.requests.add(r);
    if (r.hasHello()) {
      notifyFrame(
        pb.FromRadio(
          reqId: r.reqId,
          nodeInfo: pb.NodeInfo(protocolVersion: 1, nodeId: 7, firmware: 'ghostwave-rak4631', maxTextBytes: 73),
        ),
      );
    } else if (r.hasGetStatus()) {
      notifyFrame(pb.FromRadio(reqId: r.reqId, status: pb.Status()));
    }
  }

  /// Sends a frame in notifications of at most MTU - 3 bytes.
  void notifyFrame(pb.FromRadio m) {
    if (silent) return;
    final f = encodeFrame(m.writeToBuffer());
    final chunk = (radio.mtu ?? kBleMinMtu) - 3;
    scheduleMicrotask(() {
      for (var off = 0; off < f.length; off += chunk) {
        _notes.add(Uint8List.fromList(f.sublist(off, (off + chunk).clamp(0, f.length))));
      }
    });
  }

  void drop() {
    if (!_gone.isCompleted) _gone.complete();
  }

  @override
  Future<void> get disconnected => _gone.future;

  @override
  Future<void> close() async {
    closed = true;
    drop();
  }
}

class FakeRadio implements BleRadio {
  int? mtu = 247;
  bool pairingFails = false;
  bool staleBond = false;
  bool failWrites = false;
  bool connectFails = false;
  BleAvailability state = BleAvailability.on;
  final List<FakeLink> links = <FakeLink>[];
  final List<pb.ToRadio> requests = <pb.ToRadio>[];

  @override
  Future<BleAvailability> availability() async => state;

  @override
  Future<void> ensurePermissions() async {}

  @override
  Stream<BleAdvert> scan() => const Stream.empty();

  @override
  Future<BleLink> connect(String id) async {
    if (connectFails) throw StateError('out of range');
    final l = FakeLink(this);
    links.add(l);
    return l;
  }
}

const BleNodeRef node = BleNodeRef('AA:BB', 'GhostWave-a11b');

void main() {
  test('stored form', () {
    final back = BleNodeRef.tryParse(node.encode())!;
    expect([back.id, back.name], ['AA:BB', 'GhostWave-a11b']);
    expect(BleNodeRef.tryParse('192.168.1.20:47800'), isNull);
    expect(BleNodeRef.tryParse('ble:noname'), isNull);
  });

  void connectAt(int? mtu, void Function(FakeRadio, NodeLink, FakeAsync) body) {
    fakeAsync((fa) {
      final radio = FakeRadio()..mtu = mtu;
      final link = NodeLink();
      link.connect(BleTransport(node, radio));
      fa.flushMicrotasks();
      body(radio, link, fa);
      link.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
  }

  for (final (mtu, largest) in [(23, 20), (185, 182), (247, 244), (517, 244), (null, 20)]) {
    test('MTU $mtu: writes of at most $largest bytes, and Hello gets through', () {
      connectAt(mtu, (radio, link, fa) {
        expect(link.state, isA<LinkUp>());
        expect(radio.links.single.subscribed, isTrue);
        final big = pb.ToRadio(sendText: pb.SendText(dest: 1, text: List.filled(150, 0x41)));
        unawaited((link.state as LinkUp).session.request(big).catchError((Object _) => pb.FromRadio()));
        fa.flushMicrotasks();
        expect(radio.requests.last.sendText.text, hasLength(150), reason: 'reassembled in order');
        final sizes = radio.links.single.writeSizes;
        expect(sizes.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(largest));
        if (mtu == 23) expect(sizes.where((s) => s == 20).length, greaterThan(5));
        fa.elapse(const Duration(seconds: 9)); // the unanswered request times out
      });
    });
  }

  test('fragmented notifications are reassembled (MTU 23)', () {
    connectAt(23, (radio, link, fa) {
      final events = <pb.FromRadio>[];
      link.events.listen(events.add);
      radio.links.single.notifyFrame(pb.FromRadio(text: pb.TextMessage(src: 9, msgId: 1, text: List.filled(70, 0x42))));
      fa.flushMicrotasks();
      expect(events.single.text.text, hasLength(70));
    });
  });

  test('a drop reconnects without user action, and Hello runs again', () {
    connectAt(247, (radio, link, fa) {
      radio.links.single.drop();
      fa.flushMicrotasks();
      expect(link.state, isA<LinkWaiting>());
      fa.elapse(const Duration(seconds: 1));
      expect(link.state, isA<LinkUp>());
      expect(radio.links, hasLength(2));
      expect(radio.requests.where((r) => r.hasHello()), hasLength(2));
    });
  });

  test('out of range keeps retrying, then recovers', () {
    fakeAsync((fa) {
      final radio = FakeRadio()..connectFails = true;
      final link = NodeLink();
      link.connect(BleTransport(node, radio));
      fa.flushMicrotasks();
      expect(link.state, isA<LinkWaiting>());
      fa.elapse(const Duration(seconds: 30));
      radio.connectFails = false;
      fa.elapse(const Duration(seconds: 21));
      expect(link.state, isA<LinkUp>());
      link.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('a link that goes silent is caught by the heartbeat', () {
    connectAt(247, (radio, link, fa) {
      radio.links.single.silent = true;
      fa.elapse(const Duration(seconds: 27));
      expect(radio.links.length, greaterThanOrEqualTo(2));
    });
  });

  test('a failed write ends the connection and it reconnects', () {
    connectAt(247, (radio, link, fa) {
      radio.failWrites = true;
      unawaited(
        (link.state as LinkUp).session
            .request(pb.ToRadio(getStatus: pb.GetStatus()))
            .catchError((Object _) => pb.FromRadio()),
      );
      fa.flushMicrotasks();
      expect(radio.links.single.closed, isTrue);
      radio.failWrites = false;
      fa.elapse(const Duration(seconds: 1));
      expect(link.state, isA<LinkUp>());
    });
  });

  test('failed pairing stops, with what to do; no passkey dialog loop', () {
    fakeAsync((fa) {
      final radio = FakeRadio()..pairingFails = true;
      final link = NodeLink();
      link.connect(BleTransport(node, radio));
      fa.flushMicrotasks();
      expect(link.state, isA<LinkFailed>());
      expect((link.state as LinkFailed).reason, contains('passkey'));
      expect(radio.links.single.closed, isTrue);
      fa.elapse(const Duration(minutes: 2));
      expect(radio.links, hasLength(1));
      radio.pairingFails = false;
      link.retryNow();
      fa.flushMicrotasks();
      expect(link.state, isA<LinkUp>());
      link.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('an old pairing from earlier firmware stops with how to fix it', () {
    fakeAsync((fa) {
      final radio = FakeRadio()..staleBond = true;
      final link = NodeLink();
      link.connect(BleTransport(node, radio));
      fa.flushMicrotasks();
      expect(link.state, isA<LinkFailed>());
      expect((link.state as LinkFailed).reason, allOf(contains('forget'), contains('654321')));
      fa.elapse(const Duration(minutes: 2));
      expect(radio.links, hasLength(1)); // no retry loop
      link.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('Bluetooth off waits and recovers; no permission stops', () {
    fakeAsync((fa) {
      final radio = FakeRadio()..state = BleAvailability.off;
      final link = NodeLink();
      link.connect(BleTransport(node, radio));
      fa.flushMicrotasks();
      expect((link.state as LinkWaiting).reason, contains('Bluetooth is off'));
      radio.state = BleAvailability.on;
      fa.elapse(const Duration(seconds: 3));
      expect(link.state, isA<LinkUp>());
      link.disconnect();
      radio.state = BleAvailability.unauthorized;
      link.connect(BleTransport(node, radio));
      fa.flushMicrotasks();
      expect((link.state as LinkFailed).reason, contains('Nearby devices'));
      link.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });
}
