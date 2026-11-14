import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../app/preferences.dart';
import '../app/providers.dart';
import '../data/mesh_store.dart';
import '../data/message_refs.dart';
import '../data/models.dart';
import '../gen/ghostwave.pb.dart' as pb;
import '../link/contact_card.dart';
import '../link/session.dart';
import 'add_contact_screen.dart';
import 'channel_screens.dart';
import 'chat_screen.dart';
import 'format.dart';
import 'link_ping.dart';
import 'node_journal_screen.dart';
import 'node_mark.dart';
import 'theme.dart';
import 'timeline_screen.dart';
import 'trace_route.dart';
import 'widgets.dart';

/// Contacts (with unread counts and last-seen) and nodes heard nearby.
class ContactsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

enum _PeopleFilter { all, unread, contacts, nearby }

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _search = TextEditingController();
  String _query = '';
  _PeopleFilter _filter = _PeopleFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    bool matches(int id) {
      final name = mesh.nameOf(id).toLowerCase();
      final hex = nodeIdHex(id).toLowerCase();
      return name.contains(_query) || hex.contains(_query);
    }

    bool visible(int id) {
      return matches(id) && (_filter != _PeopleFilter.nearby || mesh.neighbors.containsKey(id));
    }

    final shownContacts = contacts.where(
      (c) => visible(c.nodeId) && (_filter != _PeopleFilter.unread || (mesh.unread[c.nodeId] ?? 0) > 0),
    );
    final shownNearby = nearby.where(
      (n) => _filter != _PeopleFilter.contacts && _filter != _PeopleFilter.unread && visible(n.nodeId),
    );

    final peopleUnread = mesh.unread.values.fold(0, (a, b) => a + b);
    final channelUnread = mesh.channelUnread.values.fold(0, (a, b) => a + b);
    final people = contacts.isEmpty && nearby.isEmpty
        ? Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(GwSpace.xl),
              child: SignalPanel(
                icon: Icons.forum_outlined,
                title: 'Your conversations',
                detail: online
                    ? 'No contacts yet. Nodes in radio range show up here on their own once your node '
                          'has heard their identity (usually within a minute). Or tap "Add" and scan '
                          'another GhostWave user\'s QR code (Me tab).'
                    : 'Connect to a node to load its contacts.',
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              Padding(
                padding: const EdgeInsets.all(GwSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SignalPanel(
                      icon: Icons.forum_outlined,
                      title: 'Your conversations',
                      detail: peopleUnread == 0 ? 'All caught up' : '$peopleUnread unread messages',
                    ),
                    const SizedBox(height: GwSpace.md),
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        labelText: 'Find a node',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                              ),
                      ),
                      onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                    ),
                    Wrap(
                      spacing: GwSpace.xs,
                      children: [
                        for (final choice in _PeopleFilter.values)
                          ChoiceChip(
                            label: _CountLabel(
                              switch (choice) {
                                _PeopleFilter.all => 'All',
                                _PeopleFilter.unread => 'Unread',
                                _PeopleFilter.contacts => 'Contacts',
                                _PeopleFilter.nearby => 'Nearby',
                              },
                              switch (choice) {
                                _PeopleFilter.all => contacts.length + nearby.length,
                                _PeopleFilter.unread => mesh.unread.values.where((n) => n > 0).length,
                                _PeopleFilter.contacts => contacts.length,
                                _PeopleFilter.nearby => mesh.neighbors.length,
                              },
                            ),
                            selected: _filter == choice,
                            onSelected: (_) => setState(() => _filter = choice),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (shownContacts.isEmpty && shownNearby.isEmpty)
                ListTile(
                  title: Text(_filter == _PeopleFilter.unread ? 'No matching unread chats' : 'No matching nodes'),
                ),
              for (final c in shownContacts) _ContactTile(c, unread: mesh.unread[c.nodeId] ?? 0, mesh: mesh),
              if (shownNearby.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(GwSpace.lg + GwSpace.sm, GwSpace.xl, GwSpace.lg, GwSpace.xs),
                  child: Text(
                    'Heard nearby, waiting for their key',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: GwColors.mutedText),
                  ),
                ),
                for (final n in shownNearby)
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: GwSpace.md, vertical: GwSpace.xs),
                    color: GwColors.surface1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: NodeMark(nodeId: n.nodeId),
                      title: Text(nodeIdHex(n.nodeId), style: GwText.mono),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: GwSpace.xs),
                        child: NodeMetrics(nodeId: n.nodeId, mesh: mesh, waiting: waiting(n.nodeId), keyKnown: false),
                      ),
                      trailing: const Icon(Icons.info_outline, semanticLabel: 'What this means'),
                      onTap: () => _showHeardNode(context, ref, n),
                    ),
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
              tooltip: 'Timeline',
              onPressed: () => unawaited(
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TimelineScreen())),
              ),
              icon: const Icon(Icons.timeline),
            ),
            IconButton(
              tooltip: 'Node journal',
              onPressed: () => unawaited(
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NodeJournalScreen())),
              ),
              icon: const Icon(Icons.menu_book_outlined),
            ),
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: GwSpace.md, vertical: GwSpace.xs),
      color: selected ? GwColors.surface3 : GwColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        selected: selected,
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
                '${last.outgoing ? 'You: ' : ''}${friendlyText(last.text)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: unread > 0 ? text.bodyMedium?.copyWith(color: GwColors.mistWhite) : null,
              ),
            Text(nodeIdHex(c.nodeId), style: GwText.mono.copyWith(fontSize: 11.5, color: GwColors.mutedText)),
            const SizedBox(height: GwSpace.xs),
            NodeMetrics(nodeId: c.nodeId, mesh: mesh, contact: c),
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

