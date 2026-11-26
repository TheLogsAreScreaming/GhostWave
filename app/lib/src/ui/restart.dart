import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../link/session.dart';
import 'widgets.dart';

/// Asks, then restarts the connected node (protocol 1.13), so saved settings
/// that apply after a restart take effect. True if the node took the request.
Future<bool> confirmRestartNode(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      icon: const Icon(Icons.restart_alt),
      title: const Text('Restart the node?'),
      content: const Text(
        'It restarts in a couple of seconds and the app reconnects by itself.\n\n'
        'Saved settings, contacts and channels are kept. Messages and SOS it is holding '
        'for other nodes are lost.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Restart')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await ref.read(meshProvider.notifier).restartNode();
    if (context.mounted) showSnack(context, 'Restarting. The app reconnects in a few seconds.');
    return true;
  } on NodeError catch (e) {
    if (context.mounted) showSnack(context, 'Not restarted: ${e.message}');
  } on Object catch (e) {
    if (context.mounted) showSnack(context, 'Not restarted: $e');
  }
  return false;
}

/// Asks, then powers the connected node off (protocol 1.16). True if the node
/// took the request.
Future<bool> confirmPowerOffNode(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      icon: const Icon(Icons.power_settings_new),
      title: const Text('Power off the node?'),
      content: const Text(
        'It stops sending and listening in a couple of seconds, and the app loses the link.\n\n'
        'To turn it back on, press its reset button (or its button, on boards that have one), '
        'or unplug it and plug it back in.\n\n'
        'Saved settings, contacts and channels are kept. Messages it is holding for other nodes are lost.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Power off')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await ref.read(meshProvider.notifier).powerOffNode();
    if (context.mounted) showSnack(context, 'Powering off.');
    return true;
  } on NodeError catch (e) {
    if (context.mounted) showSnack(context, 'Not powered off: ${e.message}');
  } on Object catch (e) {
    if (context.mounted) showSnack(context, 'Not powered off: $e');
  }
  return false;
}
