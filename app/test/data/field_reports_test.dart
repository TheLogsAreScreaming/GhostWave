// Saved field reports: storage survives restarts and damage, exports round-trip,
// limits hold, and CSV cannot smuggle spreadsheet formulas.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/field_reports_controller.dart';
import 'package:ghostwave_app/src/data/field_reports.dart';

Map<String, Object?> _sample(int n, {String? note}) => {
  'at': DateTime.utc(2026, 11, 11, 12, n % 60).toIso8601String(),
  'node': 'b6888904',
  'note': ?note,
  'tx': n,
  'rx': n * 2,
  'delivered': n,
  'neighbors': [
    {'node': '9f219dbb', 'lastSeen': '2026-11-11T12:00:00.000Z', 'distanceMetres': 805},
  ],
};

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('gw_reports'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('reports survive a restart', () async {
    final store = FieldReportStore(dir);
    final r = FieldReport.start(DateTime.utc(2026, 11, 11), name: 'Ridge road').withSample(_sample(1));
    await store.save([r.copyWith(notes: 'RAK 1 W to T1000-E, 20 dBm')]);
    final (back, problem) = await FieldReportStore(dir).load();
    expect(problem, ReportsProblem.none);
    expect(back.single.name, 'Ridge road');
    expect(back.single.notes, 'RAK 1 W to T1000-E, 20 dBm');
    expect(back.single.samples.single['rx'], 2);
    expect(back.single.id, r.id);
  });

  test('a damaged file is set aside, not crashed on', () async {
    File('${dir.path}/field_reports.json').writeAsStringSync('{"version":1,"reports":[{"id":');
    final (back, problem) = await FieldReportStore(dir).load();
    expect(back, isEmpty);
    expect(problem, ReportsProblem.unreadable);
    expect(File('${dir.path}/field_reports.json.bad').existsSync(), isTrue);
  });

  test('a failed save does not stop later saves', () async {
    final store = FieldReportStore(dir);
    Directory('${dir.path}/field_reports.json.tmp').createSync();
    await expectLater(store.save([FieldReport.start(DateTime.utc(2026), name: 'Lost')]), throwsA(anything));
    Directory('${dir.path}/field_reports.json.tmp').deleteSync();
    await store.save([FieldReport.start(DateTime.utc(2026), name: 'Saved')]);
    final (back, _) = await store.load();
    expect(back.single.name, 'Saved');
  });

  test('a write cut short leaves the last good file in place', () async {
    final store = FieldReportStore(dir);
    await store.save([FieldReport.start(DateTime.utc(2026), name: 'Kept')]);
    File('${dir.path}/field_reports.json.tmp').writeAsStringSync('{"vers');
    final (back, _) = await store.load();
    expect(back.single.name, 'Kept');
  });

  test('export round-trips and says what made it', () {
    final r = FieldReport.start(
      DateTime.utc(2026, 11, 11),
      name: 'Half mile',
    ).copyWith(notes: 'clear line of sight').withSample(_sample(3, note: 'top of hill'));
    final text = r.exportJson(appVersion: '0.1.0', now: DateTime.utc(2026, 11, 12));
    final j = jsonDecode(text) as Map<String, Object?>;
    expect(j['format'], kReportFormat);
    expect(j['formatVersion'], kReportFormatVersion);
    expect(j['appVersion'], '0.1.0');
    final back = FieldReport.parseExport(text);
    expect(back.toJson(), r.toJson());
    expect(r.fileName, 'ghostwave-half-mile.json');
  });

  test('a file from a newer app, or not a report, is refused', () {
    final newer = jsonEncode({'format': kReportFormat, 'formatVersion': kReportFormatVersion + 1, 'report': {}});
    expect(() => FieldReport.parseExport(newer), throwsA(isA<FormatException>()));
    expect(() => FieldReport.parseExport('{"format":"something-else"}'), throwsA(isA<FormatException>()));
    expect(() => FieldReport.parseExport('not json'), throwsA(isA<FormatException>()));
  });

  test('a report stops taking samples at the limit', () {
    var r = FieldReport.start(DateTime.utc(2026));
    for (var i = 0; i < kMaxSamples + 5; i++) {
      r = r.withSample(_sample(i));
    }
    expect(r.samples, hasLength(kMaxSamples));
    expect(r.full, isTrue);
  });

  test('an unnamed report is named after when it started', () {
    final r = FieldReport.start(DateTime(2026, 11, 11, 9, 5), name: '  ');
    expect(r.name, 'Test 2026-11-11 09:05');
    expect(r.id, matches(RegExp(r'^[0-9a-f]{16}$')));
  });

  test('CSV quotes text and escapes formulas', () {
    final r = FieldReport.start(DateTime.utc(2026))
        .withSample(_sample(1, note: '=HYPERLINK("x")'))
        .withSample(_sample(2, note: 'ridge, north side'));
    final lines = r.countersCsv().split('\r\n');
    expect(lines.first, 'at,node,note,tx,rx,delivered,rxBad,airtimeMs,neighbors');
    expect(lines[1], contains('"\'=HYPERLINK(""x"")"'));
    expect(lines[2], contains('"ridge, north side"'));
    expect(lines[2], endsWith(',1'));
  });

  test('controller starts, edits, imports and deletes, and keeps a limit', () async {
    final store = FieldReportStore(dir);
    final c = ProviderContainer(overrides: [fieldReportStoreProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    final ctl = c.read(fieldReportsProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    final r = ctl.start(name: 'One')!;
    expect(ctl.addSample(r.id, _sample(1)), isTrue);
    ctl.setNotes(r.id, 'notes');
    final copy = ctl.import(c.read(fieldReportsProvider).byId(r.id)!)!;
    expect(copy.id, isNot(r.id));
    expect(c.read(fieldReportsProvider).reports.map((x) => x.name), ['One', 'One']);
    ctl.delete(copy.id);
    await store.idle;
    final (back, _) = await FieldReportStore(dir).load();
    expect(back.single.notes, 'notes');
    expect(back.single.samples, hasLength(1));
    for (var i = 1; i < kMaxReports; i++) {
      expect(ctl.start(), isNotNull);
    }
    expect(ctl.start(), isNull);
  });
}
