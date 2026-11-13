// Node journal: the controller logs every node heard; the screens show the
// labels with their evidence, tags and notes; each node gets the same
// generated mark every time.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/node_journal.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:ghostwave_app/src/ui/node_journal_screen.dart';
import 'package:ghostwave_app/src/ui/node_mark.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/mesh_controller_test.dart' show answeringNode, makeContainer, settle;
import 'support/journal_seed.dart';

final DateTime now = DateTime(2026, 11, 13, 15);

Future<void> _pump(WidgetTester tester, Widget home, {double text = 1}) async {
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
        meshProvider.overrideWith(() => SeededMesh(journalSeedState(now))),
      ],
      child: MaterialApp(theme: buildGhostWaveTheme(), home: home),
    ),
  );
  await tester.pump();
}

void main() {
  group('generated mark', () {
    test('is a fixed function of the node ID (golden vector)', () {
      final s = NodeMarkSpec.forNode(ridge);
      expect(s.hue, 292);
      expect(s.accentHue, 102);
      expect(s.core, MarkCore.triangle);
      expect(s.coreTurn, 0.298);
      expect(s.moonTurn, 0.791);
      expect([for (final r in s.rings) r.arcs], [1, 1, 1]);
      expect([for (final r in s.rings) r.turn], [0.673, 0.232, 0.161]);
      expect(s.rings.last.gap, closeTo(0.47, 1e-9));
      final one = NodeMarkSpec.forNode(1);
      expect((one.hue, one.core, one.rings.length), (198, MarkCore.hollow, 2));
    });

    test('same ID, same mark; different IDs, different marks', () {
      expect(NodeMarkSpec.forNode(ridge), NodeMarkSpec.forNode(ridge));
      final seen = {for (var i = 0; i < 500; i++) NodeMarkSpec.forNode(i * 2654435761 & 0xFFFFFFFF)};
      expect(seen.length, 500);
    });

    testWidgets('decorative unless given a label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              NodeMark(nodeId: ridge),
              NodeMark(nodeId: rover, semanticLabel: 'Generated mark for node 0c0ffee0'),
            ],
          ),
        ),
      );
      expect(find.bySemanticsLabel('Generated mark for node 0c0ffee0'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(NodeMark).last),
        isSemantics(label: 'Generated mark for node 0c0ffee0', isImage: true),
      );
      handle.dispose();
    });
  });

  group('logging', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('gw-journal-test.'));
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('beacons, messages and identities are logged; our own node is not', () async {
      final c = await makeContainer(dir);
      addTearDown(c.dispose);
      final node = answeringNode();
      c.read(nodeLinkProvider).connect(node);
      await settle();
      final own = c.read(meshProvider).nodeId!;
      node.last
        ..send(
          pb.FromRadio(
            neighbor: pb.Neighbor(nodeId: rover, rssiDbm: -97, pos: pb.Position(latE7: 450000000, lonE7: -1100000000)),
          ),
        )
        ..send(
          pb.FromRadio(
            text: pb.TextMessage(src: rover, msgId: 5, text: 'hi'.codeUnits),
          ),
        )
        // the same message replayed later is counted once
        ..send(
          pb.FromRadio(
            text: pb.TextMessage(src: rover, msgId: 5, text: 'hi'.codeUnits),
            replayed: true,
          ),
        )
        ..send(
          pb.FromRadio(
            peerIdent: pb.PeerIdent(nodeId: ridge, name: 'Ridge'.codeUnits),
          ),
        )
        ..send(pb.FromRadio(neighbor: pb.Neighbor(nodeId: own)));
      await settle();
      final j = c.read(meshProvider).journal;
      expect(j.entries.keys, unorderedEquals([rover, ridge]));
      final e = j.entries[rover]!;
      expect(e.via, {HeardVia.beacon: 1, HeardVia.direct: 1});
      expect(e.lastRssi, -97);
      expect(e.lastPos, const LatLon(45, -110));
      expect(j.entries[ridge]!.name, 'Ridge');
      expect(j.listened, isNotEmpty);
    });

    test('a message replayed by the node counts the sender but no hour', () async {
      final c = await makeContainer(dir);
      addTearDown(c.dispose);
      final node = answeringNode();
      c.read(nodeLinkProvider).connect(node);
      await settle();
      node.last.send(
        pb.FromRadio(
          text: pb.TextMessage(src: rover, msgId: 9, text: 'x'.codeUnits),
          replayed: true,
        ),
      );
      await settle();
      final e = c.read(meshProvider).journal.entries[rover]!;
      expect(e.timesHeard, 1);
      expect(e.hours, isEmpty);
    });

    test('the journal, tags and notes survive a restart', () async {
      final node = answeringNode();
      var c = await makeContainer(dir);
      c.read(nodeLinkProvider).connect(node);
      await settle();
      node.last.send(pb.FromRadio(neighbor: pb.Neighbor(nodeId: rover)));
      await settle();
      c.read(meshProvider.notifier)
        ..setJournalTags(rover, ['truck'])
        ..setJournalNote(rover, 'Forest service truck');
      c.read(meshProvider.notifier).flush();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      c.dispose();

      c = await makeContainer(dir);
      addTearDown(c.dispose);
      c.read(nodeLinkProvider).connect(answeringNode()); // same node ID
      await settle();
      final e = c.read(meshProvider).journal.entries[rover]!;
      expect(e.tags, ['truck']);
      expect(e.note, 'Forest service truck');
      c.read(meshProvider.notifier).forgetJournalEntry(rover);
      expect(c.read(meshProvider).journal.entries, isEmpty);
    });
  });

  group('screens', () {
    testWidgets('list: newest first, headline label with confidence, tags, filters', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const NodeJournalScreen());
      expect(
        find.text(
          '2 logged · 2 heard today. Labels are guesses from what this app has heard; tap a node to see '
          'the evidence.',
        ),
        findsOneWidget,
      );
      expect(find.text('Rover'), findsOneWidget, reason: 'announced name used when not a contact');
      expect(find.text('Roamer · probable (68%)'), findsOneWidget);
      expect(find.text('Ridge'), findsOneWidget, reason: 'contact name wins');
      expect(find.text('Always-on relay · likely (100%)'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Tag: lookout')), findsOneWidget);
      expect(find.byTooltip('Has a note'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Ridge')).dy,
        lessThan(tester.getTopLeft(find.text('Rover')).dy),
        reason: 'Ridge was heard most recently',
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Always-on relay'));
      await tester.pump();
      expect(find.text('Rover'), findsNothing);
      expect(find.text('Ridge'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'solar');
      await tester.pump();
      expect(find.text('Ridge'), findsOneWidget, reason: 'notes are searched');
      expect(find.text('Rover'), findsNothing);
      handle.dispose();
    });

    testWidgets('filter chips read their counts', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const NodeJournalScreen());
      expect(find.bySemanticsLabel('Always-on relay, 1'), findsOneWidget);
      expect(find.bySemanticsLabel('All, 2'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('detail: evidence, confidence read aloud, record, tags and notes', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const JournalNodeScreen(nodeId: rover));
      expect(find.bySemanticsLabel('Generated mark for node 0c0ffee0'), findsOneWidget);
      expect(find.text('Roamer'), findsOneWidget);
      expect(find.text('Its reported positions span 4.0 km'), findsOneWidget);
      expect(find.bySemanticsLabel('Confidence 68 percent, probable'), findsOneWidget);
      expect(find.bySemanticsLabel('Times heard: 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Signal: last -104 dBm, good · best -104 dBm'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Add tag'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Add tag'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'vehicle'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'vehicle'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove tag vehicle'));
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'vehicle'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Your note'), 'Ranger patrol');
      await tester.pump();
      final container = ProviderScope.containerOf(tester.element(find.byType(JournalNodeScreen)));
      expect(container.read(meshProvider).journal.entries[rover]!.note, 'Ranger patrol');
      handle.dispose();
      await tester.pump(const Duration(seconds: 1)); // let the save timer run
    });

    testWidgets('forget asks first, then removes the node', (tester) async {
      await _pump(tester, const NodeJournalScreen());
      await tester.tap(find.text('Rover'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Forget this node'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Forget this node'));
      await tester.pumpAndSettle();
      expect(find.text('Forget Rover?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Forget'));
      await tester.pumpAndSettle();
      expect(find.byType(JournalNodeScreen), findsNothing);
      expect(find.text('Rover'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('large text: no overflow on list or detail', (tester) async {
      await _pump(tester, const NodeJournalScreen(), text: 2);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Ridge'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Ridge'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Always-on relay'), findsOneWidget);
    });

    testWidgets('empty journal explains what will appear', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            meshProvider.overrideWith(() => SeededMesh(const MeshState())),
          ],
          child: MaterialApp(theme: buildGhostWaveTheme(), home: const NodeJournalScreen()),
        ),
      );
      expect(find.textContaining('Nothing logged yet.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
