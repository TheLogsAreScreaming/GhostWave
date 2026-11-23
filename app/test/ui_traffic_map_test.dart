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
import 'package:ghostwave_app/src/ui/traffic_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int me = 0x00000009;
const int ridge = 0xCAFE0003;
const int saddle = 0x0000B002;
const int ghost = 0x0000C003;

Future<ProviderContainer> _pumpMap(WidgetTester tester, {bool reduceMotion = false, DateTime Function()? clock}) async {
  // wide enough for the map attribution in the test font
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      if (clock != null) clockProvider.overrideWithValue(clock),
    ],
  );
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

  testWidgets("the card's age counts up while it shows a packet", (tester) async {
    var t = DateTime(2026, 11, 18, 13);
    final c = await _pumpMap(tester, clock: () => t);
    c.read(trafficProvider.notifier)
      ..setOn(true)
      ..add(TrafficPacket(kind: TrafficKind.advert, path: const [ridge, me], hops: 1, at: t));
    await tester.pump();
    expect(find.textContaining('0s ago'), findsOneWidget);
    t = t.add(const Duration(seconds: 7));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('7s ago'), findsOneWidget, reason: 'no new packet, but the age moved on');
    c.read(trafficProvider.notifier).setOn(false);
    await tester.pumpAndSettle();
  });

  testWidgets('Fit all keeps every pin clear of the route card and the toolbar', (tester) async {
    final c = await _pumpMap(tester);
    c.read(trafficProvider.notifier).setOn(true);
    await tester.pump();
    await tester.tap(find.byTooltip('Show all'));
    await tester.pump();
    final card = tester.getRect(find.byType(TrafficRouteCard));
    final toolbar = tester.getRect(find.byType(MapToolbar));
    for (final label in [RegExp('^My node'), RegExp('^Ridge'), RegExp('^0000b002')]) {
      final pin = tester.getRect(find.bySemanticsLabel(label).first);
      expect(pin.overlaps(card), isFalse, reason: '$label pin is above the card');
      expect(pin.overlaps(toolbar), isFalse, reason: '$label pin is left of the toolbar');
    }
    await tester.pumpAndSettle();
  });

  group('mapFitPadding', () {
    const map = Rect.fromLTWH(0, 0, 400, 800);

    test('with nothing over the map, the plain margin on every side', () {
      expect(mapFitPadding(map), const EdgeInsets.all(kMapFitMargin));
    });

    test('a wide card at the bottom and a tall toolbar on the right push the pins away', () {
      final p = mapFitPadding(map, overlays: const [Rect.fromLTWH(12, 600, 376, 172), Rect.fromLTWH(320, 12, 68, 400)]);
      expect(p.bottom, 800 - 600 + kMapFitMargin);
      expect(p.right, 400 - 320 + kMapFitMargin);
      expect(p.top, kMapFitMargin);
      expect(p.left, kMapFitMargin);
    });

    test('overlays too big to clear still leave a quarter of the map', () {
      final p = mapFitPadding(map, overlays: const [Rect.fromLTWH(0, 0, 400, 300), Rect.fromLTWH(0, 500, 400, 300)]);
      expect(p.top + p.bottom, closeTo(800 * 0.75, 0.001));
      expect(p.top, closeTo(p.bottom, 0.001), reason: 'shared fairly');
    });

    test('an overlay outside the map is ignored', () {
      expect(
        mapFitPadding(map, overlays: const [Rect.fromLTWH(0, 900, 400, 100)]),
        const EdgeInsets.all(kMapFitMargin),
      );
    });
  });
}
