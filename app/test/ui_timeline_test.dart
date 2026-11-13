// Timeline screen: one feed with filter chips and search; every row reads as
// one phrase with its kind in words; large text does not overflow; the
// controller logs signal changes from live beacons but not replayed ones.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/data/timeline.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:ghostwave_app/src/ui/timeline_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/mesh_controller_test.dart' show answeringNode, makeContainer, settle;
import 'support/journal_seed.dart';

final DateTime now = DateTime(2026, 11, 13, 15);

MeshState seeded() {
  final base = journalSeedState(now);
  return base.copyWith(
    messages: {
      ridge: [
        ChatMessage(
          peer: ridge,
          outgoing: false,
          text: 'camp at the lake',
          at: now.subtract(const Duration(minutes: 30)),
        ),
      ],
    },
    signalLog: [SignalShift(nodeId: rover, fromDbm: -104, toDbm: -118, at: now.subtract(const Duration(minutes: 10)))],
    alerts: [
      SosAlertEntry(src: rover, seq: 1, receivedAt: now.subtract(const Duration(minutes: 5)), text: 'twisted ankle'),
    ],
  );
}

Future<void> _pump(WidgetTester tester, {double text = 1}) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({'units': 'metric'});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => now),
        meshProvider.overrideWith(() => SeededMesh(seeded())),
      ],
      child: MaterialApp(theme: buildGhostWaveTheme(), home: const TimelineScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows every kind with counts and filters by chip', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(find.text('SOS from Rover'), findsOneWidget);
    expect(find.text('Rover weaker by 14 dB'), findsOneWidget);
    expect(find.text('Ridge to you'), findsOneWidget);
    expect(find.text('First heard Rover'), findsOneWidget);
    expect(find.bySemanticsLabel('Signal, 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Alerts, 1'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Alert\. SOS from Rover\. twisted ankle\. ')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Signal change\. Rover weaker by 14 dB\. -104 dBm to -118 dBm\. ')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Alerts 1'));
    await tester.tap(find.text('Alerts 1'));
    await tester.pump();
    expect(find.text('SOS from Rover'), findsNothing);
    expect(find.text('Ridge to you'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'lake');
    await tester.pump();
    expect(find.text('Ridge to you'), findsOneWidget);
    expect(find.text('First heard Rover'), findsNothing);
    handle.dispose();
  });

  testWidgets('tapping a message opens the chat', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Ridge to you'));
    await tester.pumpAndSettle();
    expect(find.byType(TimelineScreen), findsNothing);
  });

  testWidgets('200% text does not overflow', (tester) async {
    await _pump(tester, text: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Timeline'), findsOneWidget);
  });

  testWidgets('empty history explains what will show', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          meshProvider.overrideWith(() => SeededMesh(const MeshState(nodeId: 1))),
        ],
        child: MaterialApp(theme: buildGhostWaveTheme(), home: const TimelineScreen()),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Nothing yet.'), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
  });

  group('controller', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('gwapp-timeline.'));
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('logs a signal change from live beacons, not from replayed events', () async {
      final c = await makeContainer(dir);
      addTearDown(c.dispose);
      final node = answeringNode();
      c.read(nodeLinkProvider).connect(node);
      await settle();
      node.last
        ..send(pb.FromRadio(neighbor: pb.Neighbor(nodeId: rover, rssiDbm: -100)))
        ..send(pb.FromRadio(neighbor: pb.Neighbor(nodeId: rover, rssiDbm: -95)))
        ..send(pb.FromRadio(neighbor: pb.Neighbor(nodeId: rover, rssiDbm: -115)))
        ..send(
          pb.FromRadio(
            text: pb.TextMessage(src: rover, msgId: 9, text: 'old'.codeUnits, rssiDbm: -80),
            replayed: true,
          ),
        );
      await settle();
      final log = c.read(meshProvider).signalLog;
      expect(log, hasLength(1));
      expect((log.single.nodeId, log.single.fromDbm, log.single.toDbm), (rover, -95, -115));
    });
  });
}
