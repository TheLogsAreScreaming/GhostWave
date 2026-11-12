// Node cards: chips show only what was measured (in range, signal, distance and
// direction, trust, waiting messages) and wrap at large text.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:ghostwave_app/src/ui/contacts_screen.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int ridge = 0x1A2B3C4D;

Future<void> _pump(WidgetTester tester, Widget child, {double text = 1, Size size = const Size(412, 892)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({'units': 'imperial'});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: buildGhostWaveTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: size.width - 120, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final own = const LatLon(45.0, -110.0);
  final north = const LatLon(45.00725, -110.0); // about 0.5 mi north

  testWidgets('a contact heard just now: in range, signal, distance and direction, verified', (tester) async {
    final now = DateTime.now();
    final mesh = MeshState(
      ownPos: own,
      neighbors: {ridge: Neighbor(nodeId: ridge, lastSeen: now, pos: north, rssiDbm: -112)},
    );
    await _pump(
      tester,
      NodeMetrics(
        nodeId: ridge,
        mesh: mesh,
        contact: Contact(nodeId: ridge, pinned: true, lastSeen: now),
      ),
    );
    expect(find.text('in range · just now'), findsOneWidget);
    expect(find.text('-112 dBm, fair'), findsOneWidget);
    expect(find.text('0.5 mi N'), findsOneWidget);
    expect(find.text('verified by QR'), findsOneWidget);
  });

  testWidgets('nothing invented: no position, no signal, no chips for them', (tester) async {
    final mesh = MeshState(ownPos: own);
    await _pump(
      tester,
      NodeMetrics(
        nodeId: ridge,
        mesh: mesh,
        contact: Contact(nodeId: ridge, lastSeen: DateTime.now().subtract(const Duration(hours: 3))),
      ),
    );
    expect(find.text('3 h ago'), findsOneWidget, reason: 'heard, but not in range now');
    expect(find.textContaining('dBm'), findsNothing);
    expect(find.textContaining(' mi '), findsNothing);
    expect(find.text('key learned over the air'), findsOneWidget);
  });

  testWidgets('a heard node waiting for its key, with messages queued; key change is a warning', (tester) async {
    final mesh = MeshState(
      neighbors: {ridge: Neighbor(nodeId: ridge, lastSeen: DateTime.now())},
    );
    await _pump(tester, NodeMetrics(nodeId: ridge, mesh: mesh, waiting: 2, keyKnown: false));
    expect(find.text('waiting for key'), findsOneWidget);
    expect(find.text('2 waiting'), findsOneWidget);
    await _pump(
      tester,
      NodeMetrics(
        nodeId: ridge,
        mesh: mesh,
        contact: const Contact(nodeId: ridge, keyChanged: true),
      ),
    );
    expect(find.text('key changed'), findsOneWidget);
  });

  testWidgets('wraps at 200% text on a small phone', (tester) async {
    final now = DateTime.now();
    final mesh = MeshState(
      ownPos: own,
      neighbors: {ridge: Neighbor(nodeId: ridge, lastSeen: now, pos: north, rssiDbm: -90)},
    );
    await _pump(
      tester,
      NodeMetrics(
        nodeId: ridge,
        mesh: mesh,
        contact: Contact(nodeId: ridge, lastSeen: now),
        waiting: 1,
      ),
      text: 2,
      size: const Size(360, 780),
    );
    expect(tester.takeException(), isNull);
  });
}
