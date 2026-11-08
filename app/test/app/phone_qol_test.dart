// Phone conveniences: location sharing (throttle + controller), recent nodes,
// and notifications only while backgrounded.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/location_share.dart';
import 'package:ghostwave_app/src/app/mesh_alerts.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:ghostwave_app/src/link/transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../link/fake_node.dart';
import 'mesh_controller_test.dart' show answeringNode, bob, settle;

/// Positions on demand, with a chosen permission answer.
class FakePositionSource implements PositionSource {
  FakePositionSource({this.access = LocationAccess.granted});

  LocationAccess access;
  final StreamController<LatLon> fixes = StreamController<LatLon>.broadcast();
  int asks = 0;
  int opened = 0;

  bool get watching => fixes.hasListener;

  @override
  Future<LocationAccess> ensureAccess() async {
    asks++;
    return access;
  }

  @override
  Stream<LatLon> watch({required int distanceFilterM}) => fixes.stream;

  @override
  Future<void> openSettings(LocationAccess why) async => opened++;
}

class RecordingAlerts implements MeshAlerts {
  final List<String> shown = <String>[];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> textReceived({required int peer, required String from, required String text}) async =>
      shown.add('text $from: $text');

  @override
  Future<void> sosReceived({required int src, required String from, required String text}) async =>
      shown.add('sos $from: $text');

  @override
  Future<void> backgroundLinkStopped(String reason) async => shown.add('stopped: $reason');
}

/// [answeringNode] that also accepts `SetOwnPosition`.
FakeNode positionNode() {
  final node = answeringNode();
  node.onRequest.listen((e) {
    final (c, r) = e;
    if (r.hasSetOwnPosition()) c.send(pb.FromRadio(reqId: r.reqId, ok: pb.Ok()));
  });
  return node;
}

List<pb.SetOwnPosition> sentPositions(FakeNode node) => [
  for (final r in node.requests)
    if (r.hasSetOwnPosition()) r.setOwnPosition,
];

/// A point [metres] north of [p].
LatLon north(LatLon p, double metres) => LatLon(p.lat + metres / 111195.0, p.lon);

const LatLon home = LatLon(46.87, -113.99);

