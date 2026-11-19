import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../app/node_hygiene.dart';
import '../link/contact_card.dart' show nodeIdHex;
import 'node_mark.dart';
import 'theme.dart';
import 'widgets.dart';

/// The nodes the user ignores, each with a button to show it again.
class IgnoredNodesScreen extends ConsumerWidget {
  /// Creates the screen.
  const IgnoredNodesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(ignoredNodesProvider).toList()..sort();
    final mesh = ref.watch(meshProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ignored nodes')),
      body: ids.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(GwSpace.xl),
                child: Text(
                  'No ignored nodes. Open a node\'s details and tap the eye button to hide it from '
                  'your chats and the map.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(GwSpace.lg),
                  child: Text(
                    'Hidden from your chats and the map, and they never notify you. Their messages are '
                    'still kept and they still relay for the mesh.',
                  ),
                ),
                for (final id in ids)
                  ListTile(
                    leading: NodeMark(nodeId: id),
                    title: Text(mesh.nameOf(id), overflow: TextOverflow.ellipsis),
                    subtitle: Text(nodeIdHex(id), style: GwText.mono),
                    trailing: TextButton(
                      onPressed: () {
                        ref.read(ignoredNodesProvider.notifier).unignore(id);
                        showSnack(context, '${mesh.nameOf(id)} is shown again');
                      },
                      child: const Text('Show again'),
                    ),
                  ),
              ],
            ),
    );
  }
}
