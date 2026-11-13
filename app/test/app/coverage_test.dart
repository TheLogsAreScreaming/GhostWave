// Coverage walks: results come only from real receipts (pending, then failed
// after the timeout, a late receipt still counts), pings need location and a
// fresh fix, walks survive a restart, and the receiving phone stays quiet.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/coverage.dart';
import 'package:ghostwave_app/src/app/location_share.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/coverage_sample.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/history_keys.dart';
import 'mesh_controller_test.dart' show answeringNode, settle;
import 'phone_qol_test.dart' show FakePositionSource;

const int base = 0xB0000002;

void main() {
  final t0 = DateTime.utc(2026, 11, 12, 12);

  group('results from receipts only', () {
    final walk = CoverageWalk(id: 'w1', dest: base, startedAt: t0, intervalS: 30);
    final ping = CoveragePing(n: 1, clientMsgId: 77, pos: const LatLon(45, -110), at: t0);
    Map<int, List<ChatMessage>> msg(MsgState st, {int? rssi}) => {
      base: [
        ChatMessage(
          peer: base,
          outgoing: true,
          text: '[Coverage] 1',
          at: t0,
          state: st,
          clientMsgId: 77,
          rssiDbm: rssi,
        ),
      ],
    };

    test('pending, then failed after the timeout; a late receipt still counts', () {
      expect(
        sampleOf(walk, ping, msg(MsgState.sent), t0.add(const Duration(minutes: 1))).outcome,
        CoverageOutcome.pending,
      );
      expect(
        sampleOf(walk, ping, msg(MsgState.sent), t0.add(const Duration(minutes: 4))).outcome,
        CoverageOutcome.failed,
      );
      final late = sampleOf(walk, ping, msg(MsgState.delivered, rssi: -104), t0.add(const Duration(minutes: 9)));
      expect([late.outcome, late.rssiDbm, late.mapClass], [CoverageOutcome.delivered, -104, 'fair']);
    });

    test('no signal is invented: failed or unmeasured have none', () {
      expect(sampleOf(walk, ping, msg(MsgState.failed, rssi: -80), t0).rssiDbm, isNull);
      expect(sampleOf(walk, ping, msg(MsgState.delivered), t0).mapClass, 'delivered-unmeasured');
      expect(sampleOf(walk, ping, const {}, t0.add(const Duration(minutes: 5))).outcome, CoverageOutcome.failed);
    });

    test('walk JSON round trip', () {
      final w = walk.copyWith(pings: [ping], skippedNoFix: 2);
      final back = CoverageWalk.fromJson(jsonDecode(jsonEncode(w.toJson())))!;
      expect([back.id, back.dest, back.pings.single.clientMsgId, back.skippedNoFix], ['w1', base, 77, 2]);
      expect(CoverageWalk.fromJson({'id': 1}), isNull);
    });
  });

  group('walking', () {
    late Directory dir;
    late SharedPreferences prefs;
    late FakePositionSource gps;
    late DateTime now;

    ProviderContainer make() => ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
        coverageStoreProvider.overrideWithValue(CoverageStore(dir)),
        positionSourceProvider.overrideWithValue(gps),
        clockProvider.overrideWithValue(() => now),
      ],
    );

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('gwapp-coverage.');
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      gps = FakePositionSource();
      now = t0;
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    Future<ProviderContainer> connected() async {
      final c = make();
      c
        ..listen(meshProvider, (_, _) {})
        ..listen(coverageProvider, (_, _) {});
      c.read(nodeLinkProvider).connect(answeringNode(contacts: [pb.Contact(nodeId: base)]));
      await settle();
      return c;
    }

    test('no location: no walk', () async {
      gps.access = LocationAccess.denied;
      final c = await connected();
      addTearDown(c.dispose);
      expect(await c.read(coverageProvider.notifier).start(base, 30), isFalse);
      expect(c.read(coverageProvider).running, isNull);
    });

    test('pings need a fresh fix; a sent ping is an encrypted DM with its number', () async {
      final c = await connected();
      addTearDown(c.dispose);
      final cov = c.read(coverageProvider.notifier);
      expect(await cov.start(base, 30), isTrue);
      await cov.ping();
      expect(c.read(coverageProvider).running!.skippedNoFix, 1, reason: 'no fix yet');
      cov.noteFix(const LatLon(45.1, -110.2), at: now);
      now = now.add(const Duration(seconds: 40));
      await cov.ping();
      expect(c.read(coverageProvider).running!.skippedNoFix, 2, reason: 'a 40 s old fix is stale');
      cov.noteFix(const LatLon(45.1, -110.2), at: now);
      await cov.ping();
      await settle();
      final walk = c.read(coverageProvider).running!;
      expect(walk.pings.single.pos.lat, 45.1);
      expect(c.read(meshProvider).messages[base]!.single.text, '[Coverage] 1');
      cov.stop();
      expect(c.read(coverageProvider).running, isNull);
    });

    test('walks survive a restart; one left running is ended', () async {
      final c = await connected();
      final cov = c.read(coverageProvider.notifier);
      await cov.start(base, 60);
      await c.read(coverageStoreProvider)!.idle;
      c.dispose();
      final again = make()..listen(coverageProvider, (_, _) {});
      addTearDown(again.dispose);
      await settle();
      final walks = again.read(coverageProvider).walks;
      expect(walks.single.intervalS, 60);
      expect(walks.single.running, isFalse);
    });

    test('the receiving phone: a ping lands in the chat without unread or notification', () async {
      final c = await connected();
      addTearDown(c.dispose);
      final node = answeringNode();
      c.read(nodeLinkProvider).connect(node);
      await settle();
      node.last.send(
        pb.FromRadio(
          text: pb.TextMessage(src: base, msgId: 3, text: utf8.encode('[Coverage] 4')),
        ),
      );
      await settle();
      expect(c.read(meshProvider).messages[base]!.single.text, '[Coverage] 4');
      expect(c.read(meshProvider).unread[base] ?? 0, 0);
    });
  });
}