void main() {
  group('LatLon.distanceTo', () {
    test('one degree of latitude is about 111 km', () {
      expect(const LatLon(0, 0).distanceTo(const LatLon(1, 0)), closeTo(111195, 5));
    });
    test('short distances', () {
      expect(home.distanceTo(north(home, 50)), closeTo(50, 0.5));
      expect(home.distanceTo(home), 0);
    });
  });

  group('PositionThrottle', () {
    final t0 = DateTime.utc(2026, 11, 8, 12);
    test('first fix goes out, small moves are skipped', () {
      final t = PositionThrottle();
      expect(t.offer(home, t0), isA<SendNow>());
      t.sent(home, t0);
      expect(t.offer(north(home, 20), t0.add(const Duration(minutes: 5))), isA<NoSend>());
    });
    test('50 m of movement, at most every 30 s', () {
      final t = PositionThrottle()..sent(home, t0);
      final far = north(home, 80);
      final early = t.offer(far, t0.add(const Duration(seconds: 10)));
      expect(early, isA<SendAfter>());
      expect((early as SendAfter).wait, const Duration(seconds: 20));
      expect(t.offer(far, t0.add(const Duration(seconds: 30))), isA<SendNow>());
    });
    test('reset sends the next fix at once', () {
      final t = PositionThrottle()..sent(home, t0);
      t.reset();
      expect(t.offer(home, t0.add(const Duration(seconds: 1))), isA<SendNow>());
    });
  });

  group('recent nodes', () {
    Future<ProviderContainer> container([Map<String, Object> prefs = const {}]) async {
      SharedPreferences.setMockInitialValues(prefs);
      final p = await SharedPreferences.getInstance();
      return ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(p)]);
    }

    test('newest first, capped, labelled, removable, saved', () async {
      final c = await container();
      addTearDown(c.dispose);
      final n = c.read(recentNodesProvider.notifier);
      for (var i = 0; i < 8; i++) {
        n.touch('10.0.0.$i:47800', now: DateTime(2026, 11, 8, 12, i));
      }
      n.touch('10.0.0.5:47800', now: DateTime(2026, 11, 8, 13));
      var list = c.read(recentNodesProvider);
      expect(list, hasLength(RecentNodesNotifier.max));
      expect(list.first.address, '10.0.0.5:47800');
      expect(list.map((r) => r.address), isNot(contains('10.0.0.0:47800')));

      n.label('10.0.0.5:47800', name: 'N1', nodeId: 0x9d66916b);
      expect(c.read(recentNodesProvider).first.label, 'N1 (9d66916b)');
      n.remove('10.0.0.7:47800');
      list = c.read(recentNodesProvider);
      expect(list.map((r) => r.address), isNot(contains('10.0.0.7:47800')));

      // a fresh container reads the same saved list
      final saved = (await SharedPreferences.getInstance()).getString('recent_nodes')!;
      final c2 = await container({'recent_nodes': saved});
      addTearDown(c2.dispose);
      expect(c2.read(recentNodesProvider).first.label, 'N1 (9d66916b)');
      expect(c2.read(recentNodesProvider), hasLength(list.length));
    });

    test('a malformed saved list is ignored', () async {
      final c = await container({'recent_nodes': '{not json'});
      addTearDown(c.dispose);
      expect(c.read(recentNodesProvider), isEmpty);
      final c2 = await container({
        'recent_nodes': jsonEncode([
          {'a': 1},
          {'a': 'x:1', 't': 5},
        ]),
      });
      addTearDown(c2.dispose);
      expect(c2.read(recentNodesProvider).single.address, 'x:1');
    });

    test('connecting labels the entry with the node that answered', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final node = FakeNode();
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          transportFactoryProvider.overrideWithValue((_) => node),
        ],
      );
      addTearDown(c.dispose);
      c.listen(nodeAddressProvider, (_, _) {});
      await c.read(nodeAddressProvider.notifier).connectTo(TcpAddress.tryParse('192.168.1.20:47800')!);
      expect(c.read(recentNodesProvider).first.label, '192.168.1.20:47800');
      await settle();
      expect(c.read(recentNodesProvider).first.label, 'N1 (11223344)');
      expect(c.read(recentNodesProvider).first.address, '192.168.1.20:47800');
    });
  });

  group('location sharing', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('gwapp-loc.'));
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    Future<(ProviderContainer, FakePositionSource)> setUpShare({
      LocationAccess access = LocationAccess.granted,
      DateTime Function()? clock,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final source = FakePositionSource(access: access);
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          meshStoreProvider.overrideWithValue(MeshStore(dir)),
          positionSourceProvider.overrideWithValue(source),
          if (clock != null) clockProvider.overrideWithValue(clock),
        ],
      );
      c.listen(meshProvider, (_, _) {});
      c.listen(locationShareProvider, (_, _) {});
      return (c, source);
    }

    test('off by default: no permission prompt, no GPS', () async {
      final (c, source) = await setUpShare();
      addTearDown(c.dispose);
      c.read(nodeLinkProvider).connect(positionNode());
      await settle();
      expect(source.asks, 0);
      expect(source.watching, isFalse);
    });

    test('on: sends the first fix, skips small moves, stops in the background', () async {
      var now = DateTime.utc(2026, 11, 8, 12);
      final (c, source) = await setUpShare(clock: () => now);
      addTearDown(c.dispose);
      final node = positionNode();
      c.read(nodeLinkProvider).connect(node);
      await settle();
      await c.read(locationShareProvider.notifier).setEnabled(enabled: true);
      await settle();
      expect(source.watching, isTrue);
      expect(c.read(locationShareProvider).active, isTrue);

      source.fixes.add(home);
      await settle();
      expect(sentPositions(node).single.pos.latE7, (home.lat * 1e7).round());
      expect(c.read(locationShareProvider).lastSent, home);
      expect(c.read(meshProvider).ownPos, home);

      now = now.add(const Duration(minutes: 2));
      source.fixes.add(north(home, 20)); // under 50 m: skipped
      await settle();
      expect(sentPositions(node), hasLength(1));

      source.fixes.add(north(home, 120)); // 30 s passed and far enough
      await settle();
      expect(sentPositions(node), hasLength(2));

      c.read(appForegroundProvider.notifier).set(foreground: false);
      await settle();
      expect(source.watching, isFalse);
      expect(c.read(locationShareProvider).active, isFalse);

      c.read(appForegroundProvider.notifier).set(foreground: true);
      await settle();
      expect(source.watching, isTrue);
    });

    test('a fast move waits for the 30 s limit, then sends the latest fix', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 11, 8, 12);
        late ProviderContainer c;
        late FakePositionSource source;
        late FakeNode node;
        unawaited(
          setUpShare(clock: () => start.add(async.elapsed)).then((v) {
            (c, source) = v;
            node = positionNode();
            c.read(nodeLinkProvider).connect(node);
          }),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        unawaited(c.read(locationShareProvider.notifier).setEnabled(enabled: true));
        async.elapse(const Duration(milliseconds: 10));
        source.fixes.add(home);
        async.elapse(const Duration(seconds: 5));
        source.fixes.add(north(home, 100));
        async.elapse(const Duration(seconds: 1));
        source.fixes.add(north(home, 200));
        async.elapse(const Duration(seconds: 10));
        expect(sentPositions(node), hasLength(1), reason: 'still inside the 30 s window');
        async.elapse(const Duration(seconds: 20));
        expect(sentPositions(node), hasLength(2));
        expect(sentPositions(node).last.pos.latE7, (north(home, 200).lat * 1e7).round());
        c.dispose();
        async.flushTimers();
      });
    });

    test('permission refused: nothing is watched, the reason is shown', () async {
      final (c, source) = await setUpShare(access: LocationAccess.deniedForever);
      addTearDown(c.dispose);
      c.read(nodeLinkProvider).connect(positionNode());
      await settle();
      await c.read(locationShareProvider.notifier).setEnabled(enabled: true);
      await settle();
      expect(source.watching, isFalse);
      expect(c.read(locationShareProvider).access, LocationAccess.deniedForever);
      await c.read(locationShareProvider.notifier).openSettings();
      expect(source.opened, 1);
    });

    test('the choice is saved', () async {
      final (c, _) = await setUpShare();
      addTearDown(c.dispose);
      await c.read(locationShareProvider.notifier).setEnabled(enabled: true);
      expect(c.read(sharedPrefsProvider).getBool('share_location'), isTrue);
    });
  });

  group('notifications', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('gwapp-notif.'));
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('only while backgrounded; one per new SOS', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final alerts = RecordingAlerts();
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          meshStoreProvider.overrideWithValue(MeshStore(dir)),
          meshAlertsProvider.overrideWithValue(alerts),
        ],
      );
      addTearDown(c.dispose);
      c.listen(meshProvider, (_, _) {});
      final node = answeringNode(
        contacts: [pb.Contact(nodeId: bob, name: 'bob'.codeUnits, pinned: true)],
      );
      c.read(nodeLinkProvider).connect(node);
      await settle();

      node.last.send(
        pb.FromRadio(
          text: pb.TextMessage(src: bob, msgId: 1, text: utf8.encode('hi')),
        ),
      );
      await settle();
      expect(alerts.shown, isEmpty, reason: 'foreground: the app shows it');

      c.read(appForegroundProvider.notifier).set(foreground: false);
      node.last.send(
        pb.FromRadio(
          text: pb.TextMessage(src: bob, msgId: 2, text: utf8.encode('still there?')),
        ),
      );
      node.last.send(
        pb.FromRadio(
          sos: pb.SosAlert(src: bob, seq: 1, text: utf8.encode('hurt')),
        ),
      );
      node.last.send(
        pb.FromRadio(
          sos: pb.SosAlert(src: bob, seq: 2, text: utf8.encode('hurt')),
        ),
      );
      await settle();
      expect(alerts.shown, ['text bob: still there?', 'sos bob: hurt']);
    });
  });
}
