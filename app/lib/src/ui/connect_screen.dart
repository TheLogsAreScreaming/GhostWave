import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../link/contact_card.dart';
import '../link/node_link.dart';
import '../link/transport.dart';
import 'theme.dart';

/// Enter the node's `host:port`, connect, see the link state.
class ConnectScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  late final TextEditingController _address;
  String? _error;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(text: ref.read(nodeAddressProvider) ?? '');
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final a = TcpAddress.tryParse(_address.text);
    if (a == null) {
      setState(() => _error = 'Use host:port, e.g. 192.168.1.20:47800');
      return;
    }
    setState(() => _error = null);
    FocusScope.of(context).unfocus();
    await ref.read(nodeAddressProvider.notifier).connectTo(a);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(linkStateProvider).value ?? const LinkIdle();
    final active = state is! LinkIdle && state is! LinkFailed;
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to a node')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Logo(),
          const SizedBox(height: 16),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Node address (host:port)',
              hintText: '192.168.1.20:47800',
              errorText: _error,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lan_outlined),
            ),
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _connect,
                  icon: const Icon(Icons.link),
                  label: Text(active ? 'Reconnect' : 'Connect'),
                ),
              ),
              if (active) ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => ref.read(nodeAddressProvider.notifier).disconnect(),
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          LinkStateCard(state: state),
          const SizedBox(height: 24),
          const _Help(),
        ],
      ),
    );
  }
}

/// A card describing [state].
class LinkStateCard extends ConsumerWidget {
  /// Creates the card.
  const LinkStateCard({required this.state, super.key});

  /// The state to show.
  final LinkState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color, String title, String detail) = switch (state) {
      LinkIdle() => (Icons.link_off, scheme.outline, 'Not connected', 'Enter the node address above.'),
      LinkConnecting(:final target, :final attempt) => (
        Icons.sync,
        scheme.tertiary,
        'Connecting…',
        attempt > 1 ? '$target (attempt $attempt)' : target,
      ),
      LinkUp(:final target, :final info) => (
        Icons.check_circle,
        GwColors.success,
        'Connected to ${decodeLenient(info.name)}',
        '$target · node ${nodeIdHex(info.nodeId)} · ${info.firmware}',
      ),
      LinkWaiting(:final target, :final reason, :final retryIn) => (
        Icons.schedule,
        scheme.tertiary,
        'Reconnecting in ${retryIn.inSeconds} s',
        '$target: $reason',
      ),
      LinkFailed(:final target, :final reason) => (Icons.error, scheme.error, 'Stopped', '$target: $reason'),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color, size: 32),
        title: Text(title),
        subtitle: Text(detail),
        trailing: state is LinkWaiting || state is LinkFailed
            ? TextButton(onPressed: () => ref.read(nodeLinkProvider).retryNow(), child: const Text('Retry now'))
            : null,
      ),
    );
  }
}

class _Help extends StatelessWidget {
  const _Help();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Testing without radios: on a computer on the same Wi-Fi, run\n'
          '  firmware/pi/tools/vmesh_lan.sh -n 4 --lan\n'
          'from the GhostWave repo. It prints one address per virtual node '
          '(ports 47800 and up). Enter one here.\n\n'
          'The link has no password yet: anyone on the network can drive the node. '
          'Use a Wi-Fi you trust.',
          style: style,
        ),
      ),
    );
  }
}

/// The GhostWave mark above the address field, with clear space around it.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Image.asset('assets/brand/logo.png', width: 96, height: 96, semanticLabel: 'GhostWave logo'),
          const SizedBox(height: 8),
          Text('GhostWave', style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    ),
  );
}
