import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../gen/ghostwave.pb.dart' as pb;
import 'theme.dart';
import 'field_tools_screen.dart';
import 'widgets.dart';

/// The node's `Status` counters, refreshed every 10 s while visible.
class StatusScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const StatusScreen({super.key});

  @override
  ConsumerState<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends ConsumerState<StatusScreen> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) _startPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(nodeStatusProvider);
      _startPolling();
    }
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => ref.invalidate(nodeStatusProvider));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    ref.invalidate(nodeStatusProvider);
    try {
      await ref.read(nodeStatusProvider.future);
    } on Object {
      // The status provider exposes the error to the screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(nodeStatusProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Node status'),
        actions: [
          IconButton(
            tooltip: 'Field tools',
            onPressed: () {
              Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const FieldToolsScreen()));
            },
            icon: const Icon(Icons.science_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(nodeStatusProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: switch (status) {
        AsyncData(value: null) => const NotConnected(),
        AsyncData(:final value?) => RefreshIndicator(onRefresh: _refreshStatus, child: _StatusList(value)),
        AsyncError(:final error) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not read status: $error', textAlign: TextAlign.center),
                TextButton.icon(
                  onPressed: () => ref.invalidate(nodeStatusProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry status request'),
                ),
              ],
            ),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _StatusList extends StatelessWidget {
  const _StatusList(this.s);

  final pb.Status s;

  @override
  Widget build(BuildContext context) {
    final tiles = <_Metric>[
      _Metric(Icons.timer_outlined, 'Uptime', formatUptime(s.uptimeS)),
      s.txOff
          ? const _Metric(
              Icons.portable_wifi_off,
              'Transmit',
              'OFF',
              note: 'type tx on on the serial console',
              alert: true,
            )
          : const _Metric(Icons.cell_tower, 'Transmit', 'on', note: 'or not reported'),
      _Metric(Icons.hub_outlined, 'Neighbors', '${s.neighbors}'),
      s.sosActive
          ? const _Metric(Icons.sos, 'SOS (ours)', 'ACTIVE', alert: true)
          : const _Metric(Icons.shield_outlined, 'SOS (ours)', 'off'),
    ];
    final mesh = <(String, String)>[
      ('SOS alerts held', '${s.sosHeld}'),
      ('Store (carry-forward)', '${s.storeSize}'),
      ('Delivered to us', '${s.delivered}'),
      ('Forwarded', '${s.forwarded}'),
      ('Stored for later', '${s.stored}'),
      ('Apps connected', '${s.clients}'),
      ('Events queued for apps', '${s.queued}'),
    ];
    final radio = <(String, String)>[
      ('Frames sent', '${s.tx}'),
      ('Frames received', '${s.rx}'),
      ('Received, bad', '${s.rxBad}'),
      ('Received, auth failed', '${s.rxAuthFail}'),
      ('Airtime', '${(s.airMs.toInt() / 1000).toStringAsFixed(1)} s'),
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(GwSpace.lg, GwSpace.sm, GwSpace.lg, GwSpace.xl),
      children: [
        ReadableWidth(
          maxWidth: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SignalPanel(
                icon: Icons.monitor_heart_outlined,
                title: 'Radio overview',
                detail: 'Live activity and delivery counters from your connected node.',
              ),
              const SizedBox(height: GwSpace.lg),
              LayoutBuilder(
                builder: (context, box) {
                  final columns = box.maxWidth >= 560 ? 4 : 2;
                  final w = (box.maxWidth - GwSpace.md * (columns - 1)) / columns;
                  return Wrap(
                    spacing: GwSpace.md,
                    runSpacing: GwSpace.md,
                    children: [for (final t in tiles) SizedBox(width: w, child: t)],
                  );
                },
              ),
              const SectionLabel('Messages'),
              _Rows(mesh),
              const SectionLabel('Radio'),
              _Rows(radio),
            ],
          ),
        ),
      ],
    );
  }
}

/// One headline number: an icon, the value as a word or number, and its name.
class _Metric extends StatelessWidget {
  const _Metric(this.icon, this.label, this.value, {this.note, this.alert = false});

  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final color = alert ? scheme.onErrorContainer : GwColors.mistWhite;
    return Semantics(
      container: true,
      label: '$label: $value${note == null ? '' : ', $note'}',
      excludeSemantics: true,
      child: Card(
        color: alert ? scheme.errorContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(GwSpace.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: alert ? color : GwColors.spectralCyan),
              const SizedBox(height: GwSpace.sm),
              Text(
                value,
                style: text.headlineSmall?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              Text(label, style: text.labelMedium?.copyWith(color: alert ? color : GwColors.mutedText)),
              if (note != null) Text(note!, style: text.bodySmall?.copyWith(color: alert ? color : GwColors.outline)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label and value rows in one card.
class _Rows extends StatelessWidget {
  const _Rows(this.rows);

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) const Divider(indent: GwSpace.lg, endIndent: GwSpace.lg),
          ListTile(
            dense: true,
            title: Text(r.$1, style: Theme.of(context).textTheme.bodyMedium),
            trailing: Text(
              r.$2,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ],
    ),
  );
}

/// `1d 02:03:04`-style uptime.
String formatUptime(int seconds) {
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d > 0 ? '${d}d ' : ''}${two(h)}:${two(m)}:${two(s)}';
}
