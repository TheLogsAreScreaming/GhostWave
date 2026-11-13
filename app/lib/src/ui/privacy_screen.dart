import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/field_reports_controller.dart';
import '../app/mesh_controller.dart';
import 'settings_screen.dart' show confirmAndResetAppData;
import 'theme.dart';
import 'widgets.dart';

/// What GhostWave keeps on this phone, what leaves it and where to, and the
/// buttons to delete it.
class PrivacyScreen extends ConsumerWidget {
  /// Creates the page.
  const PrivacyScreen({super.key});

  Future<bool> _confirm(BuildContext context, String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: GwColors.alert, foregroundColor: GwColors.onAlert),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    Widget section(String title, List<(IconData, String, String)> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title),
        Card(
          child: Column(
            children: [
              for (final (icon, head, body) in rows)
                ListTile(leading: Icon(icon), title: Text(head), subtitle: Text(body)),
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & data')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(GwSpace.lg, GwSpace.sm, GwSpace.lg, GwSpace.xl),
        children: [
          ReadableWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SignalPanel(
                  icon: Icons.shield_outlined,
                  title: 'No accounts, no tracking',
                  detail:
                      'GhostWave has no sign-up, no analytics, no ads and no servers of its own. It talks to your '
                      'radio, and your radio talks to the mesh.',
                ),
                section('Kept on this phone', const [
                  (
                    Icons.forum_outlined,
                    'Chats, contacts, channels and SOS records',
                    'Encrypted on the phone with a key held in its secure storage. Kept until you delete them.',
                  ),
                  (Icons.password, 'Node PINs', 'In the phone\'s secure storage, never in plain files.'),
                  (
                    Icons.science_outlined,
                    'Saved field tests',
                    'Counters, positions and distances you recorded. Kept until you delete them.',
                  ),
                  (
                    Icons.hiking,
                    'Trip plan and your check-ins',
                    'Who you check in with, reminder settings, and which check-ins you sent.',
                  ),
                  (
                    Icons.route_outlined,
                    'Trails',
                    'Only during a trip: your position and your trip contacts\', for 24 hours, encrypted with your chats.',
                  ),
                  (Icons.map_outlined, 'Offline maps', 'Map tiles for areas you saved.'),
                  (Icons.tune, 'Settings', 'Units, the node address, and the like.'),
                ]),
                section('What leaves this phone', const [
                  (
                    Icons.bluetooth,
                    'To your own radio',
                    'Over Bluetooth (paired, encrypted) or your network (encrypted after the PIN). Your messages, '
                        'and your phone\'s position only if you turn on location sharing.',
                  ),
                  (
                    Icons.lock_outline,
                    'Over the mesh, from your radio',
                    'Direct messages and check-ins are encrypted end to end. Channel messages are encrypted with '
                        'the channel key. Your radio\'s beacons carry its ID and, if it has one, its position. '
                        'An SOS carries your position and battery, readable by any GhostWave node, so help can find you.',
                  ),
                  (
                    Icons.public,
                    'Map tiles',
                    'The map downloads tiles from the tile server set in Offline maps. That server sees your '
                        'internet address and which area you look at. Saved areas work with no connection.',
                  ),
                  (
                    Icons.ios_share,
                    'Only when you choose',
                    'Backups, field test exports and copied text go only where you send them.',
                  ),
                ]),
                const SectionLabel('Delete'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.forum_outlined),
                        title: const Text('Delete chat history'),
                        subtitle: const Text(
                          'Every direct and channel message on this phone. Contacts and channels stay.',
                        ),
                        onTap: () async {
                          final ok = await _confirm(
                            context,
                            'Delete chat history?',
                            'Deletes every direct and channel message on this phone. Messages others have stay with '
                                'them. This cannot be undone.',
                            'Delete',
                          );
                          if (!ok || !context.mounted) return;
                          ref.read(meshProvider.notifier).deleteAllMessages();
                          showSnack(context, 'Chat history deleted');
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.science_outlined),
                        title: const Text('Delete saved field tests'),
                        onTap: () async {
                          final ok = await _confirm(
                            context,
                            'Delete all field tests?',
                            'Deletes every saved field test on this phone. Export any you want to keep first.',
                            'Delete',
                          );
                          if (!ok || !context.mounted) return;
                          ref.read(fieldReportsProvider.notifier).deleteAll();
                          showSnack(context, 'Field tests deleted');
                        },
                      ),
                      ListTile(
                        leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
                        title: const Text('Delete everything on this phone'),
                        subtitle: const Text('Chats, contacts, field tests, trip, maps, PINs and settings'),
                        onTap: () => unawaited(confirmAndResetAppData(context, ref)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: GwSpace.md),
                  child: Text(
                    'Your radio keeps its own contacts, channels and identity. Deleting here does not change it.',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
