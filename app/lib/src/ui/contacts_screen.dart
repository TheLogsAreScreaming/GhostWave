import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../app/preferences.dart';
import '../app/providers.dart';
import '../data/mesh_store.dart';
import '../data/models.dart';
import '../gen/ghostwave.pb.dart' as pb;
import '../link/contact_card.dart';
import '../link/session.dart';
import 'add_contact_screen.dart';
import 'channel_screens.dart';
import 'chat_screen.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

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
    int waiting(int peer) =>
        (mesh.messages[peer] ?? const <ChatMessage>[]).where((m) => m.outgoing && m.state == MsgState.pending).length;
    // messages written for a node that has gone quiet stay findable until its key arrives
    final held = {
      for (final MapEntry(key: peer, value: msgs) in mesh.messages.entries)
        if (!mesh.contacts.containsKey(peer) && !mesh.neighbors.containsKey(peer) && waiting(peer) > 0)
          peer: Neighbor(nodeId: peer, lastSeen: msgs.last.at),
    };
    final nearby = [...mesh.neighbors.values.where((n) => !mesh.contacts.containsKey(n.nodeId)), ...held.values]
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(GwSpace.lg + GwSpace.sm, GwSpace.xl, GwSpace.lg, GwSpace.xs),
                  child: Text(
                    'Heard nearby, waiting for their key',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: GwColors.mutedText),
                  ),
                ),
                for (final n in nearby)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.cell_tower)),
                    title: Text(nodeIdHex(n.nodeId), style: GwText.mono),
                    subtitle: Text(
                      [
                        timeAgo(n.lastSeen),
                        if (n.pos != null) n.pos.toString(),
                        if (waiting(n.nodeId) > 0) '${waiting(n.nodeId)} waiting for key',
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.info_outline),
                    onTap: () => _showHeardNode(context, ref, n),
                  ),
              ],
            ],
          );

    final list = DefaultTabController(
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
          ],
          bottom: TabBar(
            // large text: tabs size to their labels and scroll instead of overflowing
            isScrollable: MediaQuery.textScalerOf(context).scale(1) > 1.3,
            tabAlignment: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? TabAlignment.start : null,
            padding: const EdgeInsets.fromLTRB(GwSpace.lg, 0, GwSpace.lg, GwSpace.sm),
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
        body: Column(
          children: [
            if (mesh.historyProblem != HistoryProblem.none) _HistoryProblemNotice(mesh.historyProblem),
            Expanded(child: TabBarView(children: [people, const ChannelsList()])),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        // side by side once the chat itself still gets a comfortable width
        if (box.maxWidth < 840) return list;
        final open = ref.watch(openChatProvider);
        return Row(
          children: [
            SizedBox(
              width: (box.maxWidth * 0.36).clamp(320, 420),
              child: ChatPaneScope(child: list),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: switch (open) {
                null => const _NoChatOpen(),
                OpenPeer(:final id) => ChatScreen(key: ValueKey(open), peer: id),
                OpenChannel(:final name) => ChannelChatScreen(key: ValueKey(open), channel: name),
              },
            ),
          ],
        );
      },
    );
  }
}

/// The empty right pane before a chat is picked.
class _NoChatOpen extends StatelessWidget {
  const _NoChatOpen();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.forum_outlined, size: 48, color: GwColors.outline),
          const SizedBox(height: GwSpace.md),
          Text('Pick a conversation', style: text.titleMedium),
          const SizedBox(height: GwSpace.xs),
          Text(
            'Messages go out over the mesh, end to end encrypted.',
            style: text.bodyMedium?.copyWith(color: GwColors.mutedText),
          ),
        ],
      ),
    );
  }
}

/// Says why earlier chats are missing, and whether new ones are being kept.
class _HistoryProblemNotice extends StatelessWidget {
  const _HistoryProblemNotice(this.problem);

