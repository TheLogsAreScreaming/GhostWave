/// Saved field test reports: named sessions of radio samples that survive
/// closing the screen and restarting the app, plus the export file format.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Most samples one report keeps.
const kMaxSamples = 200;

/// Most reports kept on the phone.
const kMaxReports = 50;

/// Longest report name.
const kMaxNameLength = 60;

/// Longest notes text.
const kMaxNotesLength = 4000;

/// Export format name, so other tools can recognise the file.
const kReportFormat = 'ghostwave-field-report';

/// Export format version. A newer file is refused rather than misread.
const kReportFormatVersion = 1;

/// One named field test.
class FieldReport {
  /// Creates a report.
  const FieldReport({
    required this.id,
    required this.name,
    required this.createdAt,
    this.notes = '',
    this.samples = const [],
  });

  /// A new, empty report named after the time it was started.
  factory FieldReport.start(DateTime now, {String? name}) {
    final rnd = Random.secure();
    final id = List.generate(8, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final local = now.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final fallback = 'Test ${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
    final trimmed = name?.trim() ?? '';
    return FieldReport(
      id: id,
      name: trimmed.isEmpty ? fallback : _clip(trimmed, kMaxNameLength),
      createdAt: now.toUtc(),
    );
  }

  /// From [toJson]. Throws [FormatException] on anything malformed.
  factory FieldReport.fromJson(Map<String, Object?> j) {
    final id = j['id'];
    final name = j['name'];
    final created = j['createdAt'];
    if (id is! String || !RegExp(r'^[0-9a-f]{16}$').hasMatch(id)) throw const FormatException('bad report id');
    if (name is! String || name.trim().isEmpty) throw const FormatException('bad report name');
    if (created is! String) throw const FormatException('bad report time');
    final notes = j['notes'];
    final samples = j['samples'];
    if (notes != null && notes is! String) throw const FormatException('bad notes');
    if (samples != null && samples is! List) throw const FormatException('bad samples');
    final list = <Map<String, Object?>>[
      for (final s in (samples as List<Object?>?) ?? const <Object?>[])
        if (s is Map) s.cast<String, Object?>() else throw const FormatException('bad sample'),
    ];
    if (list.length > kMaxSamples) throw const FormatException('too many samples');
    return FieldReport(
      id: id,
      name: _clip(name.trim(), kMaxNameLength),
      createdAt: DateTime.parse(created).toUtc(),
      notes: _clip((notes as String?) ?? '', kMaxNotesLength),
      samples: List.unmodifiable(list),
    );
  }

  /// Stable ID, 16 hex digits.
  final String id;

  /// What the user called it.
  final String name;

  /// When it was started, UTC.
  final DateTime createdAt;

  /// Free text: boards, terrain, distance, results.
  final String notes;

  /// Recorded samples, oldest first. Each is plain JSON.
  final List<Map<String, Object?>> samples;

  /// Whether another sample fits.
  bool get full => samples.length >= kMaxSamples;

  /// When the last sample was taken, or when it was started.
  DateTime get updatedAt {
    if (samples.isEmpty) return createdAt;
    return DateTime.tryParse('${samples.last['at']}')?.toUtc() ?? createdAt;
  }

  /// A copy with changes.
  FieldReport copyWith({String? name, String? notes, List<Map<String, Object?>>? samples}) => FieldReport(
    id: id,
    name: name == null ? this.name : _clip(name.trim(), kMaxNameLength),
    createdAt: createdAt,
    notes: notes == null ? this.notes : _clip(notes, kMaxNotesLength),
    samples: samples == null ? this.samples : List.unmodifiable(samples),
  );

  /// With [sample] added, dropping it if the report is full.
  FieldReport withSample(Map<String, Object?> sample) => full ? this : copyWith(samples: [...samples, sample]);

  /// With the sample at [index] removed.
  FieldReport withoutSample(int index) => copyWith(samples: [...samples]..removeAt(index));

  /// Storage and export shape.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'notes': notes,
    'samples': samples,
  };

