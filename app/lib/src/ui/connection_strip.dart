/// A one-line connection summary for chat screens. Hidden while the link is
/// up; otherwise says what is happening in words, and a tap shows the details.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/radios.dart';
import '../link/node_link.dart';
import 'connect_screen.dart' show LinkStateCard;
import 'my_radios_screen.dart';
import 'theme.dart';

/// The strip's words for [state], or null when there is nothing to say.
/// [radio] names the active radio once the phone has more than one.
(IconData, String)? connectionSummary(LinkState? state, {String? radio}) => switch (state) {
  null => null,
  LinkUp() => radio == null ? null : (Icons.settings_input_antenna, 'Using $radio. Tap to switch radios.'),
  LinkIdle() => (Icons.link_off, 'Not connected. Messages wait on this phone.'),
  LinkConnecting() => (Icons.sync, 'Connecting to ${radio ?? 'your radio'}… Messages wait on this phone.'),
  LinkWaiting(:final retryIn) => (
    Icons.schedule,
    '${radio ?? 'Radio'} link dropped. Retrying in ${retryIn.inSeconds} s; messages wait on this phone.',
  ),
  LinkNeedsPin() => (Icons.lock_outline, '${radio ?? 'Your radio'} needs its PIN. Messages wait on this phone.'),
  LinkFailed() => (Icons.error_outline, 'Not connected: the link stopped. Tap for what to do.'),
};

/// Shows [connectionSummary] for the current link, or nothing while it is up.
class ConnectionStrip extends ConsumerWidget {
  /// Creates the strip.
  const ConnectionStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(linkStateProvider).value;
    // name the radio only when there is more than one to mix up
    final several = ref.watch(radiosProvider.select((l) => l.length > 1));
    final radio = several ? ref.watch(activeRadioProvider)?.displayName : null;
    final summary = connectionSummary(state, radio: radio);
    if (summary == null || state == null) return const SizedBox.shrink();
    final (icon, text) = summary;
    final scheme = Theme.of(context).colorScheme;
    final failed = state is LinkFailed;
    return Material(
      color: failed ? GwColors.alertContainer : scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => state is LinkUp
            ? unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyRadiosScreen())))
            : unawaited(
                showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (sheet) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(GwSpace.md, 0, GwSpace.md, GwSpace.md),
                      child: Consumer(
                        builder: (context, ref, _) {
                          final live = ref.watch(linkStateProvider).value ?? state;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [LinkStateCard(state: live)],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
        child: Semantics(
          button: true,
          hint: state is LinkUp ? 'Shows your radios' : 'Shows connection details',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: GwSpace.md, vertical: GwSpace.sm),
            child: Row(
              children: [
                Icon(icon, size: 18, color: failed ? GwColors.onAlertContainer : null),
                const SizedBox(width: GwSpace.sm),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: failed ? GwColors.onAlertContainer : null),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: failed ? GwColors.onAlertContainer : null),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
