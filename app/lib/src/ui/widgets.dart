import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../link/node_link.dart';
import 'connect_screen.dart';

/// App-bar chip showing the link state; tap opens the Connect screen.
class LinkChip extends ConsumerWidget {
  /// Creates the chip.
  const LinkChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(linkStateProvider).value ?? const LinkIdle();
    final (IconData icon, String label) = switch (state) {
      LinkUp() => (Icons.link, 'Online'),
      LinkConnecting() => (Icons.sync, 'Connecting'),
      LinkWaiting() => (Icons.schedule, 'Retrying'),
      LinkFailed() => (Icons.error_outline, 'Stopped'),
      LinkIdle() => (Icons.link_off, 'Offline'),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: state is LinkUp ? Colors.green.shade600 : null),
        label: Text(label),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ConnectScreen())),
      ),
    );
  }
}

/// Placeholder body when there is no link.
class NotConnected extends StatelessWidget {
  /// Creates the placeholder.
  const NotConnected({super.key, this.what = 'this'});

  /// What needs a link, e.g. "status".
  final String what;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link_off, size: 48),
          const SizedBox(height: 12),
          Text('Connect to a node to see $what.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ConnectScreen())),
            child: const Text('Connect'),
          ),
        ],
      ),
    ),
  );
}

/// Shows [message] in a snack bar.
void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
