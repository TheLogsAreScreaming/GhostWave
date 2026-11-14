// Node details: name and ID, last heard and whether directly, position with
// distance and bearing, the signal graph (and its readings as text), and
// telemetry only when a node reported it. Screen reader labels and 200 % text.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/location_share.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/data/node_journal.dart';
import 'package:ghostwave_app/src/data/timeline.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:ghostwave_app/src/ui/node_details_screen.dart';
import 'package:ghostwave_app/src/ui/node_journal_screen.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/journal_seed.dart' show SeededMesh;

const int me = 0x11223344;
const int ridge = 0x9F219DBB;
const int quiet = 0x0C0FFEE0;
final DateTime now = DateTime(2026, 11, 14, 12);

class _NoShare extends LocationShareController {
  @override
  LocationShareState build() => const LocationShareState(enabled: false);
}

MeshState seed({bool withTelemetry = true}) => MeshState(
  nodeId: me,
  ownPos: const LatLon(45, -110),
  contacts: {
    ridge: Contact(nodeId: ridge, name: 'Ridge', pinned: true, lastSeen: now.subtract(const Duration(minutes: 3))),
  },
  neighbors: {
    ridge: Neighbor(
      nodeId: ridge,
      lastSeen: now.subtract(const Duration(minutes: 3)),
      pos: const LatLon(45.009, -110), // ~1 km north
      rssiDbm: -97,
    ),
  },
  messages: {
    ridge: [
      ChatMessage(
        peer: ridge,
        outgoing: false,
        text: 'camp',
        at: now.subtract(const Duration(hours: 2)),
        rssiDbm: -112,
      ),
    ],
  },
  signalLog: [SignalShift(nodeId: ridge, fromDbm: -112, toDbm: -100, at: now.subtract(const Duration(hours: 1)))],
  telemetry: withTelemetry
      ? {
          ridge: NodeTelemetry(
            nodeId: ridge,
            heardAt: now.subtract(const Duration(minutes: 3)),
            batteryPct: 87,
            batteryMv: 3987,
            uptime: const Duration(hours: 5),
          ),
          quiet: NodeTelemetry(nodeId: quiet, heardAt: now, uptime: const Duration(minutes: 9)),
        }
      : const {},
);

Future<void> _pump(
  WidgetTester tester,
  int node, {
  MeshState? state,
  int? minor = 12,
  double text = 1,
  Widget? home,
}) async {
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
        meshProvider.overrideWith(() => SeededMesh(state ?? seed())),
        locationShareProvider.overrideWith(_NoShare.new),
        nodeInfoProvider.overrideWithValue(minor == null ? null : pb.NodeInfo(nodeId: me, protocolMinor: minor)),
      ],
      child: MaterialApp(
        theme: buildGhostWaveTheme(),
        home: home ?? NodeDetailsScreen(nodeId: node),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a direct neighbor with telemetry: everything, readable', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, ridge);
    expect(find.text('Ridge'), findsWidgets);
    expect(find.text('9f219dbb'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Node ID 9 f 2 1 9 d b b')), findsOneWidget);
    expect(find.textContaining('Yes: your node heard its beacon 3 min ago'), findsOneWidget);
    expect(find.textContaining('1.0 km N of your node (bearing 0°)'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Distance: 1\.0 km N of your node, bearing 0 degrees')), findsOneWidget);
    expect(find.textContaining('-97 dBm, good · beacon, 3 min ago'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Signal history graph: 3 readings over 1 h 57 min, from -112 to -97 dBm')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('87 % · 3.99 V'), 200);
    expect(find.text('87 % · 3.99 V'), findsOneWidget);
    expect(find.textContaining('About 5 h 3 min'), findsOneWidget);
    expect(find.text('In its beacon 3 min ago'), findsOneWidget);
    // each fact reads as one node: label and value together
    expect(find.bySemanticsLabel(RegExp(r'Battery\n87 % · 3\.99 V')), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('the readings are listed as text too', (tester) async {
    await _pump(tester, ridge);
    await tester.scrollUntilVisible(find.text('All 3 readings'), 200);
    await tester.tap(find.text('All 3 readings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('-112 dBm, fair'), 200);
    expect(find.text('-112 dBm, fair'), findsOneWidget);
    expect(find.text('-100 dBm, good'), findsOneWidget);
    expect(find.textContaining('signal change ·'), findsOneWidget);
  });

  testWidgets('uptime only: battery is "not reported", never guessed', (tester) async {
    await _pump(tester, quiet);
    await tester.scrollUntilVisible(find.text('Not reported (the board cannot read it)'), 200);
    expect(find.textContaining('About 9 min'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('It has not reported a position'), findsOneWidget);
    expect(find.textContaining('No beacon heard while connected'), findsOneWidget);
    expect(find.textContaining('No signal readings yet'), findsOneWidget);
  });

  testWidgets('an older connected node: says why there is no telemetry', (tester) async {
    await _pump(tester, ridge, state: seed(withTelemetry: false), minor: 10);
    await tester.scrollUntilVisible(find.textContaining('firmware does not pass on telemetry'), 200);
    expect(find.text('Ask your node again'), findsNothing);
    expect(find.textContaining('Battery'), findsOneWidget); // the label only
  });

  testWidgets('not connected, no telemetry heard: asks to connect', (tester) async {
    await _pump(tester, ridge, state: seed(withTelemetry: false), minor: null);
    await tester.scrollUntilVisible(find.textContaining('Connect to your node'), 200);
  });

  testWidgets('the journal page opens it', (tester) async {
    final heard = seed().copyWith(
      journal: const NodeJournal().record(ridge, now.subtract(const Duration(hours: 4)), HeardVia.beacon, rssiDbm: -90),
    );
    await _pump(
      tester,
      ridge,
      state: heard,
      home: const JournalNodeScreen(nodeId: ridge),
    );
    await tester.tap(find.byTooltip('Node details'));
    await tester.pumpAndSettle();
    expect(find.byType(NodeDetailsScreen), findsOneWidget);
    expect(find.textContaining('First heard'), findsOneWidget);
    expect(find.text('Strongest heard'), findsOneWidget);
  });

  testWidgets('200 % text: no overflow', (tester) async {
    await _pump(tester, ridge, text: 2);
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}
