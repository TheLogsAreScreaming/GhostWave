import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../link/contact_card.dart';
import '../link/node_link.dart';
import 'connect_screen.dart';
import 'theme.dart';

/// The app header above the tabs: the brand, which node the app is talking
/// to, and the link state as a word in a pill. Tap opens the Connect screen.
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
    final text = Theme.of(context).textTheme;
    // word: the state at a glance; detail: which node, or what to do
    final (IconData icon, Color color, String word, String detail) = switch (state) {
      LinkUp(:final info) => (
        Icons.circle,
        GwColors.success,
        'Online',
        _nodeLabel(decodeLenient(info.name), info.nodeId),
      ),
      LinkConnecting(:final target) => (Icons.sync, scheme.tertiary, 'Connecting', target),
      LinkWaiting(:final target, :final retryIn) => (
        Icons.schedule,
        scheme.tertiary,
        'Retrying',
        '$target in ${retryIn.inSeconds} s',
      ),
      LinkFailed(:final reason) => (Icons.error_outline, scheme.error, 'Stopped', reason),
      LinkNeedsPin(:final wrong) => (
        Icons.lock_outline,
        scheme.error,
        'PIN',
        wrong ? 'Wrong PIN · tap to enter it again' : 'This node needs a PIN · tap to enter it',
      ),
      LinkIdle() => (Icons.link_off, scheme.outline, 'Offline', address == null ? 'Not connected' : 'Tap to connect'),
    };
    // the wordmark only where it fits on one line: large text on a narrow phone keeps just the logo
    final wordmark = MediaQuery.sizeOf(context).width / MediaQuery.textScalerOf(context).scale(1) >= 300;
    return Material(
      color: GwColors.ghostBlack,
      child: SafeArea(
        top: safeTop,
        bottom: false,
        child: Semantics(
          button: true,
          label: '$word. $detail',
          hint: 'Opens the connection screen',
          excludeSemantics: true,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ConnectScreen())),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.fromLTRB(GwSpace.lg + GwSpace.xs, GwSpace.sm, GwSpace.md, GwSpace.sm),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: GwColors.outlineVariant)),
              ),
              child: Row(
                children: [
                  Image.asset('assets/brand/logo.png', width: 26, height: 26),
                  const SizedBox(width: GwSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (wordmark)
                          Text(
                            'GhostWave',
                            style: text.titleMedium?.copyWith(
                              fontFamily: GwFonts.headline,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        Text(detail, style: text.bodySmall?.copyWith(color: GwColors.mutedText)),
                      ],
                    ),
                  ),
                  const SizedBox(width: GwSpace.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: GwSpace.md, vertical: GwSpace.xs + 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(GwRadius.pill),
                      border: Border.all(color: color.withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: icon == Icons.circle ? 9 : 15, color: color),
                        const SizedBox(width: GwSpace.xs + 2),
                        Text(word, style: text.labelLarge?.copyWith(color: GwColors.mistWhite)),
                      ],
                    ),
                  ),
                ],
              ),
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
