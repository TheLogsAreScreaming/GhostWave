import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../link/ble.dart';
import 'theme.dart';

/// Scans for GhostWave nodes over Bluetooth and connects to one.
class BleScanScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const BleScanScreen({super.key});

  @override
  ConsumerState<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends ConsumerState<BleScanScreen> {
  final Map<String, BleAdvert> _found = {};
  StreamSubscription<BleAdvert>? _sub;
  Timer? _stop;
  bool _scanning = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  @override
  void dispose() {
    _stop?.cancel();
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    final radio = ref.read(bleRadioProvider);
    setState(() {
      _problem = null;
      _found.clear();
    });
    try {
      await radio.ensurePermissions();
    } on BlePermissionException {
      if (mounted) setState(() => _problem = 'GhostWave needs the Nearby devices permission to find Bluetooth nodes.');
      return;
    }
    final state = await radio.availability();
    if (!mounted) return;
    if (state != BleAvailability.on && state != BleAvailability.unknown) {
      setState(
        () => _problem = switch (state) {
          BleAvailability.off => 'Bluetooth is off. Switch it on, then scan again.',
          BleAvailability.unsupported => 'This phone has no Bluetooth LE.',
          _ => 'GhostWave is not allowed to use Bluetooth. Allow Nearby devices in the app\'s settings.',
        },
      );
      return;
    }
    await _sub?.cancel();
    setState(() => _scanning = true);
    _sub = radio.scan().listen(
      (a) {
        if (mounted) setState(() => _found[a.id] = a);
      },
      onError: (Object e) {
        if (mounted) setState(() => _problem = 'Scan failed: $e');
        unawaited(_end());
      },
    );
    _stop?.cancel();
    _stop = Timer(const Duration(seconds: 30), () => unawaited(_end()));
  }

  Future<void> _end() async {
    _stop?.cancel();
    final s = _sub;
    _sub = null;
    await s?.cancel();
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(BleAdvert a) async {
    final navigator = Navigator.of(context);
    await _end();
    await ref.read(nodeAddressProvider.notifier).connectAddress(BleNodeRef(a.id, a.name).encode());
    navigator.popUntil((r) => r.isFirst);
  }

  static String _signal(int rssi) => switch (rssi) {
    >= -60 => 'strong',
    >= -80 => 'fair',
    _ => 'weak',
  };

  @override
  Widget build(BuildContext context) {
    final nodes = _found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth nodes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'The first time you connect, Android asks for a 6-digit passkey. It is 654321 unless it was changed '
                'on the node. After that, the phone reconnects by itself.\n\n'
                'A node talks to one phone at a time, and stops advertising while connected.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_problem != null)
            Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error))
          else if (_scanning && nodes.isEmpty)
            const ListTile(
              leading: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 3)),
              title: Text('Looking for GhostWave nodes…'),
            )
          else if (nodes.isEmpty)
            const Text('No nodes found. Check that the node is on and close by.'),
          for (final a in nodes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bluetooth),
              title: Text(a.name),
              subtitle: Text('${_signal(a.rssi)} signal · ${a.rssi} dBm', style: GwText.mono.copyWith(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => unawaited(_connect(a)),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _scanning ? null : () => unawaited(_start()),
            icon: const Icon(Icons.refresh),
            label: Text(_scanning ? 'Scanning…' : 'Scan again'),
          ),
        ],
      ),
    );
  }
}
