// Trips: the check-in text round-trips and fits one radio message, check-ins go
// to every trip contact with delivery tracked per person, reminders and overdue
// warnings fire once on a fake clock, and the plan survives a restart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_alerts.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/app/trip_controller.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/data/trip.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/history_keys.dart';
import 'mesh_controller_test.dart' show answeringNode, settle;
import 'phone_qol_test.dart' show RecordingAlerts;

const int ann = 0xA0000001, ben = 0xB0000002;

void main() {
  group('check-in text', () {
    test('round-trips with and without a position, and fits one radio message', () {
      for (final k in CheckInKind.values) {
        final t = checkInText(k, const LatLon(-45.123456, -110.654321));
        expect(utf8.encode(t).length, lessThan(73));
        final back = parseCheckIn(t)!;
        expect(back.kind, k);
        expect(back.pos!.lat, closeTo(-45.12346, 1e-6));
        expect(back.pos!.lon, closeTo(-110.65432, 1e-6));
        expect(parseCheckIn(checkInText(k, null))!.pos, isNull);
      }
      expect(checkInText(CheckInKind.camp, const LatLon(45, -110)), '[Check-in] At camp · 45.00000, -110.00000');
    });

    test('ordinary messages and near-misses are not check-ins', () {
      expect(parseCheckIn('At camp'), isNull);
      expect(parseCheckIn('[Check-in] Partying'), isNull);
      expect(parseCheckIn("[Check-in] I'm OK · 95.0, 10.0")!.pos, isNull, reason: 'impossible latitude dropped');
      expect(parseCheckIn("[Check-in] I'm OK and more"), isNull);
    });
  });

  test('overdue: only on a trip, with a limit, counted from the last check-in or the start', () {
    final start = DateTime(2026, 11, 12, 8);
    final plan = TripPlan(contacts: const [ann], overdueMinutes: 120, startedAt: start);
    ChatMessage from(String text, DateTime at) => ChatMessage(peer: ann, outgoing: false, text: text, at: at);
    expect(isOverdue(plan, ann, const {}, start.add(const Duration(minutes: 119))), isFalse);
    expect(isOverdue(plan, ann, const {}, start.add(const Duration(minutes: 121))), isTrue);
    final msgs = {
      ann: [from(checkInText(CheckInKind.ok, null), start.add(const Duration(minutes: 100)))],
    };
    expect(isOverdue(plan, ann, msgs, start.add(const Duration(minutes: 200))), isFalse);
    expect(isOverdue(plan, ann, msgs, start.add(const Duration(minutes: 221))), isTrue);
    expect(isOverdue(plan.copyWith(clearStart: true), ann, const {}, start.add(const Duration(days: 1))), isFalse);
    expect(isOverdue(plan.copyWith(overdueMinutes: 0), ann, const {}, start.add(const Duration(days: 1))), isFalse);
  });

  group('controller', () {
    late Directory dir;
    late ProviderContainer c;
    late RecordingAlerts alerts;
    late DateTime now;
    late SharedPreferences prefs;

    ProviderContainer make() => ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
        meshAlertsProvider.overrideWithValue(alerts),
        clockProvider.overrideWithValue(() => now),
      ],
    );

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('gwapp-trip.');
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      alerts = RecordingAlerts();
      now = DateTime(2026, 11, 12, 8);
      c = make();
      c.listen(meshProvider, (_, _) {});
      c.listen(tripProvider, (_, _) {});
    });
    tearDown(() async {
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('check-in goes to each trip contact with our position; delivery is per person; resend', () async {
      final node = answeringNode(
        contacts: [
          pb.Contact(nodeId: ann),
          pb.Contact(nodeId: ben),
        ],
      );
      c.read(nodeLinkProvider).connect(node);
      await settle();
      c.read(meshProvider.notifier).noteOwnPosition(const LatLon(45.1, -110.2));
      final trip = c.read(tripProvider.notifier);
      expect(trip.toggleContact(ann) && trip.toggleContact(ben), isTrue);
      expect(await trip.checkIn(CheckInKind.camp), 2);
      await settle();
      final sent = node.requests.where((r) => r.hasSendText()).map((r) => r.sendText).toList();
      expect(sent.map((s) => s.dest).toSet(), {ann, ben});
      expect(utf8.decode(sent.first.text), '[Check-in] At camp · 45.10000, -110.20000');
      final last = c.read(tripProvider).lastSent!;
      final annMsg = c.read(meshProvider).messages[ann]!.single;
      node.last.send(
        pb.FromRadio(
          delivered: pb.Delivered(dest: ann, msgId: annMsg.msgId, clientMsgId: annMsg.clientMsgId),
        ),
      );
      await settle();
      final d = deliveryMap(last, c.read(meshProvider));
      expect(d[ann], MsgState.delivered);
      expect(d[ben], MsgState.sent);
      await trip.resend(last, ben);
      await settle();
      expect(c.read(meshProvider).messages[ben], hasLength(2));
      expect(c.read(tripProvider).lastSent!.messages[ben], isNot(last.messages[ben]));
    });

    test('at most six trip contacts', () {
      final trip = c.read(tripProvider.notifier);
      for (var i = 1; i <= kMaxTripContacts; i++) {
        expect(trip.toggleContact(i), isTrue);
      }
      expect(trip.toggleContact(99), isFalse);
      expect(trip.toggleContact(1), isTrue, reason: 'removing always works');
    });

    test('reminder when a check-in is due, once; overdue warning once, cleared by a check-in', () async {
      final node = answeringNode(
        contacts: [pb.Contact(nodeId: ann, name: 'Ann'.codeUnits)],
      );
      c.read(nodeLinkProvider).connect(node);
      await settle();
      final trip = c.read(tripProvider.notifier);
      trip
        ..toggleContact(ann)
        ..setPlan(c.read(tripProvider).plan.copyWith(reminderMinutes: 60, overdueMinutes: 120))
        ..start();
      now = now.add(const Duration(minutes: 59));
      trip.check();
      expect(alerts.shown, isEmpty);
      now = now.add(const Duration(minutes: 2));
      trip
        ..check()
        ..check();
      expect(alerts.shown.where((s) => s.startsWith('trip Time to check in')), hasLength(1));
      now = now.add(const Duration(minutes: 70)); // 131 min since start, no check-in from Ann
      trip
        ..check()
        ..check();
      expect(alerts.shown.where((s) => s.contains('is overdue')), hasLength(1));
      expect(alerts.shown.last, 'trip Ann is overdue: No check-in since your trip started.');
      node.last.send(
        pb.FromRadio(
          text: pb.TextMessage(src: ann, msgId: 7, text: utf8.encode(checkInText(CheckInKind.ok, null))),
        ),
      );
      await settle();
      expect(isOverdue(c.read(tripProvider).plan, ann, c.read(meshProvider).messages, now), isFalse);
      expect(lastCheckInFrom(ann, c.read(meshProvider).messages)!.$1.kind, CheckInKind.ok);
    });

    test('the plan and sent check-ins survive a restart; a damaged entry does not break the app', () async {
      final trip = c.read(tripProvider.notifier);
      trip
        ..toggleContact(ann)
        ..start();
      await trip.checkIn(CheckInKind.ok);
      final again = make();
      addTearDown(again.dispose);
      final back = again.read(tripProvider);
      expect(back.plan.contacts, [ann]);
      expect(back.plan.active, isTrue);
      expect(back.lastSent!.kind, CheckInKind.ok);
      await prefs.setString('trip_plan_v1', '{not json');
      final broken = make();
      addTearDown(broken.dispose);
      expect(broken.read(tripProvider).plan.contacts, isEmpty);
    });
  });
}
