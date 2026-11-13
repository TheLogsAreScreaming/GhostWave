// Home-screen widget text and launch actions: plain words, urgent things first,
// and only the three known places can be opened.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/home_surfaces.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/trip_controller.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/data/trip.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:ghostwave_app/src/link/session.dart';

import '../link/fake_node.dart';

void main() {
  final now = DateTime(2026, 11, 12, 12);
  const ann = 0xA0000001;

  test('only the known places open', () {
    expect(launchActionNamed('sos'), LaunchAction.sos);
    expect(launchActionNamed('checkin'), LaunchAction.checkin);
    expect(launchActionNamed('chats'), LaunchAction.chats);
    expect(launchActionNamed('send-sos'), isNull);
    expect(launchActionNamed(null), isNull);
  });

  test('link states in words', () async {
    final session = LinkSession(await FakeNode().open() as FakeConnection);
    addTearDown(session.close);
    final up = LinkUp('t', pb.NodeInfo(nodeId: 0xb6888904, name: 'Ridge'.codeUnits), session);
    expect(widgetTextFor(up, const MeshState(), const TripState(), now).status, 'Connected to Ridge');
    final unnamed = LinkUp('t', pb.NodeInfo(nodeId: 0xb6888904), session);
    expect(widgetTextFor(unnamed, const MeshState(), const TripState(), now).status, 'Connected to b6888904');
    expect(widgetTextFor(null, const MeshState(), const TripState(), now).status, 'Not connected');
    expect(
      widgetTextFor(
        const LinkWaiting('t', 'x', Duration(seconds: 5)),
        const MeshState(),
        const TripState(),
        now,
      ).status,
      'Radio link dropped, reconnecting',
    );
  });

  test('all quiet, then unread, then urgent things first and flagged', () {
    var t = widgetTextFor(null, const MeshState(), const TripState(), now);
    expect([t.detail, t.alert], ['All quiet', false]);
    t = widgetTextFor(null, const MeshState(unread: {ann: 3}), const TripState(), now);
    expect([t.detail, t.alert], ['3 unread', false]);
    final mesh = MeshState(
      unread: const {ann: 1},
      contacts: {ann: const Contact(nodeId: ann, name: 'Ann')},
      alerts: [SosAlertEntry(src: 7, seq: 1, receivedAt: now)],
    );
    final trip = TripState(
      plan: TripPlan(contacts: const [ann], overdueMinutes: 60, startedAt: now.subtract(const Duration(hours: 2))),
    );
    t = widgetTextFor(null, mesh, trip, now);
    expect(t.detail, '1 SOS alert · Ann overdue · 1 unread');
    expect(t.alert, isTrue);
  });

  test('on a trip: when you last checked in', () {
    final trip = TripState(
      plan: TripPlan(contacts: const [ann], startedAt: now.subtract(const Duration(hours: 1))),
      sent: [SentCheckIn(kind: CheckInKind.ok, at: now.subtract(const Duration(minutes: 12)), messages: const {})],
    );
    expect(widgetTextFor(null, const MeshState(), trip, now).detail, 'Checked in 12 min ago');
    final fresh = TripState(
      plan: TripPlan(contacts: const [ann], startedAt: now),
    );
    expect(widgetTextFor(null, const MeshState(), fresh, now).detail, 'Trip on, no check-in yet');
  });
}
