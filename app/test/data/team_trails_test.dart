import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/team_trails.dart';

void main() {
  final now = DateTime.utc(2026, 11, 12, 20);
  test('24 hour cutoff, duplicate fixes and invalid coordinates', () {
    final trails = TeamTrails();
    trails.record(
      1,
      TrailFix(latitude: 41, longitude: -73, at: now.subtract(const Duration(hours: 25))),
      now: now,
    );
    trails.record(1, TrailFix(latitude: 91, longitude: -73, at: now), now: now);
    final fix = TrailFix(
      latitude: 41,
      longitude: -73,
      at: now.subtract(const Duration(minutes: 5)),
    );
    trails.record(1, fix, now: now);
    trails.record(1, fix, now: now);
    expect(trails.snapshot(now: now)[1], hasLength(1));
    expect(trails.snapshot(now: now.add(const Duration(hours: 25))), isEmpty);
  });

  test('GPX exports sorted UTC fixes and escapes contact names', () {
    final trails = TeamTrails();
    trails.record(2, TrailFix(latitude: 41.2, longitude: -73.1, at: now), now: now);
    trails.record(
      2,
      TrailFix(latitude: 41.1, longitude: -73.2, at: now.subtract(const Duration(minutes: 1))),
      now: now,
    );
    final xml = trails.exportGpx({2: 'A & B <team>'}, now: now);
    expect(xml, contains('xmlns="http://www.topografix.com/GPX/1/1"'));
    expect(xml, contains('A &amp; B &lt;team&gt;'));
    expect(xml.indexOf('41.1'), lessThan(xml.indexOf('41.2')));
    expect(xml, contains('2026-11-12T20:00:00.000Z'));
    trails.clear(2);
    expect(trails.snapshot(now: now), isEmpty);
  });
}
