// Local alerts wired to the app: battery only from a real reading, new nodes
// after the connect baseline (and only if turned on), quiet trip contacts
// while a trip is on, names not node numbers, and the settings switches.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/local_alerts.dart';
import 'package:ghostwave_app/src/app/mesh_alerts.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/app/trip_controller.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:ghostwave_app/src/link/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../link/fake_node.dart';
import '../support/history_keys.dart';
import 'mesh_controller_test.dart' show answeringNode, settle;
import 'phone_qol_test.dart' show RecordingAlerts;

const int ann = 0xA0000001, ben = 0xB0000002;

void main() {
  late Directory dir;
  late ProviderContainer c;
  late RecordingAlerts alerts;
  late DateTime now;
  late LocalAlertsRunner run;
  late LinkSession session;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-alerts.');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    alerts = RecordingAlerts();
    now = DateTime(2026, 11, 12, 8);
    c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
        meshAlertsProvider.overrideWithValue(alerts),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    c.listen(meshProvider, (_, _) {});
    c.listen(tripProvider, (_, _) {});
    // the node's contact list gives the names alerts use
    c
        .read(nodeLinkProvider)
        .connect(
          answeringNode(
            contacts: [
              pb.Contact(nodeId: ann, name: 'Ann'.codeUnits),
              pb.Contact(nodeId: ben, name: 'Ben'.codeUnits),
            ],
          ),
        );
    await settle();
    run = c.read(_runner);
    session = LinkSession(await FakeNode().open() as FakeConnection);
  });
  tearDown(() async {
    await session.close();
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  MeshState heard(Map<int, DateTime> seen) => MeshState(
    contacts: {
      ann: const Contact(nodeId: ann, name: 'Ann'),
      ben: const Contact(nodeId: ben, name: 'Ben'),
    },
    neighbors: {for (final MapEntry(:key, :value) in seen.entries) key: Neighbor(nodeId: key, lastSeen: value)},
  );

  test('battery: only from a real reading, at 20 % then 10 %, once each', () {
    run
      ..onStatus(pb.Status()) // no battery reading at all
      ..onStatus(pb.Status(batteryPct: 55))
      ..onStatus(pb.Status(batteryPct: 20))
      ..onStatus(pb.Status(batteryPct: 19))
      ..onStatus(pb.Status(batteryPct: 9));
    expect(alerts.shown, [
      'radio Radio battery low: Radio battery at 20%. Charge it or swap batteries soon.',
      'radio Radio battery very low: Radio battery at 9%. Charge it or swap batteries soon.',
    ]);
  });

  test('battery switch off: nothing', () {
    final n = c.read(localAlertSettingsProvider.notifier);
    n.set(c.read(localAlertSettingsProvider).copyWith(battery: false));
    run.onStatus(pb.Status(batteryPct: 5));
    expect(alerts.shown, isEmpty);
  });

  test('new nodes: off by default; when on, not for the first two minutes after connecting', () {
    run.onLinkState(const LinkConnecting('t', 1));
    final up = LinkUp('t', pb.NodeInfo(), session);
    run
      ..onLinkState(up)
      ..onNeighbors(heard({ann: now}));
    expect(alerts.shown, isEmpty, reason: 'off by default');
    c.read(localAlertSettingsProvider.notifier).set(const LocalAlertSettings(newNode: true));
    run.onNeighbors(heard({ann: now, ben: now}));
    expect(alerts.shown, isEmpty, reason: 'still in the baseline');
    now = now.add(const Duration(minutes: 3));
    run.onNeighbors(heard({ann: now, ben: now}));
    expect(alerts.shown, isEmpty, reason: 'both were baseline nodes');
    run.onLinkState(up);
    now = now.add(const Duration(minutes: 3));
    run.onNeighbors(heard({ann: now}));
    expect(alerts.shown, ['radio New node heard: Ann is in radio range.']);
  });

  test('quiet trip contact: only on a trip, by name, once until heard again', () async {
    final trip = c.read(tripProvider.notifier)..toggleContact(ann);
    run
      ..onLinkState(LinkUp('t', pb.NodeInfo(), session))
      ..onNeighbors(heard({ann: now}));
    now = now.add(const Duration(minutes: 31));
    run.tick();
    expect(alerts.shown, isEmpty, reason: 'no trip on');
    trip.start();
    run
      ..tick()
      ..tick();
    expect(alerts.shown, [
      'trip Ann has gone quiet: Your radio has not heard them for over 30 minutes. They may be out of range.',
    ]);
    run.onLinkState(const LinkWaiting('t', 'x', Duration(seconds: 5)));
    now = now.add(const Duration(hours: 1));
    run.tick();
    expect(alerts.shown, hasLength(1), reason: 'not while our own radio is disconnected');
  });
}

final _runner = Provider<LocalAlertsRunner>(LocalAlertsRunner.new);
