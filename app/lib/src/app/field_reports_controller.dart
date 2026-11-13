/// Keeps saved field reports in memory and on disk.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/field_reports.dart';

/// The on-disk store; `main` installs the real one. Null keeps reports in
/// memory only (tests).
final fieldReportStoreProvider = Provider<FieldReportStore?>((ref) => null);

/// Saved reports, newest first.
class FieldReportsState {
  /// Creates the state.
  const FieldReportsState({
    this.reports = const [],
    this.loaded = false,
    this.problem = ReportsProblem.none,
    this.saveError,
  });

  /// Reports, newest first.
  final List<FieldReport> reports;

  /// Whether the saved file has been read.
  final bool loaded;

  /// Whether the saved file had to be set aside.
  final ReportsProblem problem;

  /// The last save failure, if the latest change is not on disk.
  final String? saveError;

  /// The report with [id], if any.
  FieldReport? byId(String id) {
    for (final r in reports) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Whether another report fits.
  bool get full => reports.length >= kMaxReports;
}

/// Loads, changes and saves reports.
class FieldReportsController extends Notifier<FieldReportsState> {
  FieldReportStore? _store;

  @override
  FieldReportsState build() {
    _store = ref.watch(fieldReportStoreProvider);
    final store = _store;
    if (store == null) return const FieldReportsState(loaded: true);
    store
        .load()
        .then((r) {
          if (!ref.mounted) return;
          final (reports, problem) = r;
          state = FieldReportsState(reports: reports, loaded: true, problem: problem);
        })
        .catchError((Object e) {
          if (ref.mounted) state = FieldReportsState(loaded: true, saveError: 'Could not read saved reports: $e');
        });
    return const FieldReportsState();
  }

  void _set(List<FieldReport> reports) {
    state = FieldReportsState(reports: reports, loaded: true, problem: state.problem);
    final store = _store;
    if (store == null) return;
    store.save(reports).catchError((Object e) {
      debugPrint('field reports not saved: $e');
      if (ref.mounted) {
        state = FieldReportsState(
          reports: state.reports,
          loaded: true,
          problem: state.problem,
          saveError: 'Could not save reports: $e',
        );
      }
    });
  }

  /// Starts a report and returns it, or null if [kMaxReports] are kept already.
  FieldReport? start({String? name, DateTime? now}) {
    if (state.full) return null;
    final r = FieldReport.start(now ?? DateTime.now(), name: name);
    _set([r, ...state.reports]);
    return r;
  }

  /// Replaces the report with the same ID.
  void update(FieldReport report) {
    if (state.byId(report.id) == null) return;
    _set([for (final r in state.reports) r.id == report.id ? report : r]);
  }

  /// Adds [sample] to report [id]. False if it is full or gone.
  bool addSample(String id, Map<String, Object?> sample) {
    final r = state.byId(id);
    if (r == null || r.full) return false;
    update(r.withSample(sample));
    return true;
  }

  /// Saves [notes] on report [id], if it still exists and they changed.
  void setNotes(String id, String notes) {
    final r = state.byId(id);
    if (r != null && r.notes != notes) update(r.copyWith(notes: notes));
  }

  /// Deletes every saved report.
  void deleteAll() => _set(const []);

  /// Deletes report [id].
  void delete(String id) => _set([
    for (final r in state.reports)
      if (r.id != id) r,
  ]);

  /// Adds an imported report as a new copy, so it never overwrites one here.
  FieldReport? import(FieldReport incoming) {
    if (state.full) return null;
    final fresh = FieldReport.start(incoming.createdAt, name: incoming.name);
    final copy = FieldReport(
      id: fresh.id,
      name: incoming.name,
      createdAt: incoming.createdAt,
      notes: incoming.notes,
      samples: incoming.samples,
    );
    _set([copy, ...state.reports]);
    return copy;
  }
}

/// Saved field reports.
final fieldReportsProvider = NotifierProvider<FieldReportsController, FieldReportsState>(FieldReportsController.new);
