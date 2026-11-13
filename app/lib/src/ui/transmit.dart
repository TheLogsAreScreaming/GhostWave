import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../link/session.dart';
import 'theme.dart';
import 'widgets.dart';

/// Asks, then turns the node's transmitter on (or off). A fresh board only
/// listens until this: turning it on is the user's call, after checking the
/// antenna and the region.
Future<void> confirmSetTransmit(BuildContext context, WidgetRef ref, {required bool on}) async {
  final ok = on
      ? await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            icon: const Icon(Icons.cell_tower),
            title: const Text('Turn transmit on?'),
            content: const Text(
              'Check two things first:\n\n'
              '• The LoRa antenna is screwed on. Transmitting without one can damage the radio.\n'
              '• The node\'s region matches where you are (US915 unless you changed it). '
              'Only transmit where that band is allowed.\n\n'
              'Messages waiting on this phone go out once it is on.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Turn on')),
            ],
          ),
        )
      : await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Turn transmit off?'),
            content: const Text(
              'Your node will only listen. Messages and SOS from this phone wait until transmit is on again. '
              'An SOS started on the node itself still goes out.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: GwColors.alert, foregroundColor: GwColors.onAlert),
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Turn off'),
              ),
            ],
          ),
        );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(meshProvider.notifier).setTransmit(on);
    if (context.mounted) showSnack(context, on ? 'Transmit is on' : 'Transmit is off');
  } on NodeError catch (e) {
    if (context.mounted) showSnack(context, 'Not changed: ${e.message}');
  } on Object catch (e) {
    if (context.mounted) showSnack(context, 'Not changed: $e');
  }
}
