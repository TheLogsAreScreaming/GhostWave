/// The timeline: messages, new nodes, signal changes, alerts and shared
/// positions in one feed, newest first, with a filter per kind and search.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../data/timeline.dart';
import 'channel_screens.dart';
import 'chat_screen.dart';
import 'format.dart';
import 'node_journal_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Most entries drawn at once; search or filter to reach older ones.
const int kTimelineShown = 400;

/// The icon for each kind (shown with its label, never alone).
IconData timelineIcon(TimelineKind k) => switch (k) {
  TimelineKind.message => Icons.chat_bubble_outline,
  TimelineKind.node => Icons.person_add_alt,
  TimelineKind.signal => Icons.network_check,
  TimelineKind.alert => Icons.sos,
  TimelineKind.position => Icons.place_outlined,
};

/// The singular word read out for one entry of each kind.
String timelineKindWord(TimelineKind k) => switch (k) {
  TimelineKind.message => 'Message',
  TimelineKind.node => 'New node',
  TimelineKind.signal => 'Signal change',
  TimelineKind.alert => 'Alert',
  TimelineKind.position => 'Shared position',
};

/// "Today", "Yesterday" or the date, for the day headers.
String timelineDay(DateTime t, DateTime now) {
  final d = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// Everything that happened on the mesh, in one filterable feed.
class TimelineScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  final _search = TextEditingController();
  String _query = '';
  final Set<TimelineKind> _kinds = {...TimelineKind.values};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(TimelineKind k, bool on) => setState(() => on ? _kinds.add(k) : _kinds.remove(k));

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    final now = ref.watch(clockProvider)();
    final all = buildTimeline(
      nameOf: (id) => journalName(mesh, id),
      messages: mesh.messages,
      channelMessages: mesh.channelMessages,
      journal: mesh.journal,
      signalLog: mesh.signalLog,
      alerts: mesh.alerts,
      ownSos: mesh.ownSos,
    );
    final shown = filterTimeline(all, _kinds, _query);
    final counts = {for (final k in TimelineKind.values) k: all.where((e) => e.kind == k).length};
    final rows = <Widget>[];
    String? day;
    for (final e in shown.take(kTimelineShown)) {
      final d = timelineDay(e.at, now);
      if (d != day) {
        day = d;
        rows.add(_DayHeader(d));
      }
      rows.add(_EventTile(event: e, now: now));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Timeline')),
      body: ReadableWidth(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(GwSpace.md, GwSpace.md, GwSpace.md, GwSpace.xl),
          children: [
            SignalPanel(
              icon: Icons.timeline,
              title: 'Everything, newest first',
              detail: all.isEmpty
                  ? 'Nothing yet. Messages, nodes heard for the first time, signal changes of '
                        '$kSignalShiftDb dB or more, SOS alerts and shared positions show up here '
                        'as they happen.'
                  : '${all.length} entries kept on this phone with this node\'s history. '
                        'Signal changes are logged when a node is $kSignalShiftDb dB stronger or weaker '
                        'than the last time it was heard.',
            ),
            if (all.isNotEmpty) ...[
              const SizedBox(height: GwSpace.md),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: 'Search the timeline',
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
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: GwSpace.xs),
              // one scrolling row: long labels at large text never squeeze or clip
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: GwSpace.xs,
                  children: [
                    for (final k in TimelineKind.values)
                      Semantics(
                        label: '${k.label}, ${counts[k]}',
                        excludeSemantics: true,
                        selected: _kinds.contains(k),
                        button: true,
                        child: FilterChip(
                          avatar: Icon(timelineIcon(k), size: 18),
                          label: Text('${k.label} ${counts[k]}'),
                          selected: _kinds.contains(k),
                          onSelected: (on) => _toggle(k, on),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: GwSpace.sm),
              if (shown.isEmpty)
                const ListTile(title: Text('Nothing matches these filters'))
              else ...[
                ...rows,
                if (shown.length > kTimelineShown)
                  Padding(
                    padding: const EdgeInsets.all(GwSpace.md),
                    child: Text(
                      'Showing the newest $kTimelineShown of ${shown.length}. Search or filter to find older ones.',
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(GwSpace.xs, GwSpace.md, GwSpace.xs, GwSpace.xs),
    child: Semantics(header: true, child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
  );
}

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.event, required this.now});

  final TimelineEvent event;
  final DateTime now;

  Widget? _target(WidgetRef ref) {
    final e = event;
    if (e.kind == TimelineKind.message && e.channel != null) return ChannelChatScreen(channel: e.channel!);
    final id = e.nodeId;
    if (id == null) return null;
    return switch (e.kind) {
      TimelineKind.node || TimelineKind.signal =>
        ref.read(meshProvider).journal.entries.containsKey(id) ? JournalNodeScreen(nodeId: id) : null,
      _ => ChatScreen(peer: id),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = event;
    final time = clockTime(e.at, now: now);
    final target = _target(ref);
    final word = timelineKindWord(e.kind);
    return Semantics(
      label: '$word. ${e.title}. ${e.detail.isEmpty ? '' : '${e.detail}. '}$time, ${timeAgo(e.at, now: now)}',
      button: target != null,
      excludeSemantics: true,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: GwSpace.xs),
        leading: Icon(timelineIcon(e.kind), color: e.kind == TimelineKind.alert ? GwColors.errorText : null),
        title: Text(e.title),
        subtitle: Text([word, if (e.detail.isNotEmpty) e.detail].join(' · ')),
        trailing: Text(time, style: GwText.mono),
        onTap: target == null
            ? null
            : () => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => target))),
      ),
    );
  }
}
