// The map's Traffic mode: the toolbar toggles it, a heard packet shows on the
// route card with its kind, signal and hops off the map, the legend lists the
// six kinds, the animation ends on its own, and reduce-motion still works.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/app/traffic.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/data/traffic.dart';
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:ghostwave_app/src/ui/map_screen.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int me = 0x00000009;
const int ridge = 0x9F219DBB;
const int saddle = 0x0000B002;
const int ghost = 0x0000C003;

Future<ProviderContainer> _pumpMap(WidgetTester tester, {bool reduceMotion = false}) async {
  // wide enough for the map attribution in the test font
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  addTearDown(c.dispose);
  final now = DateTime.now();
  c.read(meshProvider.notifier).state = c
      .read(meshProvider)
      .copyWith(
        nodeId: me,
        ownPos: const LatLon(46.87, -113.99),
        contacts: {ridge: Contact(nodeId: ridge, name: 'Ridge', pos: const LatLon(46.95, -114.10), lastSeen: now)},
        neighbors: {saddle: Neighbor(nodeId: saddle, lastSeen: now, pos: const LatLon(46.91, -114.03))},
      );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildGhostWaveTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: const MapScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return c;
}

void main() {
  setUpAll(() {
    // the map's tile cache asks path_provider for a directory
    final tmp = Directory.systemTemp.createTempSync('gw_ui_traffic').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );
  });

  TrafficPacket trace() => TrafficPacket(
    kind: TrafficKind.trace,
    path: const [ridge, ghost, saddle, me],
    pathKnown: true,
    hops: 3,
    lastHop: saddle,
    rssiDbm: -97,
    at: DateTime.now(),
  );

  testWidgets('Traffic toggles from the toolbar and shows the latest route', (tester) async {
    final c = await _pumpMap(tester);
    for (final label in ['Locate', 'Filter', 'Traffic', 'Search', 'Fit all', 'Options']) {
      expect(find.text(label), findsOneWidget, reason: 'toolbar has $label');
    }
    expect(find.text('Direct message'), findsNothing, reason: 'no legend while traffic is off');

    await tester.tap(find.byTooltip('Show live traffic'));
    await tester.pump();
    expect(c.read(trafficProvider).on, isTrue);
    expect(find.textContaining('Listening for traffic'), findsOneWidget);
    for (final k in TrafficKind.values) {
      expect(find.text(k.label), findsOneWidget, reason: 'legend lists ${k.label}');
    }

    c.read(trafficProvider.notifier).add(trace());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700)); // mid-route
    expect(find.text('Ridge → 0000c003 → 0000b002 → You'), findsOneWidget);
    expect(find.text('Trace'), findsNWidgets(2), reason: 'type pill and legend');
    expect(find.textContaining('Heard from 0000b002 · -97 dBm'), findsOneWidget);
    expect(find.textContaining('3 hops · -97 dBm · 1 not on map'), findsOneWidget);
    expect(find.text('Not on map: 0000c003'), findsOneWidget);

    // the route fades out and the animation stops by itself
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Hide live traffic'));
    await tester.pump();
    expect(c.read(trafficProvider).on, isFalse);
    expect(find.text('Direct message'), findsNothing);
  });

  testWidgets('Filter hides a packet kind', (tester) async {
    final c = await _pumpMap(tester);
    c.read(trafficProvider.notifier).setOn(true);
    await tester.pump();
    await tester.tap(find.byTooltip('Packet types to show'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Trace'));
    await tester.pumpAndSettle();
    expect(c.read(trafficProvider).kinds, isNot(contains(TrafficKind.trace)));
  });

  testWidgets('reduce motion: the route draws and fades without a travelling dot', (tester) async {
    final c = await _pumpMap(tester, reduceMotion: true);
    c.read(trafficProvider.notifier)
      ..setOn(true)
      ..add(trace());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Ridge →'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