  /// The export file: an envelope that says what it is and which app wrote it.
  String exportJson({required String appVersion, required DateTime now}) => const JsonEncoder.withIndent('  ').convert({
    'format': kReportFormat,
    'formatVersion': kReportFormatVersion,
    'appVersion': appVersion,
    'exportedAtUtc': now.toUtc().toIso8601String(),
    'report': toJson(),
  });

  /// Reads an export file back. Throws [FormatException] if it is not one, or
  /// if a newer app wrote it.
  static FieldReport parseExport(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      throw const FormatException('not a JSON file');
    }
    if (j is! Map || j['format'] != kReportFormat) throw const FormatException('not a GhostWave field report');
    final v = j['formatVersion'];
    if (v is! int || v < 1) throw const FormatException('bad format version');
    if (v > kReportFormatVersion) throw const FormatException('made by a newer GhostWave app');
    final r = j['report'];
    if (r is! Map) throw const FormatException('missing report');
    return FieldReport.fromJson(r.cast<String, Object?>());
  }

  /// A file name for the export, safe on every platform.
  String get fileName {
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return 'ghostwave-${slug.isEmpty ? 'report' : slug}.json';
  }

  /// Counters as CSV, one row per sample. Text cells are quoted, and cells that
  /// a spreadsheet would run as a formula are escaped.
  String countersCsv() {
    const columns = ['at', 'node', 'note', 'tx', 'rx', 'delivered', 'rxBad', 'airtimeMs', 'lastRssiDbm', 'neighbors'];
    final rows = [columns.join(',')];
    for (final s in samples) {
      rows.add(
        columns.map((c) => c == 'neighbors' ? '${(s['neighbors'] as List?)?.length ?? 0}' : _csvCell(s[c])).join(','),
      );
    }
    return rows.join('\r\n');
  }
}

String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);

String _csvCell(Object? v) {
  if (v == null) return '';
  var s = '$v';
  if (s.isNotEmpty && '=+-@\t\r'.contains(s[0]) && num.tryParse(s) == null) s = "'$s";
  if (s.contains(RegExp('[",\r\n]')) || s != s.trim()) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

/// Why saved reports did not load.
enum ReportsProblem {
  /// They loaded, or there were none.
  none,

  /// The file was damaged. It was set aside as `field_reports.json.bad`.
  unreadable,
}

/// Saved reports on disk: one JSON file, replaced whole by write-then-rename
/// so a crash mid-write leaves the old file intact.
class FieldReportStore {
  /// Uses [dir] (the app's private support folder).
  FieldReportStore(this.dir);

  /// Where the file lives.
  final Directory dir;

  File get _file => File('${dir.path}/field_reports.json');

  /// Reports, newest first, and whether the file had to be set aside.
  Future<(List<FieldReport>, ReportsProblem)> load() async {
    final f = _file;
    if (!f.existsSync()) return (const <FieldReport>[], ReportsProblem.none);
    try {
      final j = jsonDecode(await f.readAsString());
      if (j is! Map || j['version'] != 1 || j['reports'] is! List) throw const FormatException('bad file');
      final reports = [
        for (final r in j['reports'] as List<Object?>)
          if (r is Map) FieldReport.fromJson(r.cast<String, Object?>()) else throw const FormatException('bad report'),
      ];
      return (reports, ReportsProblem.none);
    } on FormatException {
      await _setAside(f);
    } on TypeError {
      await _setAside(f);
    }
    return (const <FieldReport>[], ReportsProblem.unreadable);
  }

  Future<void> _setAside(File f) async {
    try {
      await f.rename('${f.path}.bad');
    } on FileSystemException {
      // leave it; the next save replaces it
    }
  }

  Future<void> _queue = Future<void>.value();

  /// Saves [reports], after any save already under way. A failed save does not
  /// stop later ones.
  Future<void> save(List<FieldReport> reports) {
    final next = _queue.catchError((Object _) {}).then((_) => _write(reports));
    _queue = next;
    return next;
  }

  /// Completes when every save asked for so far has finished.
  Future<void> get idle => _queue.catchError((Object _) {});

  Future<void> _write(List<FieldReport> reports) async {
    await dir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    final json = jsonEncode({
      'version': 1,
      'reports': [for (final r in reports) r.toJson()],
    });
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(_file.path);
  }
}
