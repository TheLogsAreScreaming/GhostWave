import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../app/providers.dart';
import '../data/models.dart';
import '../link/contact_card.dart';
import 'add_contact_screen.dart';
import 'channel_screens.dart';
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

    final peopleUnread = mesh.unread.values.fold(0, (a, b) => a + b);
    final channelUnread = mesh.channelUnread.values.fold(0, (a, b) => a + b);
    final people = contacts.isEmpty && nearby.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                online
                    ? 'No contacts yet. Nodes in radio range show up here on their own once your node '
                          'has heard their identity (usually within a minute). Or tap "Add" and scan '
                          'another GhostWave user\'s QR code (Me tab).'
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
                  child: Text('Heard nearby, waiting for their key'),
                ),
                for (final n in nearby)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.cell_tower)),
                    title: Text(nodeIdHex(n.nodeId), style: GwText.mono),
                    subtitle: Text([timeAgo(n.lastSeen), if (n.pos != null) n.pos.toString()].join(' · ')),
                    trailing: const Icon(Icons.info_outline),
                    onTap: () => _showHeardNode(context, ref, n),
                  ),
              ],
            ],
          );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chats'),
          actions: [
            IconButton(
              tooltip: 'Reload from node',
              onPressed: online
                  ? () {
                      unawaited(ref.read(meshProvider.notifier).refreshContacts());
                      unawaited(ref.read(meshProvider.notifier).refreshChannels());
                    }
                  : null,
              icon: const Icon(Icons.refresh),
            ),
            const LinkChip(),
          ],
          bottom: TabBar(
            tabs: [
              Tab(child: _TabLabel('People', peopleUnread)),
              Tab(child: _TabLabel('Channels', channelUnread)),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddSheet(context),
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
        body: TabBarView(children: [people, const ChannelsList()]),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.text, this.unread);

  final String text;
  final int unread;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text),
      if (unread > 0) ...[const SizedBox(width: 6), Badge(label: Text('$unread'))],
    ],
  );
}

/// Add a contact, make a channel, or join one.
void _showAddSheet(BuildContext context) {
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Add a contact'),
              subtitle: const Text('Scan their QR code (Me tab) or paste their card'),
              onTap: () {
                Navigator.of(sheet).pop();
                unawaited(
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AddContactScreen())),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('New channel'),
              subtitle: const Text('A group chat with a new secret key, shared by QR code'),
              onTap: () {
                Navigator.of(sheet).pop();
                unawaited(showNewChannelDialog(context));
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Join a channel'),
              subtitle: const Text('Scan or paste a channel card (ghostwave-ch:…)'),
              onTap: () {
                Navigator.of(sheet).pop();
                unawaited(
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const AddContactScreen(channelsFirst: true))),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
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
          if (c.keyChanged) ...[
            // the warning icon below says it
          ] else if (c.pinned) ...[
            const SizedBox(width: 4),
            const Tooltip(message: 'Key pinned from a contact card', child: Icon(Icons.verified, size: 16)),
          ] else ...[
            const SizedBox(width: 4),
            const Tooltip(
              message: 'Key learned over the air (not checked against a QR code)',
              child: Icon(Icons.wifi_tethering, size: 16),
            ),
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

/// Explains a heard node the app cannot message yet, and what to do.
void _showHeardNode(BuildContext context, WidgetRef ref, Neighbor n) {
  final id = nodeIdHex(n.nodeId);
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(id, style: Theme.of(sheet).textTheme.titleLarge?.merge(GwText.mono)),
              const SizedBox(height: 8),
              Text(
                'This node is in radio range, but your node does not have its key yet, so it cannot '
                'be messaged. Your node asks for the key on its own (an IDENT request). When it '
                'arrives, the node moves to your contacts, usually within a minute.\n\n'
                'To add it right away, scan its QR code or paste its contact card text '
                '(ghostwave:$id:…). The virtual mesh script prints the card key for each node.',
                style: Theme.of(sheet).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      unawaited(ref.read(meshProvider.notifier).refreshContacts());
                    },
                    child: const Text('Check again'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      unawaited(
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AddContactScreen())),
                      );
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Add by card'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
