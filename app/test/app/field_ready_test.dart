// dev.6: offline regions (and the OSM policy guard), units, bearings,
// walkthrough, SOS clock and map focus, contrast and large text.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/main.dart';
import 'package:ghostwave_app/src/app/preferences.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:ghostwave_app/src/map/offline_maps.dart';
import 'package:ghostwave_app/src/ui/format.dart';
import 'package:ghostwave_app/src/ui/sos_screen.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:ghostwave_app/src/ui/walkthrough_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String custom = 'https://tiles.example.org/{z}/{x}/{y}.png';
const RegionBounds small = RegionBounds(
  south: 46.86,
  west: -114.0,
  north: 46.88,
  east: -113.98,
  minZoom: 12,
  maxZoom: 13,
);

void main() {
  group('tile source rules', () {
    test('valid URLs', () {
      expect(validTileUrl(custom), isTrue);
      expect(validTileUrl('https://x.org/{z}/{x}.png'), isFalse);
      expect(validTileUrl('ftp://x.org/{z}/{x}/{y}.png'), isFalse);
      expect(validTileUrl('https://{s}.x.org/{z}/{x}/{y}.png'), isFalse);
    });

    test('OSM servers are refused for bulk download', () {
      for (final u in [
        kOsmTileUrl,
        'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png',
        'https://tile.osm.org/{z}/{x}/{y}.png',
      ]) {
        expect(isForbiddenBulkSource(u), isTrue, reason: u);
        expect(refuseDownload(small, u), contains('do not allow'));
      }
      expect(isForbiddenBulkSource('https://notopenstreetmap.org/{z}/{x}/{y}.png'), isFalse);
      expect(refuseDownload(small, custom), isNull);
    });

    test('zoom, tile and storage caps', () {
      const deep = RegionBounds(south: 46, west: -114, north: 46.1, east: -113.9, minZoom: 16, maxZoom: 17);
      expect(refuseDownload(deep, custom), contains('Zoom'));
      const wide = RegionBounds(south: 40, west: -120, north: 50, east: -100, minZoom: 10, maxZoom: 16);
      expect(refuseDownload(wide, custom), contains('limit'));
      expect(refuseDownload(small, custom, usedBytes: kMaxOfflineBytes), contains('MB'));
    });
  });

  test('tile maths: known tile, count matches the list', () {
    const b = RegionBounds(south: 51.5, west: -0.13, north: 51.5, east: -0.13, minZoom: 10, maxZoom: 10);
    final t = b.tiles.single;
    expect([t.x, t.y], [511, 340]);
    expect(small.tiles.length, small.tileCount);
    expect(t.url(custom).toString(), 'https://tiles.example.org/10/511/340.png');
  });

  group('download', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('gwapp-maps.'));
    tearDown(() async => dir.delete(recursive: true));

    test('saves every tile, survives a missing one, and is found again', () async {
      final store = OfflineStore(dir);
      var n = 0;
      final r = await downloadRegion(
        store: store,
        id: 'r1',
        name: 'Home',
        bounds: small,
        urlTemplate: custom,
        fetch: (u) async => n++ == 0 ? null : Uint8List.fromList([1, 2, 3]),
      );
      expect(r.tiles, small.tileCount - 1);
      expect(r.bytes, (small.tileCount - 1) * 3);
      await store.save([r]);
      final back = await OfflineStore(dir).load();
      expect(back.single.name, 'Home');
      expect(store.tileFile('r1', small.tiles.last).existsSync(), isTrue);
    });

    test('never fetches from OSM, and a refusal removes the partial region', () async {
      final store = OfflineStore(dir);
      var fetched = 0;
      await expectLater(
        downloadRegion(
          store: store,
          id: 'x',
          name: 'n',
          bounds: small,
          urlTemplate: kOsmTileUrl,
          fetch: (u) async {
            fetched++;
            return Uint8List(1);
          },
        ),
        throwsStateError,
      );
      expect(fetched, 0);
      var calls = 0;
      await expectLater(
        downloadRegion(
          store: store,
          id: 'y',
          name: 'n',
          bounds: small,
          urlTemplate: custom,
          fetch: (u) async {
            if (++calls > 2) throw const TileServerRefused(429);
            return Uint8List(1);
          },
        ),
        throwsA(isA<TileServerRefused>()),
      );
      expect(Directory('${store.root.path}/y').existsSync(), isFalse);
    });

    test('controller: download, cancel, delete', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = OfflineStore(dir);
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          offlineStoreProvider.overrideWithValue(store),
          tileFetcherProvider.overrideWithValue((u) async => Uint8List.fromList([9])),
        ],
      );
      addTearDown(c.dispose);
      c.listen(offlineMapsProvider, (_, _) {});
      final ctl = c.read(offlineMapsProvider.notifier);
      await ctl.download('blocked', small);
      expect(c.read(offlineMapsProvider).error, contains('do not allow'));
      expect(c.read(tileSourceProvider.notifier).set(custom, 'Tiles © Example'), isTrue);
      await ctl.download('Home', small);
      final st = c.read(offlineMapsProvider);
      expect(st.job, isNull);
      expect(st.regions.single.tiles, small.tileCount);
      await ctl.delete(st.regions.single);
      expect(c.read(offlineMapsProvider).regions, isEmpty);
      expect(Directory('${store.root.path}/${st.regions.single.id}').existsSync(), isFalse);
    });
  });

  test('units and compass', () {
    expect(formatDistance(850, Units.metric), '850 m');
    expect(formatDistance(1420, Units.metric), '1.4 km');
    expect(formatDistance(100, Units.imperial), '330 ft');
    expect(formatDistance(3218.7, Units.imperial), '2.0 mi');
    expect(formatAccuracy(12, Units.imperial), '39 ft');
    const a = LatLon(46, -114);
    expect(a.bearingTo(const LatLon(47, -114)), closeTo(0, 0.01));
    expect(a.bearingTo(const LatLon(46, -113)), closeTo(89.6, 0.5));
    expect(compassPoint(44), 'NE');
    expect(compassPoint(359), 'N');
    expect(clockDuration(const Duration(minutes: 3, seconds: 7)), '3:07');
    expect(clockDuration(const Duration(hours: 1, seconds: 5)), '1:00:05');
  });

  group('theme contrast (WCAG)', () {
    double lum(Color c) {
      double g(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * g(c.r) + 0.7152 * g(c.g) + 0.0722 * g(c.b);
    }

    double ratio(Color a, Color b) {
      final x = lum(a), y = lum(b);
      return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
    }

    final s = buildGhostWaveTheme().colorScheme;
    final pairs = <String, (Color, Color)>{
      'body': (s.onSurface, s.surface),
      'muted': (s.onSurfaceVariant, s.surfaceContainerHighest),
      'button': (s.onPrimary, s.primary),
      'error text': (s.error, s.surfaceContainerHighest),
      'sos': (GwColors.onAlert, GwColors.alert),
      'alert container': (s.onErrorContainer, s.errorContainer),
      'my bubble': (s.onSurface, s.primaryContainer),
      'sender': (s.tertiary, s.surfaceContainerHighest),
    };
    for (final e in pairs.entries) {
      test(e.key, () => expect(ratio(e.value.$1, e.value.$2), greaterThanOrEqualTo(4.5)));
    }
  });

  Widget scaled(Widget child) => MaterialApp(
    theme: buildGhostWaveTheme(),
    home: MediaQuery(
      data: const MediaQueryData(size: Size(360, 740), textScaler: TextScaler.linear(2)),
      child: child,
    ),
  );

  testWidgets('walkthrough: pages, finish, large text, tap targets', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var done = 0;
    await tester.pumpWidget(scaled(WalkthroughScreen(onDone: () => done++)));
    await tester.pump();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    for (final title in ['Connect to your node', 'Your QR card', 'How SOS works']) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    await tester.tap(find.text('Get started'));
    expect(done, 1);
    handle.dispose();
  });

  testWidgets('first launch shows the walkthrough, then Connect', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(overrides: [sharedPrefsProvider.overrideWithValue(prefs)], child: const GhostWaveApp()),
    );
    await tester.pump();
    expect(find.text('Welcome to GhostWave'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(find.text('Connect to a node'), findsOneWidget);
    expect(prefs.getBool('walkthrough_done'), isTrue);
  });

  testWidgets('SOS clock: elapsed time and next repeat', (tester) async {
    final start = DateTime(2026, 11, 8, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SosClock(startedAt: start, now: () => start.add(const Duration(minutes: 7, seconds: 30))),
        ),
      ),
    );
    expect(find.textContaining('Active for 7:30'), findsOneWidget);
    expect(find.textContaining('Next repeat in about 2:30'), findsOneWidget);
  });

  testWidgets('SOS button survives large text', (tester) async {
    await tester.pumpWidget(
      scaled(
        Scaffold(
          body: Center(child: HoldToConfirmButton(onConfirmed: () {})),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('map focus requests are distinct', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final seen = <int>[];
    c.listen(mapFocusProvider, (_, f) => seen.add(f!.serial));
    c.read(mapFocusProvider.notifier).show(const LatLon(1, 2), 'a');
    c.read(mapFocusProvider.notifier).show(const LatLon(1, 2), 'a');
    expect(seen, hasLength(2));
  });
}
