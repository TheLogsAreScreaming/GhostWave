import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../link/contact_card.dart';
import '../link/node_link.dart';
import 'connect_screen.dart';
import 'theme.dart';

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
      LinkNeedsPin() => (Icons.lock_outline, 'PIN'),
      LinkIdle() => (Icons.link_off, 'Offline'),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: state is LinkUp ? GwColors.success : null),
        label: Text(label),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ConnectScreen())),
      ),
    );
  }
}

/// Slim header above the tabs: which node the app is talking to. Tap opens
/// the Connect screen.
class ConnectionBar extends ConsumerWidget {
  /// Creates the bar. [safeTop] pads for the status bar (false when another
  /// banner above already does).
  const ConnectionBar({this.safeTop = true, super.key});

  /// Whether to add the status-bar inset.
  final bool safeTop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(linkStateProvider).value ?? const LinkIdle();
    final address = ref.watch(nodeAddressProvider);
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color, String text) = switch (state) {
      LinkUp(:final info) => (
        Icons.link,
        GwColors.success,
        'Connected to ${_nodeLabel(decodeLenient(info.name), info.nodeId)}',
      ),
      LinkConnecting(:final target) => (Icons.sync, scheme.tertiary, 'Connecting to $target…'),
      LinkWaiting(:final target, :final retryIn) => (
        Icons.schedule,
        scheme.tertiary,
        'Reconnecting to $target in ${retryIn.inSeconds} s',
      ),
      LinkFailed(:final reason) => (Icons.error_outline, scheme.error, 'Stopped: $reason'),
      LinkNeedsPin(:final wrong) => (
        Icons.lock_outline,
        scheme.error,
        wrong ? 'Wrong PIN · tap to enter it again' : 'This node needs a PIN · tap to enter it',
      ),
      LinkIdle() => (Icons.link_off, scheme.outline, address == null ? 'Not connected' : 'Offline · tap to connect'),
    };
    return Material(
      color: GwColors.surface1,
      child: SafeArea(
        top: safeTop,
        bottom: false,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ConnectScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.labelLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _nodeLabel(String name, int id) => name.isEmpty ? nodeIdHex(id) : '$name (${nodeIdHex(id)})';

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

bool _pinDialogOpen = false;

/// Asks for the PIN [s] needs, unless the dialog is already up.
Future<void> askForPin(BuildContext context, WidgetRef ref, LinkNeedsPin s) async {
  if (_pinDialogOpen) return;
  _pinDialogOpen = true;
  final ctl = TextEditingController();
  final pin = await showDialog<String>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) {
        final ok = RegExp(r'^[0-9]{4,16}$').hasMatch(ctl.text.trim());
        return AlertDialog(
          title: const Text('Enter the node\'s PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.target, style: GwText.mono),
              const SizedBox(height: 12),
              TextField(
                controller: ctl,
                autofocus: true,
                keyboardType: TextInputType.number,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  border: const OutlineInputBorder(),
                  errorText: s.wrong ? 'That PIN was wrong.' : null,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => ok ? Navigator.pop(dialog, ctl.text.trim()) : null,
              ),
              const SizedBox(height: 8),
              const Text('The node prints it when it starts. The app remembers it for this node.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
            FilledButton(
              onPressed: ok ? () => Navigator.pop(dialog, ctl.text.trim()) : null,
              child: const Text('Connect'),
            ),
          ],
        );
      },
    ),
  );
  // not disposed here: the dialog's closing animation still uses it
  _pinDialogOpen = false;
  if (pin != null) await ref.read(nodeAddressProvider.notifier).submitPin(s.target, pin);
}

/// Shows [message] in a snack bar.
void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