  final HistoryProblem problem;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = switch (problem) {
      HistoryProblem.locked =>
        "Saved chats for this node can't be opened right now: this phone didn't release the key. "
            "Nothing was deleted. New messages won't be saved until you restart the app.",
      HistoryProblem.unreadable =>
        "Saved chats for this node couldn't be read, so this list starts empty. "
            'If you have a backup, you can restore it in Settings.',
      HistoryProblem.none => '',
    };
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
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
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final name = mesh.nameOf(c.nodeId);
    final details = [
      nodeIdHex(c.nodeId),
      if (c.lastSeen != null) 'seen ${timeAgo(c.lastSeen!)}',
      if (c.pos != null) c.pos.toString(),
    ].join(' · ');
    final (IconData trustIcon, String trust, Color trustColor) = c.keyChanged
        ? (Icons.warning_amber, 'This node announced a different key', scheme.error)
        : c.pinned
        ? (Icons.verified, 'Key pinned from a contact card', GwColors.spectralCyan)
        : (Icons.wifi_tethering, 'Key learned over the air (not checked against a QR code)', GwColors.mutedText);
    final twoPane = ChatPaneScope.isTwoPane(context);
    void open() {
      if (twoPane) {
        ref.read(openChatProvider.notifier).open(OpenPeer(c.nodeId));
      } else {
        unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatScreen(peer: c.nodeId))));
      }
    }

    final selected = twoPane && ref.watch(openChatProvider) == OpenPeer(c.nodeId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GwSpace.sm),
      child: ListTile(
        selected: selected,
        selectedTileColor: GwColors.surface2,
        selectedColor: GwColors.mistWhite,
        leading: _Avatar(name: name, id: c.nodeId),
        title: Row(
          children: [
            Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: GwSpace.xs + 2),
            Tooltip(
              message: trust,
              child: Icon(trustIcon, size: 16, color: trustColor, semanticLabel: trust),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (last != null)
              Text(
                '${last.outgoing ? 'You: ' : ''}${last.text}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: unread > 0 ? text.bodyMedium?.copyWith(color: GwColors.mistWhite) : null,
              ),
            Text(details, style: GwText.mono.copyWith(fontSize: 11.5, color: GwColors.outline)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (last != null) Text(clockTime(last.at), style: text.labelSmall?.copyWith(color: GwColors.mutedText)),
            if (unread > 0) ...[
              const SizedBox(height: GwSpace.xs),
              Semantics(
                label: '$unread unread',
                excludeSemantics: true,
                child: Badge(label: Text('$unread')),
              ),
            ],
          ],
        ),
        onTap: open,
      ),
    );
  }
}

/// A round avatar with the name's first letter, tinted per node.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.id});

  final String name;
  final int id;

  @override
  Widget build(BuildContext context) {
    final tint = id.isEven ? GwColors.spectralCyan : GwColors.violetLight;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: 22,
        backgroundColor: tint.withValues(alpha: 0.16),
        foregroundColor: tint,
        child: Text(
          name.characters.first.toUpperCase(),
          style: const TextStyle(fontFamily: GwFonts.headline, fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
    );
  }
}

/// Asks the node for [peer]'s key and says what happened. A reply only means
/// the request went out.
Future<void> _askForKey(MeshController ctl, ScaffoldMessengerState messenger, int peer) async {
  if (!ctl.nodeCanRequestKey) {
    await ctl.refreshContacts();
    return;
  }
  String note;
  try {
    await ctl.requestKey(peer);
    await ctl.refreshContacts();
    note = 'Asked. The node moves to your contacts if it answers.';
  } on NodeError catch (e) {
    note = e.code == pb.Error_Code.RATE_LIMITED ? 'Already asked moments ago. Try again in 30 seconds.' : e.message;
  } on Object {
    note = 'Could not reach your node.';
  }
  messenger.showSnackBar(SnackBar(content: Text(note)));
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
                'Your node has heard this node but does not have its key yet. Messages you write now '
                'stay on this phone and are sent, encrypted, once the key arrives. Your node asks '
                'for the key on its own (an IDENT request), and the node then moves to your contacts, '
                'usually within a minute. A node that has left radio range cannot answer.\n\n'
                'To add it right away, scan its QR code or paste its contact card text '
                '(ghostwave:$id:…). The virtual mesh script prints the card key for each node.',
                style: Theme.of(sheet).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () {
                      final messenger = ScaffoldMessenger.of(context);
                      final ctl = ref.read(meshProvider.notifier);
                      Navigator.of(sheet).pop();
                      unawaited(_askForKey(ctl, messenger, n.nodeId));
                    },
                    child: Text(ref.read(meshProvider.notifier).nodeCanRequestKey ? 'Ask for key' : 'Check again'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      unawaited(
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatScreen(peer: n.nodeId))),
                      );
                    },
                    child: const Text('Write message'),
                  ),
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
