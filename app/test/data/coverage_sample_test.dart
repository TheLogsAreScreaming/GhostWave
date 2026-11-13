import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/coverage_sample.dart';

void main() {
  CoverageSample sample(CoverageOutcome outcome, int? rssi) => CoverageSample(
    sessionId: 'walk-1',
    clientMessageId: 42,
    destinationNodeId: 123,
    latitude: 41.3,
    longitude: -73.1,
    recordedAt: DateTime.utc(2026, 11, 12),
    outcome: outcome,
    rssiDbm: rssi,
  );

  test('does not treat unmeasured delivery as strong signal', () {
    expect(sample(CoverageOutcome.delivered, null).mapClass, 'delivered-unmeasured');
    expect(sample(CoverageOutcome.failed, null).mapClass, 'failed');
    expect(sample(CoverageOutcome.pending, null).mapClass, 'pending');
  });

  test('signal classes use measured RSSI', () {
    expect(sample(CoverageOutcome.delivered, -85).mapClass, 'strong');
    expect(sample(CoverageOutcome.delivered, -100).mapClass, 'fair');
    expect(sample(CoverageOutcome.delivered, -120).mapClass, 'weak');
  });

  test('JSON roundtrip retains timestamp and missing telemetry', () {
    final original = sample(CoverageOutcome.failed, null);
    final decoded = CoverageSample.fromJson(original.toJson());
    expect(decoded.recordedAt, original.recordedAt);
    expect(decoded.rssiDbm, isNull);
    expect(decoded.destinationNodeId, 123);
  });

  test('CSV export includes outcome without fabricated RSSI', () {
    final csv = coverageCsv([sample(CoverageOutcome.failed, null)]);
    expect(csv, contains('outcome,rssi_dbm'));
    expect(csv, contains('failed,,,'));
  });
}
