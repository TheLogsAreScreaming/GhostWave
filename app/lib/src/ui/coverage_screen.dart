import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/backup.dart';
import '../app/coverage.dart';
import '../app/location_share.dart';
import '../app/mesh_controller.dart';
import '../app/providers.dart';
import '../data/coverage_sample.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// Words and colour for a ping result: the colour is never the only signal.
(String, Color) coverageLook(CoverageSample s) => switch (s.mapClass) {
  'strong' => ('${s.rssiDbm} dBm, strong', const Color(0xFF009E73)),
  'fair' => ('${s.rssiDbm} dBm, fair', const Color(0xFFF0E442)),
  'weak' => ('${s.rssiDbm} dBm, weak', const Color(0xFFE69F00)),
  'delivered-unmeasured' => ('delivered, no signal reading', const Color(0xFF56B4E9)),
  'failed' => ('did not get through', const Color(0xFFD55E00)),
  _ => ('waiting for a receipt', const Color(0xFF9AA5B8)),
};

/// Map a node's reach as you walk.
class CoverageScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CoverageScreen({super.key});

  @override
  ConsumerState<CoverageScreen> createState() => _CoverageScreenState();
}

class _CoverageScreenState extends ConsumerState<CoverageScreen> {
  int? _dest;
  int _every = kPingIntervals.first;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // results change with time (pending -> failed), so redraw while open
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final dest = _dest;
    if (dest == null) return;
    final ok = await ref.read(coverageProvider.notifier).start(dest, _every);
    if (!ok && mounted) {
      final s = ref.read(coverageProvider);
      final why = s.access;
      showSnack(context, s.error ?? 'A walk is already running.');
      if (why == LocationAccess.deniedForever || why == LocationAccess.serviceOff) {
        unawaited(ref.read(positionSourceProvider).openSettings(why!));
      }
    }
  }

  Future<void> _export(CoverageWalk w) async {
    final mesh = ref.read(meshProvider);
    final now = DateTime.now().toUtc();
    final csv = coverageCsv([for (final p in w.pings) sampleOf(w, p, mesh.messages, now)]);
    final files = ref.read(backupFilesProvider);
    try {
      if (files.supported) {
        final ok = await files.save('ghostwave-coverage-${w.id}.csv', Uint8List.fromList(utf8.encode(csv)));
        if (ok && mounted) showSnack(context, 'Coverage saved as CSV');
      } else {
        await Clipboard.setData(ClipboardData(text: csv));
        if (mounted) showSnack(context, 'CSV copied');
      }
    } on PlatformException catch (e) {
      if (mounted) showSnack(context, 'Not exported: ${e.message ?? e.code}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cov = ref.watch(coverageProvider);
    final mesh = ref.watch(meshProvider);
    final online = ref.watch(sessionProvider) != null;
    final running = cov.running;
    final now = DateTime.now().toUtc();
    final contacts = mesh.contacts.values.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Coverage walk')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(GwSpace.lg, GwSpace.sm, GwSpace.lg, GwSpace.xl),
        children: [
          ReadableWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SignalPanel(
                  icon: Icons.radar,
                  title: 'Map where your radio gets through',
                  detail:
                      'Leave one node in place and walk. Every so often the app sends it a short encrypted ping '
                      'from your phone\'s GPS position and records whether it arrived and how strongly the receipt '
                      'came back. Dots show on the Map.',
                ),
                const SizedBox(height: GwSpace.md),
                if (running == null) ...[
                  if (contacts.isEmpty)
                    const Text('Add the node you will ping as a contact first (Chats).')
                  else
                    DropdownButtonFormField<int>(
                      initialValue: _dest,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Node to ping (the one that stays put)'),
                      items: [
                        for (final c in contacts) DropdownMenuItem(value: c.nodeId, child: Text(mesh.nameOf(c.nodeId))),
                      ],
                      onChanged: (v) => setState(() => _dest = v),
                    ),
                  const SizedBox(height: GwSpace.sm),
                  DropdownButtonFormField<int>(
                    initialValue: _every,
                    decoration: const InputDecoration(labelText: 'Ping every'),
                    items: [
                      for (final s in kPingIntervals)
                        DropdownMenuItem(value: s, child: Text(s < 60 ? '$s seconds' : '${s ~/ 60} min')),
                    ],
                    onChanged: (v) => setState(() => _every = v ?? kPingIntervals.first),
                  ),
                  const SizedBox(height: GwSpace.md),
                  FilledButton.icon(
                    onPressed: _dest == null || !online ? null : () => unawaited(_start()),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start walk'),
                  ),
                  if (!online)
                    const Padding(
                      padding: EdgeInsets.only(top: GwSpace.sm),
                      child: Text('Connect to your radio first.'),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(top: GwSpace.sm),
                    child: Text(
                      'Uses your phone\'s location only while a walk runs. The signal shown is how strongly your '
                      'radio heard the receipt, the last hop.',
                    ),
                  ),
                ] else
                  _RunningCard(walk: running, mesh: mesh, now: now),
                if (cov.walks.where((w) => !w.running).isNotEmpty) const SectionLabel('Earlier walks'),
                for (final w in cov.walks.where((w) => !w.running))
                  Card(
                    child: ListTile(
                      title: Text('${mesh.nameOf(w.dest)} · ${clockTime(w.startedAt.toLocal())}'),
                      subtitle: Text(_summary(w, mesh, now)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'csv') unawaited(_export(w));
                          if (v == 'delete') ref.read(coverageProvider.notifier).delete(w.id);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'csv', child: Text('Export CSV')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _summary(CoverageWalk w, MeshState mesh, DateTime now) {
  final s = [for (final p in w.pings) sampleOf(w, p, mesh.messages, now)];
  final got = s.where((x) => x.outcome == CoverageOutcome.delivered).length;
  final failed = s.where((x) => x.outcome == CoverageOutcome.failed).length;
  final waiting = s.length - got - failed;
  return [
    '${s.length} pings',
    '$got got through',
    if (failed > 0) '$failed did not',
    if (waiting > 0) '$waiting waiting',
    if (w.skippedNoFix > 0) '${w.skippedNoFix} skipped (no GPS fix)',
  ].join(' · ');
}

class _RunningCard extends ConsumerWidget {
  const _RunningCard({required this.walk, required this.mesh, required this.now});

  final CoverageWalk walk;
  final MeshState mesh;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = walk.pings.isEmpty ? null : sampleOf(walk, walk.pings.last, mesh.messages, now);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(GwSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pinging ${mesh.nameOf(walk.dest)} every ${walk.intervalS} s',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: GwSpace.xs),
            Text(_summary(walk, mesh, now)),
            if (last != null) ...[
              const SizedBox(height: GwSpace.xs),
              Row(
                children: [
                  Icon(Icons.circle, size: 12, color: coverageLook(last).$2),
                  const SizedBox(width: GwSpace.xs),
                  Expanded(child: Text('Ping ${walk.pings.last.n}: ${coverageLook(last).$1}')),
                ],
              ),
            ],
            const SizedBox(height: GwSpace.md),
            OutlinedButton.icon(
              onPressed: ref.read(coverageProvider.notifier).stop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop walk'),
            ),
          ],
        ),
      ),
    );
  }
}
