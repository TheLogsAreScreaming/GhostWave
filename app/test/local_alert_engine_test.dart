import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/local_alert_engine.dart';

void main() {
  test('battery alerts on threshold crossings only and rearms after recovery', () {
    final e = LocalAlertEngine();
    expect(e.battery(null), isNull);
    expect(e.battery(-1), isNull);
    expect(e.battery(101), isNull);
    expect(e.battery(55), isNull);
    expect(e.battery(20)?.kind, LocalAlertKind.batteryLow);
    expect(e.battery(18), isNull);
    expect(e.battery(10)?.kind, LocalAlertKind.batteryCritical);
    expect(e.battery(8), isNull);
    expect(e.battery(50), isNull);
    expect(e.battery(19)?.kind, LocalAlertKind.batteryLow);
  });

  test('new node is notified once per session', () {
    final e = LocalAlertEngine();
    final now = DateTime.utc(2026, 11, 12);
    expect(e.heard(123, now)?.kind, LocalAlertKind.newNode);
    expect(e.heard(123, now.add(const Duration(seconds: 2))), isNull);
    e.resetSession();
    expect(e.heard(123, now)?.kind, LocalAlertKind.newNode);
  });

  test('quiet contacts require a prior hearing, connection, and monitoring', () {
    final e = LocalAlertEngine();
    final t = DateTime.utc(2026, 11, 12);
    expect(e.checkQuiet(t.add(const Duration(hours: 1)), {4}, connected: true), isEmpty);
    e.heard(4, t);
    expect(e.checkQuiet(t.add(const Duration(minutes: 31)), {4}, connected: false), isEmpty);
    expect(e.checkQuiet(t.add(const Duration(minutes: 29)), {4}, connected: true), isEmpty);
    expect(e.checkQuiet(t.add(const Duration(minutes: 30)), {4}, connected: true).single.kind,
        LocalAlertKind.contactQuiet);
    expect(e.checkQuiet(t.add(const Duration(minutes: 40)), {4}, connected: true), isEmpty);
    e.heard(4, t.add(const Duration(minutes: 41)));
    expect(e.checkQuiet(t.add(const Duration(minutes: 72)), {4}, connected: true), hasLength(1));
    expect(e.checkQuiet(t.add(const Duration(minutes: 73)), {}, connected: true), isEmpty);
  });

  test('reset clears stale contact silence', () {
    final e = LocalAlertEngine();
    final t = DateTime.utc(2026, 11, 12);
    e.heard(1, t);
    e.resetSession();
    expect(e.checkQuiet(t.add(const Duration(hours: 2)), {1}, connected: true), isEmpty);
  });
}
