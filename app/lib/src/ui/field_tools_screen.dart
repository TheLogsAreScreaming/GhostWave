import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/backup.dart';
import '../app/field_reports_controller.dart';
import '../app/mesh_controller.dart';
import '../app/providers.dart';
import '../data/field_reports.dart';
import '../gen/ghostwave.pb.dart' as pb;
import 'settings_screen.dart' show packageInfoProvider;

String _when(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

/// Saved field tests: start one, reopen one, import one.
class FieldToolsScreen extends ConsumerWidget {
  /// Creates the list.
  const FieldToolsScreen({super.key});

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) =>
          const _NameDialog(title: 'New field test', action: 'Start', hint: 'For example: Ridge road, half mile'),
    );
    if (text == null || !context.mounted) return;
    final r = ref.read(fieldReportsProvider.notifier).start(name: text);
    if (r == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('$kMaxReports reports are saved already. Delete one to start another.')),
      );
      return;
    }
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => FieldReportScreen(reportId: r.id)));
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref.read(backupFilesProvider).pick();
      if (bytes == null) return;
      final report = FieldReport.parseExport(utf8.decode(bytes));
      final added = ref.read(fieldReportsProvider.notifier).import(report);
      messenger.showSnackBar(
        SnackBar(
          content: Text(added == null ? 'Too many reports saved. Delete one first.' : 'Imported "${report.name}"'),
        ),
      );
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Not imported: ${e.message}')));
    } on PlatformException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Not imported: ${e.message ?? e.code}')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(fieldReportsProvider);
    final canImport = ref.watch(backupFilesProvider).supported;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Field tests'),
        actions: [
          if (canImport)
            IconButton(
              tooltip: 'Import a report',
              icon: const Icon(Icons.file_open_outlined),
              onPressed: () => _import(context, ref),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: s.loaded && !s.full ? () => _start(context, ref) : null,
        icon: const Icon(Icons.add),
        label: const Text('New test'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            const Text(
              'Each test keeps its notes and radio samples on this phone until you delete it, '
              'including after the app closes. Nothing here transmits on the mesh.',
            ),
            if (s.problem == ReportsProblem.unreadable)
              const _Notice('Saved reports were damaged and could not be read. The file was set aside.'),
            if (s.saveError != null) _Notice(s.saveError!),
            const SizedBox(height: 8),
            if (!s.loaded)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (s.reports.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('No tests yet. Start one before you head out.', textAlign: TextAlign.center),
              )
            else
              for (final r in s.reports)
                Card(
                  child: ListTile(
                    title: Text(r.name),
                    subtitle: Text(
                      '${r.samples.length} ${r.samples.length == 1 ? 'sample' : 'samples'} · ${_when(r.updatedAt)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => FieldReportScreen(reportId: r.id)),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a test name. Owns its text controller, so it lives exactly as long
/// as the dialog, closing animation included. Pops the text, or null.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.action, this.hint, this.initial = ''});

  final String title;
  final String action;
  final String? hint;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _c,
      autofocus: true,
      maxLength: kMaxNameLength,
      decoration: InputDecoration(labelText: 'Name', hintText: widget.hint),
      onSubmitted: (_) => Navigator.pop(context, _c.text),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: Text(widget.action)),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

/// One saved test: notes, samples, export.
class FieldReportScreen extends ConsumerStatefulWidget {
  /// Opens report [reportId].
  const FieldReportScreen({required this.reportId, super.key});

  /// Which report.
  final String reportId;

  @override
  ConsumerState<FieldReportScreen> createState() => _FieldReportScreenState();
}

class _FieldReportScreenState extends ConsumerState<FieldReportScreen> {
  final _notes = TextEditingController();
  final _sampleNote = TextEditingController();
  Timer? _notesTimer;
  String? _error;
  bool _busy = false;
  late final FieldReportsController _reports;

  @override
  void initState() {
    super.initState();
    _notes.text = ref.read(fieldReportsProvider).byId(widget.reportId)?.notes ?? '';
    _reports = ref.read(fieldReportsProvider.notifier);
  }

  @override
  void dispose() {
    _notesTimer?.cancel();
    // ref is off limits here, and providers must not change while the tree is
    // being torn down, so the last notes are saved just after.
    final reports = _reports;
    final id = widget.reportId;
    final notes = _notes.text;
    scheduleMicrotask(() => reports.setNotes(id, notes));
    _notes.dispose();
    _sampleNote.dispose();
    super.dispose();
  }

  FieldReport? get _report => ref.read(fieldReportsProvider).byId(widget.reportId);

  void _saveNotes() => _reports.setNotes(widget.reportId, _notes.text);

  void _notesChanged(String _) {
    _notesTimer?.cancel();
    _notesTimer = Timer(const Duration(milliseconds: 800), _saveNotes);
  }

  Future<void> _capture() async {
    final session = ref.read(sessionProvider);
    if (session == null) {
      setState(() => _error = 'Connect to a radio before recording a sample.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reply = await session.request(pb.ToRadio(getStatus: pb.GetStatus()));
      if (!reply.hasStatus()) throw StateError('The radio did not return status counters.');
      final status = reply.status;
      if (!mounted) return;
      if (ref.read(sessionProvider) != session) {
        setState(() => _error = 'The connection changed. Please record again.');
        return;
      }
      final mesh = ref.read(meshProvider);
      final info = ref.read(nodeInfoProvider);
      final note = _sampleNote.text.trim();
      String hex(int id) => id.toRadixString(16).padLeft(8, '0');
      final ok = ref.read(fieldReportsProvider.notifier).addSample(widget.reportId, {
        'at': DateTime.now().toUtc().toIso8601String(),
        if (mesh.nodeId case final id?) 'node': hex(id),
        if (note.isNotEmpty) 'note': note,
        'firmware': info?.firmware,
        'uptimeSeconds': status.uptimeS,
        'tx': status.tx.toInt(),
        'rx': status.rx.toInt(),
        'delivered': status.delivered.toInt(),
        'rxBad': status.rxBad.toInt(),
        'rxAuthFail': status.rxAuthFail.toInt(),
        'airtimeMs': status.airMs.toInt(),
        if (mesh.ownPos case final p?) 'position': {'lat': p.lat, 'lon': p.lon},
        'neighbors': <Map<String, Object?>>[
          for (final n in mesh.neighbors.values)
            {
              'node': hex(n.nodeId),
              'lastSeen': n.lastSeen.toUtc().toIso8601String(),
              'distanceMetres': mesh.ownPos != null && n.pos != null ? mesh.ownPos!.distanceTo(n.pos!).round() : null,
            },
        ],
      });
      if (!ok) {
        setState(() => _error = 'This test is full ($kMaxSamples samples). Start another one.');
      } else {
        _sampleNote.clear();
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not record sample: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(FieldReport r) async {
    _saveNotes();
    final report = _report ?? r;
    final version = ref.read(packageInfoProvider).value?.version ?? 'unknown';
    final text = report.exportJson(appVersion: version, now: DateTime.now());
    final files = ref.read(backupFilesProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (files.supported) {
        final saved = await files.save(report.fileName, Uint8List.fromList(utf8.encode(text)));
        if (saved) messenger.showSnackBar(const SnackBar(content: Text('Report saved')));
      } else {
        await Clipboard.setData(ClipboardData(text: text));
        messenger.showSnackBar(const SnackBar(content: Text('Report copied. Paste it into a file or message.')));
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = 'Could not export: ${e.message ?? e.code}');
    }
  }

  Future<void> _copyCsv(FieldReport r) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: r.countersCsv()));
    messenger.showSnackBar(const SnackBar(content: Text('Counters copied as CSV')));
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(action)),
          ],
        ),
      ) ==
      true;

  Future<void> _rename(FieldReport r) async {
    final name = (await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(title: 'Rename test', action: 'Rename', initial: r.name),
    ))?.trim();
    if (name == null || name.isEmpty || !mounted) return;
    final now = _report;
    if (now != null) ref.read(fieldReportsProvider.notifier).update(now.copyWith(name: name));
  }

  Future<void> _delete(FieldReport r) async {
    final go = await _confirm(
      'Delete "${r.name}"?',
      'Its notes and ${r.samples.length} samples are removed from this phone. Export it first to keep a copy.',
      'Delete',
    );
    if (!go || !mounted) return;
    _notesTimer?.cancel();
    ref.read(fieldReportsProvider.notifier).delete(r.id);
    Navigator.pop(context);
  }

  Future<void> _removeSample(FieldReport r, int index) async {
    final go = await _confirm('Remove this sample?', 'It is removed from this test and future exports.', 'Remove');
    if (!go || !mounted) return;
    final now = _report;
    if (now != null && index < now.samples.length) {
      ref.read(fieldReportsProvider.notifier).update(now.withoutSample(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(fieldReportsProvider.select((s) => s.byId(widget.reportId)));
    if (r == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This test was deleted.')),
      );
    }
    final connected = ref.watch(sessionProvider) != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(r.name),
        actions: [
          IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_outlined), onPressed: () => _rename(r)),
          IconButton(tooltip: 'Delete test', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(r)),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Started ${_when(r.createdAt)}'),
            const SizedBox(height: 4),
            const Text(
              'Record a sample before and after exchanging messages at each spot. Counters are cumulative and '
              'reset when the radio restarts. Distances use reported positions and may be stale.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              maxLines: 4,
              minLines: 2,
              maxLength: kMaxNotesLength,
              onChanged: _notesChanged,
              decoration: const InputDecoration(
                labelText: 'Test notes',
                hintText: 'Boards, power, antennas, terrain, results',
              ),
            ),
            TextField(
              controller: _sampleNote,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Note for the next sample (optional)',
                hintText: 'For example: top of the ridge, 0.5 mi',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.radio_button_checked),
              onPressed: _busy || r.full ? null : _capture,
              label: Text(_busy ? 'Recording…' : 'Record sample (${r.samples.length}/$kMaxSamples)'),
            ),
            if (!connected)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Not connected. Connect to a radio to record samples; notes still save.'),
              ),
            if (_error != null) _Notice(_error!),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.ios_share),
                  label: Text(ref.watch(backupFilesProvider).supported ? 'Export report' : 'Copy report'),
                  onPressed: () => _export(r),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('Copy counters as CSV'),
                  onPressed: r.samples.isEmpty ? null : () => _copyCsv(r),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Exports include node IDs, your position at each sample and approximate distances to neighbors. '
              'Signal strength is not available from the radio yet.',
            ),
            const SizedBox(height: 8),
            for (var i = r.samples.length - 1; i >= 0; i--) _sampleTile(r, i),
          ],
        ),
      ),
    );
  }

  Widget _sampleTile(FieldReport r, int i) {
    final s = r.samples[i];
    final neighbors = ((s['neighbors'] as List?) ?? const []).cast<Map<Object?, Object?>>();
    final at = DateTime.tryParse('${s['at']}');
    final note = s['note'];
    return ExpansionTile(
      key: ValueKey('${r.id}-$i-${s['at']}'),
      title: Text('${i + 1}. ${at == null ? s['at'] : _when(at)}${note is String ? ' · $note' : ''}'),
      subtitle: Text('TX ${s['tx']} · RX ${s['rx']} · delivered ${s['delivered']} · ${neighbors.length} heard'),
      children: [
        for (final n in neighbors)
          ListTile(
            title: Text(switch (n['node']) {
              final int id => id.toRadixString(16).padLeft(8, '0'),
              final Object? id => '$id',
            }),
            subtitle: Text(
              'Last heard ${switch (DateTime.tryParse('${n['lastSeen']}')) {
                final DateTime t => _when(t),
                null => '${n['lastSeen']}',
              }}',
            ),
            trailing: Text(switch (n['distanceMetres']) {
              final num d => d >= 1000 ? '${(d / 1000).toStringAsFixed(2)} km' : '${d.round()} m',
              _ => 'No position',
            }),
          ),
        if (neighbors.isEmpty) const ListTile(title: Text('No neighbors heard')),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Remove sample'),
          onTap: () => _removeSample(r, i),
        ),
      ],
    );
  }
}
