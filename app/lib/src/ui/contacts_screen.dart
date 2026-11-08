import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../app/providers.dart';
import '../data/models.dart';
import '../link/contact_card.dart';
import 'add_contact_screen.dart';
import 'chat_screen.dart';
import 'format.dart';
import 'widgets.dart';
import 'theme.dart';

/// Contacts (with unread counts and last-seen) and nodes heard nearby.
class ContactsScreen extends ConsumerWidget {
  /// Creates the screen.
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesh = ref.watch(meshProvider);
    final online = ref.watch(sessionProvider) != null;
    DateTime lastActivity(Contact c) {
      final msgs = mesh.messages[c.nodeId];
      final last = msgs == null || msgs.isEmpty ? null : msgs.last.at;
      final seen = c.lastSeen;
      if (last == null) return seen ?? DateTime(2000);
      if (seen == null) return last;
      return last.isAfter(seen) ? last : seen;
    }

    final contacts = mesh.contacts.values.toList()..sort((a, b) => lastActivity(b).compareTo(lastActivity(a)));
    final nearby = mesh.neighbors.values.where((n) => !mesh.contacts.containsKey(n.nodeId)).toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            tooltip: 'Reload from node',
            onPressed: online ? () => ref.read(meshProvider.notifier).refreshContacts() : null,
            icon: const Icon(Icons.refresh),
          ),
          const LinkChip(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AddContactScreen())),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Add contact'),
      ),
      body: contacts.isEmpty && nearby.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  online
                      ? 'No contacts yet. Tap "Add contact" and scan another GhostWave user\'s QR code (Me tab).'
                      : 'Connect to a node to load its contacts.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final c in contacts) _ContactTile(c, unread: mesh.unread[c.nodeId] ?? 0, mesh: mesh),
                if (nearby.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('Heard nearby (not contacts)'),
                  ),
                  for (final n in nearby)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.cell_tower)),
                      title: Text(nodeIdHex(n.nodeId), style: GwText.mono),
                      subtitle: Text([timeAgo(n.lastSeen), if (n.pos != null) n.pos.toString()].join(' · ')),
                    ),
                ],
              ],
            ),
    );
  }
}

class _ContactTile extends ConsumerWidget {
  const _ContactTile(this.c, {required this.unread, required this.mesh});

  final Contact c;
  final int unread;
  final MeshState mesh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msgs = mesh.messages[c.nodeId];
    final last = msgs == null || msgs.isEmpty ? null : msgs.last;
    final lines = <String>[
      if (last != null) '${last.outgoing ? 'You: ' : ''}${last.text}',
      [
        nodeIdHex(c.nodeId),
        if (c.lastSeen != null) 'seen ${timeAgo(c.lastSeen!)}',
        if (c.pos != null) c.pos.toString(),
      ].join(' · '),
    ];
    final name = mesh.nameOf(c.nodeId);
    return ListTile(
      leading: CircleAvatar(child: Text(name.characters.first.toUpperCase())),
      title: Row(
        children: [
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
          if (c.pinned) ...[
            const SizedBox(width: 4),
            const Tooltip(message: 'Key pinned from a contact card', child: Icon(Icons.verified, size: 16)),
          ],
          if (c.keyChanged) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'This node announced a different key',
              child: Icon(Icons.warning_amber, size: 18, color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      subtitle: Text(lines.join('\n'), maxLines: 2, overflow: TextOverflow.ellipsis),
      isThreeLine: last != null,
      trailing: unread > 0 ? Badge(label: Text('$unread')) : null,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatScreen(peer: c.nodeId))),
    );
  }
}
