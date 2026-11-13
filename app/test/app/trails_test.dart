// Trails: recorded only for trip contacts and you during a trip, thinned and
// capped, kept in the encrypted history across a restart, cleared on request.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/app/trails.dart';
import 'package:ghostwave_app/src/app/trip_controller.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/data/team_trails.dart';
import 'package:ghostwave_app/src/data/trip.dart';
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/history_keys.dart';
import 'mesh_controller_test.dart' show answeringNode, settle;

const int ann = 0xA0000001, ben = 0xB0000002, me = 0x11223344;

void main() {
  final now = DateTime.utc(2026, 11, 12, 12);

  group('who is recorded', () {
    final mesh = MeshState(
      nodeId: me,
      ownPos: const LatLon(45, -110),
      neighbors: {
        ann: Neighbor(nodeId: ann, lastSeen: now, pos: const LatLon(45.01, -110)),
        ben: Neighbor(nodeId: ben, lastSeen: now, pos: const LatLon(45.02, -110)),
      },
      messages: {
        ann: [
          ChatMessage(
            peer: ann,
            outgoing: false,
            text: checkInText(CheckInKind.camp, const LatLon(45.005, -110.001)),
            at: now.subtract(const Duration(minutes: 30)),
          ),
        ],
      },
    );
    List<(int, double)> run(TripState trip) {
      final out = <(int, double)>[];
      recordTrailsFrom(mesh, trip, now, (id, lat, lon, at) => out.add((id, lat)));
      return out;
    }

    test('nothing without a trip', () {
      expect(run(const TripState(plan: TripPlan(contacts: [ann]))), isEmpty);
    });

    test('during a trip: trip contacts (beacon and check-in) and you, nobody else', () {
      final got = run(
        TripState(
          plan: TripPlan(contacts: const [ann], startedAt: now),
        ),
      );
      expect(got, containsAll([(ann, 45.01), (ann, 45.005), (me, 45.0)]));
      expect(got.where((e) => e.$1 == ben), isEmpty);
    });
  });

  group('trail rules', () {
    TrailFix at(int minutes, double lat) => TrailFix(
      latitude: lat,
      longitude: -110,
      at: now.subtract(Duration(minutes: minutes)),
    );

    test('a point close in time and place is skipped; a real move is kept', () {
      var t = addTrailFix(const [], at(10, 45.0), now);
      t = addTrailFix(
        t,
        TrailFix(latitude: 45.00001, longitude: -110, at: t.last.at.add(const Duration(seconds: 30))),
        now,
      );
      expect(t, hasLength(1), reason: '30 s and about 1 m later');
      t = addTrailFix(t, at(9, 45.001), now); // ~110 m
      expect(t, hasLength(2));
    });

    test('older than 24 hours is dropped; the cap keeps the newest', () {
      expect(addTrailFix(const [], at(25 * 60, 45), now), isEmpty);
      var t = const <TrailFix>[];
      for (var i = kMaxTrailPoints + 10; i > 0; i--) {
        t = addTrailFix(t, at(i, 45 + i / 1000), now);
      }
      expect(t, hasLength(kMaxTrailPoints));
      expect(t.last.at, now.subtract(const Duration(minutes: 1)));
    });

    test('compact JSON round trip; junk is dropped', () {
      final f = at(5, 45.123456);
      final back = TrailFix.fromJson(f.toJson())!;
      expect([back.latitude, back.longitude, back.at], [f.latitude, f.longitude, f.at]);
      expect(TrailFix.fromJson([95, 0, 0]), isNull);
      expect(TrailFix.fromJson('x'), isNull);
    });
  });

  group('kept with the encrypted history', () {
    late Directory dir;
    late SharedPreferences prefs;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('gwapp-trails.');
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    Future<ProviderContainer> connected() async {
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
          clockProvider.overrideWithValue(() => now),
        ],
      );
      c.listen(meshProvider, (_, _) {});
      c.read(nodeLinkProvider).connect(answeringNode());
      await settle();
      return c;
    }

    test('survives a restart; Clear trails empties it', () async {
      final c = await connected();
      final ctl = c.read(meshProvider.notifier)
        ..recordTrail(ann, const LatLon(45, -110), now.subtract(const Duration(minutes: 20)))
        ..recordTrail(ann, const LatLon(45.01, -110), now.subtract(const Duration(minutes: 10)));
      ctl.flush();
      await c.read(meshStoreProvider)!.idle;
      c.dispose();

      final again = await connected();
      addTearDown(again.dispose);
      expect(again.read(meshProvider).trails[ann], hasLength(2));
      again.read(meshProvider.notifier).clearTrails();
      expect(again.read(meshProvider).trails, isEmpty);
    });

    test('the recorder follows a trip as it starts', () async {
      final c = await connected();
      addTearDown(c.dispose);
      c
        ..listen(tripProvider, (_, _) {})
        ..listen(trailsRecorderProvider, (_, _) {});
      c.read(meshProvider.notifier).noteOwnPosition(const LatLon(45, -110));
      expect(c.read(meshProvider).trails, isEmpty, reason: 'no trip yet');
      c.read(tripProvider.notifier)
        ..toggleContact(ann)
        ..start();
      await settle();
      expect(c.read(meshProvider).trails.keys, [c.read(meshProvider).nodeId]);
    });
  });
}