/// A filter label with its count, e.g. "Nearby 3".
class _CountLabel extends StatelessWidget {
  const _CountLabel(this.label, this.count);

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label, $count',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: GwSpace.xs),
        Text('$count', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: GwColors.mutedText)),
      ],
    ),
  );
}

/// A node's measurements as small chips: when it was last heard (and whether
/// it is in range now), its signal, distance and direction from you, how its
/// key is trusted, and messages waiting for it. Only what was really measured.
class NodeMetrics extends ConsumerWidget {
  /// Creates the row for [nodeId].
  const NodeMetrics({
    required this.nodeId,
    required this.mesh,
    this.contact,
    this.waiting = 0,
    this.keyKnown = true,
    super.key,
  });

  /// The node.
  final int nodeId;

  /// Mesh state to read from.
  final MeshState mesh;

  /// Its contact entry, if it is one.
  final Contact? contact;

  /// Messages written to it and still waiting.
  final int waiting;

  /// Whether we hold its key (false for a heard node waiting for one).
  final bool keyKnown;

  /// Heard within this long counts as in range now (beacons are minutes apart).
  static const inRangeFor = Duration(minutes: 15);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final units = ref.watch(unitsProvider);
    final n = mesh.neighbors[nodeId];
    final c = contact;
    final heard = n?.lastSeen ?? c?.lastSeen;
    final inRange = n != null && DateTime.now().difference(n.lastSeen) < inRangeFor;
    final pos = n?.pos ?? c?.pos;
    final own = mesh.ownPos;
    final chips = <(IconData, String, Color?)>[
      if (heard != null)
        (
          inRange ? Icons.circle : Icons.history,
          '${inRange ? 'in range · ' : ''}${timeAgo(heard)}',
          inRange ? GwColors.success : null,
        ),
      if (n?.rssiDbm case final d?) (Icons.signal_cellular_alt, signalText(d), null),
      if (own != null && pos != null)
        (
          Icons.near_me_outlined,
          '${formatDistance(own.distanceTo(pos), units)} ${compassPoint(own.bearingTo(pos))}',
          null,
        ),
      if (c != null && c.keyChanged)
        (Icons.warning_amber, 'key changed', scheme.error)
      else if (c != null && c.pinned)
        (Icons.verified, 'verified by QR', GwColors.spectralCyan)
      else if (c != null)
        (Icons.wifi_tethering, 'key learned over the air', null)
      else if (!keyKnown)
        (Icons.key_off_outlined, 'waiting for key', null),
      if (waiting > 0) (Icons.schedule_send_outlined, '$waiting waiting', scheme.tertiary),
    ];
    final style = Theme.of(context).textTheme.labelSmall;
    return Wrap(
      spacing: GwSpace.xs,
      runSpacing: GwSpace.xs,
      children: [
        for (final (icon, label, color) in chips)
          DecoratedBox(
            decoration: BoxDecoration(
              color: GwColors.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: (color ?? scheme.outlineVariant).withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: icon == Icons.circle ? 8 : 12, color: color ?? GwColors.mutedText),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(label, style: style?.copyWith(color: color ?? GwColors.mutedText)),
                  ),
                ],
              ),
            ),
          ),
      ],
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
                  if (ref.read(meshProvider).journal.entries.containsKey(n.nodeId))
                    TextButton(
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        unawaited(
                          Navigator.of(context)
                              .push(MaterialPageRoute<void>(builder: (_) => JournalNodeScreen(nodeId: n.nodeId))),
                        );
                      },
                      child: const Text('Journal'),
                    ),
                  if (ref.read(meshProvider.notifier).nodeCanLinkPing)
                    TextButton(
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        unawaited(showLinkPing(context, ref, n.nodeId));
                      },
                      child: const Text('Ping'),
                    ),
                  if (ref.read(meshProvider.notifier).nodeCanTrace)
                    TextButton(
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        unawaited(showTraceRoute(context, n.nodeId));
                      },
                      child: const Text('Trace route'),
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
