// Stale nodes, ignored nodes and range rings: the settings and the math.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/node_hygiene.dart';
import 'package:ghostwave_app/src/app/preferences.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:ghostwave_app/src/map/range_rings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(p)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('isStale', () {
    final now = DateTime(2026, 11, 18, 12);
    test('stale once the time has passed, not before', () {
      expect(isStale(now.subtract(const Duration(hours: 23)), now, const Duration(hours: 24)), isFalse);
      expect(isStale(now.subtract(const Duration(hours: 24)), now, const Duration(hours: 24)), isTrue);
    });
    test('never stale when off or never heard', () {
      expect(isStale(now.subtract(const Duration(days: 30)), now, Duration.zero), isFalse);
      expect(isStale(null, now, const Duration(hours: 1)), isFalse);
    });
    test('a clock that was never set is unknown, not 56 years old', () {
      const day = Duration(hours: 24);
      expect(isStale(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true), now, day), isFalse);
      expect(isStale(DateTime.utc(2019, 12, 31), now, day), isFalse);
      expect(isStale(now.add(const Duration(days: 3)), now, day), isFalse, reason: 'from the future');
      expect(isStale(DateTime.utc(2026, 11, 10), now, day), isTrue, reason: 'a real, old time still counts');
      expect(plausibleHeard(DateTime.utc(2020), now), isTrue);
      expect(plausibleHeard(null, now), isFalse);
    });

    test('labels', () {
      expect([for (final d in staleChoices) staleChoiceLabel(d)], ['Off', '1 h', '6 h', '1 day', '3 days', '7 days']);
    });
  });

  group('settings are saved', () {
    test('stale after defaults to a day and keeps a choice', () async {
      final c = await _container();
      expect(c.read(staleAfterProvider), const Duration(hours: 24));
      c.read(staleAfterProvider.notifier).set(const Duration(days: 3));
      final p = await SharedPreferences.getInstance();
      expect(p.getInt('stale_after_minutes'), 3 * 24 * 60);
    });

    test('an unknown saved value falls back to the default', () async {
      final c = await _container({'stale_after_minutes': 17});
      expect(c.read(staleAfterProvider), defaultStaleAfter);
    });

    test('ignore and show again, kept across restarts', () async {
      final c = await _container();
      c.read(ignoredNodesProvider.notifier)
        ..ignore(0x1A2B3C4D)
        ..ignore(7);
      expect(c.read(ignoredNodesProvider), {7, 0x1A2B3C4D});
      final p = await SharedPreferences.getInstance();
      final again = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(p)]);
      addTearDown(again.dispose);
      expect(again.read(ignoredNodesProvider), {7, 0x1A2B3C4D});
      again.read(ignoredNodesProvider.notifier).unignore(7);
      expect(again.read(ignoredNodesProvider), {0x1A2B3C4D});
    });

    test('a damaged ignore list reads as empty, not a crash', () async {
      final c = await _container({'ignored_nodes': 'not json'});
      expect(c.read(ignoredNodesProvider), isEmpty);
    });

    test('range rings are off until turned on', () async {
      final c = await _container();
      expect(c.read(rangeRingsProvider), isFalse);
      c.read(rangeRingsProvider.notifier).set(true);
      expect(c.read(rangeRingsProvider), isTrue);
    });
  });

  group('range rings', () {
    test('round steps', () {
      expect(niceStep(7.3), 5);
      expect(niceStep(2.1), 2);
      expect(niceStep(1999), 1000);
      expect(niceStep(0.34), 0.2);
      expect(niceStep(0), 0);
    });

    test('four metric rings fill the view in round steps', () {
      expect(ringRadii(4500, Units.metric), [1000, 2000, 3000, 4000]);
      expect(ringRadii(30, Units.metric), [10, 20, 30, 40], reason: 'never below 10 m');
      expect(ringRadii(0, Units.metric), isEmpty);
    });

    test('imperial rings are in miles', () {
      final r = ringRadii(10 * 1609.344, Units.imperial);
      expect([for (final m in r) (m / 1609.344 * 10).round() / 10], [2, 4, 6, 8]);
      final tiny = ringRadii(50, Units.imperial);
      expect((tiny.first / 1609.344 * 10).round() / 10, 0.1, reason: 'never below 0.1 mi');
    });

    test('rings stay clear of the toolbar and keep room for the tags', () {
      // 400 x 800 map, 72 px toolbar down the right edge
      expect(ringReachPx(400, 800, right: 72), 200 - 72 - 28);
      // a tall top card limits it instead
      expect(ringReachPx(400, 800, top: 350), 400 - 350 - 28 < 40 ? 40 : 400 - 350 - 28);
      expect(ringReachPx(400, 800), 200 - 28);
      expect(ringReachPx(100, 100, right: 90), 40, reason: 'never vanishes');
    });

    test('labels have no stray decimals', () {
      expect(ringLabel(500, Units.metric), '500 m');
      expect(ringLabel(2000, Units.metric), '2 km');
      expect(ringLabel(1609.344 * 0.5, Units.imperial), '0.5 mi');
      expect(ringLabel(1609.344 * 10, Units.imperial), '10 mi');
    });

    test('a point along a bearing lands at that distance and bearing', () {
      const from = LatLon(45, -110);
      for (final b in [0.0, 45.0, 90.0, 200.0]) {
        final p = pointAt(from, b, 5000);
        expect(from.distanceTo(p), closeTo(5000, 25));
        final back = from.bearingTo(p);
        expect((back - b + 540) % 360 - 180, closeTo(0, 0.5));
      }
    });
  });
}
