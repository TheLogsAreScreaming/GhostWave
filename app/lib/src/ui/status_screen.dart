import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../gen/ghostwave.pb.dart' as pb;
import 'widgets.dart';

/// The node's `Status` counters, refreshed every 10 s while visible.
class StatusScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const StatusScreen({super.key});

  @override
  ConsumerState<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends ConsumerState<StatusScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => ref.invalidate(nodeStatusProvider));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(nodeStatusProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Node status'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(nodeStatusProvider),
            icon: const Icon(Icons.refresh),
          ),
          const LinkChip(),
        ],
      ),
      body: switch (status) {
        AsyncData(value: null) => const NotConnected(),
        AsyncData(:final value?) => _StatusList(value),
        AsyncError(:final error) => Center(child: Text('Could not read status: $error')),
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
    final rows = <(String, String)>[
      ('Uptime', formatUptime(s.uptimeS)),
      ('Transmit', s.txOff ? 'OFF (type tx on on the serial console)' : 'on, or not reported'),
      ('SOS active (ours)', s.sosActive ? 'YES' : 'no'),
      ('SOS alerts held', '${s.sosHeld}'),
      ('Neighbors', '${s.neighbors}'),
      ('Store (carry-forward)', '${s.storeSize}'),
      ('Apps connected', '${s.clients}'),
      ('Events queued for apps', '${s.queued}'),
      ('Frames sent', '${s.tx}'),
      ('Frames received', '${s.rx}'),
      ('Received, bad', '${s.rxBad}'),
      ('Received, auth failed', '${s.rxAuthFail}'),
      ('Delivered to us', '${s.delivered}'),
      ('Forwarded', '${s.forwarded}'),
      ('Stored for later', '${s.stored}'),
      ('Airtime', '${(s.airMs.toInt() / 1000).toStringAsFixed(1)} s'),
    ];
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => ListTile(
        dense: true,
        title: Text(rows[i].$1),
        trailing: Text(rows[i].$2, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
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
