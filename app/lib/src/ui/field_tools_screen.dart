import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../app/providers.dart';
import '../gen/ghostwave.pb.dart' as pb;

/// Captures observed radio counters and neighbor distances for a field report.
class FieldToolsScreen extends ConsumerStatefulWidget {
  /// Creates the field notebook.
  const FieldToolsScreen({super.key});

  @override
  ConsumerState<FieldToolsScreen> createState() => _FieldToolsScreenState();
}

class _FieldToolsScreenState extends ConsumerState<FieldToolsScreen> {
  final _samples = <Map<String, Object?>>[];
  final _notes = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _removeSample(Map<String, Object?> sample) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remove this sample?'),
        content: const Text('It will be excluded from future exports of this report.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Remove')),
        ],
      ),
    );
    if (!mounted || remove != true) return;
    setState(() => _samples.remove(sample));
  }

  Future<void> _capture() async {
    final sampleNote = _notes.text.trim();
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
      setState(
        () => _samples.add({
          'at': DateTime.now().toUtc().toIso8601String(),
          'node': mesh.nodeId,
          if (sampleNote.isNotEmpty) 'note': sampleNote,
          'firmware': info?.firmware,
          'uptimeSeconds': status.uptimeS,
          'tx': status.tx.toString(),
          'rx': status.rx.toString(),
          'delivered': status.delivered.toString(),
          'rxBad': status.rxBad.toString(),
          'rxAuthFail': status.rxAuthFail.toString(),
          'airtimeMs': status.airMs.toString(),
          'neighbors': <Map<String, Object?>>[
            for (final n in mesh.neighbors.values)
              {
                'node': n.nodeId,
                'lastSeen': n.lastSeen.toUtc().toIso8601String(),
                'distanceMetres': mesh.ownPos != null && n.pos != null ? mesh.ownPos!.distanceTo(n.pos!) : null,
              },
          ],
        }),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not record sample: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyCounters() async {
    const columns = ['at', 'node', 'tx', 'rx', 'delivered'];
    final rows = [columns.join(',')];
    for (final sample in _samples) {
      rows.add(columns.map((key) => sample[key] ?? '').join(','));
    }
    await Clipboard.setData(ClipboardData(text: rows.join('\r\n')));
    if (!mounted) return;
    const notice = SnackBar(content: Text('Counters copied as CSV'));
    ScaffoldMessenger.of(context).showSnackBar(notice);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Field tools')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Record samples before and after exchanging messages at each test location. Distances use reported positions and may be stale. Counters are cumulative and reset when the radio restarts. This notebook does not transmit test packets.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Test notes',
              hintText: 'Boards, terrain, distance, and observed results',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || _samples.length >= 200 ? null : _capture,
            child: Text(_busy ? 'Recording…' : 'Record sample (${_samples.length}/200)'),
          ),
          if (_error != null) Text(_error!),
          OutlinedButton(
            onPressed: _samples.isEmpty
                ? null
                : () async {
                    final report = const JsonEncoder.withIndent('  ')
                        .convert({'version': 1, 'notes': _notes.text, 'samples': _samples});
                    try {
                      await Clipboard.setData(ClipboardData(text: report));
                    } on PlatformException catch (error) {
                      if (mounted) setState(() => _error = 'Could not copy report: ${error.message ?? error.code}');
                      return;
                    }
                    if (mounted && _error != null) setState(() => _error = null);
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Report copied. Paste it into a file or message.')));
                    }
                  },
            child: const Text('Copy test report'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Copy counters as CSV'),
            onPressed: _samples.isEmpty ? null : _copyCounters,
          ),
          const Text(
            'Reports include neighbor identifiers and approximate distances. Notes and samples stay here only until this screen closes. Signal history is unavailable from the current node protocol.',
          ),
          for (final sample in _samples.reversed)
            ExpansionTile(
              key: ObjectKey(sample),
              title: Text('${sample['at']}'),
              subtitle: Text('TX ${sample['tx']} · RX ${sample['rx']} · delivered ${sample['delivered']}'),
              children: [
                for (final neighbor in sample['neighbors']! as List<Map<String, Object?>>)
                  ListTile(
                    title: Text((neighbor['node']! as int).toRadixString(16).padLeft(8, '0')),
                    subtitle: Text('Last heard ${neighbor['lastSeen']}'),
                    trailing: Text(switch (neighbor['distanceMetres']) {
                      final num distance => '${distance.round()} m',
                      _ => 'No position',
                    }),
                  ),
                if ((sample['neighbors']! as List<Map<String, Object?>>).isEmpty)
                  const ListTile(title: Text('No neighbors heard')),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Remove sample'),
                  onTap: () => _removeSample(sample),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
