/// The node journal: every node this app has heard, what it seems to be, and
/// the user's own tags and notes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../app/preferences.dart';
import '../data/node_journal.dart';
import '../link/contact_card.dart';
import 'chat_screen.dart';
import 'format.dart';
import 'node_details_screen.dart';
import 'node_mark.dart';
import 'theme.dart';
import 'widgets.dart';

/// Tag ideas offered when adding one.
const List<String> kSuggestedTags = ['friend', 'home base', 'repeater', 'trailhead', 'vehicle', 'family', 'unknown'];

/// What the list is narrowed to.
sealed class _JournalFilter {
  const _JournalFilter();
}

final class _AllNodes extends _JournalFilter {
  const _AllNodes();
}

final class _ByTrait extends _JournalFilter {
  const _ByTrait(this.trait);
  final NodeTrait trait;

  @override
  bool operator ==(Object other) => other is _ByTrait && other.trait == trait;

  @override
  int get hashCode => trait.hashCode;
}

final class _Tagged extends _JournalFilter {
  const _Tagged();
}

/// The name to show for [id]: the contact's, else the announced one, else hex.
String journalName(MeshState mesh, int id) {
  final contact = mesh.contacts[id]?.name ?? '';
  if (contact.isNotEmpty) return contact;
  final heard = mesh.journal.entries[id]?.name ?? '';
  return heard.isEmpty ? nodeIdHex(id) : heard;
}

/// Every node heard, newest first, with search and behaviour filters.
class NodeJournalScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const NodeJournalScreen({super.key});

  @override
  ConsumerState<NodeJournalScreen> createState() => _NodeJournalScreenState();
}

class _NodeJournalScreenState extends ConsumerState<NodeJournalScreen> {
  final _search = TextEditingController();
  String _query = '';
  _JournalFilter _filter = const _AllNodes();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    final now = ref.watch(clockProvider)();
    final units = ref.watch(unitsProvider);
    final journal = mesh.journal;
    final readings = {
      for (final e in journal.entries.values)
        e.nodeId: describeNode(e, journal, now, distance: (m) => formatDistance(m, units)),
    };
    final all = journal.entries.values.toList()..sort((a, b) => b.lastHeard.compareTo(a.lastHeard));

    bool matches(JournalEntry e) {
      if (_query.isEmpty) return true;
      return journalName(mesh, e.nodeId).toLowerCase().contains(_query) ||
          nodeIdHex(e.nodeId).contains(_query) ||
          e.tags.any((t) => t.toLowerCase().contains(_query)) ||
          e.note.toLowerCase().contains(_query);
    }

    bool passes(JournalEntry e, _JournalFilter f) => switch (f) {
      _AllNodes() => true,
      _ByTrait(:final trait) => readings[e.nodeId]!.any((r) => r.trait == trait),
      _Tagged() => e.tags.isNotEmpty,
    };

    final filters = <_JournalFilter>[
      const _AllNodes(),
      for (final t in NodeTrait.values)
        if (all.any((e) => passes(e, _ByTrait(t)))) _ByTrait(t),
      if (all.any((e) => e.tags.isNotEmpty)) const _Tagged(),
    ];
    final filter = filters.contains(_filter) ? _filter : const _AllNodes();
    final shown = [
      for (final e in all)
        if (matches(e) && passes(e, filter)) e,
    ];
    final today = all.where((e) => dayKey(e.lastHeard) == dayKey(now)).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Node journal')),
      body: ReadableWidth(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(GwSpace.md, GwSpace.md, GwSpace.md, GwSpace.xl),
          children: [
            SignalPanel(
              icon: Icons.menu_book_outlined,
              title: 'Every node you have heard',
              detail: all.isEmpty
                  ? 'Nothing logged yet. While your node is connected, every node it hears '
                        '(beacons, messages, identity) is written here on its own, with when and '
                        'how it was heard. Labels such as "Always-on relay" appear once there is '
                        'enough to go on.'
                  : '${all.length} logged · $today heard today. Labels are guesses from what this '
                        'app has heard; tap a node to see the evidence.',
            ),
            if (all.isNotEmpty) ...[
              const SizedBox(height: GwSpace.md),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: 'Search names, IDs, tags and notes',
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
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: GwSpace.xs),
              // one scrolling row: long labels at large text never squeeze or clip
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: GwSpace.xs,
                  children: [
                    for (final f in filters)
                      ChoiceChip(
                        label: _CountLabel(switch (f) {
                          _AllNodes() => 'All',
                          _ByTrait(:final trait) => trait.label,
                          _Tagged() => 'Tagged',
                        }, all.where((e) => passes(e, f)).length),
                        selected: filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: GwSpace.sm),
              if (shown.isEmpty)
                const ListTile(title: Text('No matching nodes'))
              else
                for (final e in shown) _JournalTile(entry: e, readings: readings[e.nodeId]!, mesh: mesh, now: now),
            ],
          ],
        ),
      ),
    );
  }
}

/// A filter label with its count, read as one phrase.
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

/// The headline label, or "Still learning".
String _headline(List<TraitReading> readings) {
  if (readings.isEmpty) return 'Still learning';
  final r = readings.first;
  return '${r.trait.label} · ${r.strength} (${r.percent}%)';
}

class _JournalTile extends StatelessWidget {
  const _JournalTile({required this.entry, required this.readings, required this.mesh, required this.now});

  final JournalEntry entry;
  final List<TraitReading> readings;
  final MeshState mesh;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = journalName(mesh, entry.nodeId);
    final hex = nodeIdHex(entry.nodeId);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: GwSpace.xs),
      color: GwColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: NodeMark(nodeId: entry.nodeId),
        title: Text(name, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name != hex) Text(hex, style: GwText.mono.copyWith(fontSize: 11.5, color: GwColors.mutedText)),
            const SizedBox(height: GwSpace.xs),
            Row(
              children: [
                Icon(
                  readings.isEmpty ? Icons.hourglass_empty : Icons.insights_outlined,
                  size: 14,
                  color: readings.isEmpty ? GwColors.mutedText : GwColors.spectralCyan,
                ),
                const SizedBox(width: GwSpace.xs),
                Flexible(
                  child: Text(
                    _headline(readings),
                    style: text.labelMedium?.copyWith(
                      color: readings.isEmpty ? GwColors.mutedText : GwColors.spectralCyan,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'Last heard ${timeAgo(entry.lastHeard, now: now)} · heard ${entry.timesHeard} '
              '${entry.timesHeard == 1 ? 'time' : 'times'}',
              style: text.bodySmall?.copyWith(color: GwColors.mutedText),
            ),
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: GwSpace.xs),
              Wrap(spacing: GwSpace.xs, runSpacing: GwSpace.xs, children: [for (final t in entry.tags) _TagPill(t)]),
            ],
          ],
        ),
        trailing: entry.note.isEmpty
            ? null
            : const Tooltip(
                message: 'Has a note',
                child: Icon(Icons.sticky_note_2_outlined, size: 18, semanticLabel: 'Has a note'),
              ),
        onTap: () => unawaited(
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => JournalNodeScreen(nodeId: entry.nodeId))),
        ),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill(this.tag);

  final String tag;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Tag: $tag',
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: GwColors.phantomViolet.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(GwRadius.pill),
        border: Border.all(color: GwColors.violetLight.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GwSpace.sm, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sell_outlined, size: 11, color: GwColors.violetLight),
            const SizedBox(width: 4),
            Flexible(
              child: Text(tag, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: GwColors.violetLight)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One node's journal page: labels with evidence, the record, tags and notes.
class JournalNodeScreen extends ConsumerStatefulWidget {
  /// Creates the page for [nodeId].
  const JournalNodeScreen({required this.nodeId, super.key});

  /// The node.
  final int nodeId;

  @override
  ConsumerState<JournalNodeScreen> createState() => _JournalNodeScreenState();
}

class _JournalNodeScreenState extends ConsumerState<JournalNodeScreen> {
  late final TextEditingController _note = TextEditingController(
    text: ref.read(meshProvider).journal.entries[widget.nodeId]?.note ?? '',
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _addTag(JournalEntry e) async {
    final tag = await showDialog<String>(
      context: context,
      builder: (_) => _AddTagDialog(existing: e.tags),
    );
    if (tag == null || !mounted) return;
    ref.read(meshProvider.notifier).setJournalTags(e.nodeId, [...e.tags, tag]);
  }

  Future<void> _forget(String name) async {
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Forget $name?'),
        content: const Text(
          'Its record, tags and note are removed from this phone. If your node hears it again, '
          'it starts a fresh entry.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Forget')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    ref.read(meshProvider.notifier).forgetJournalEntry(widget.nodeId);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    final now = ref.watch(clockProvider)();
    final units = ref.watch(unitsProvider);
    final e = mesh.journal.entries[widget.nodeId];
    final hex = nodeIdHex(widget.nodeId);
    if (e == null) {
      return Scaffold(
        appBar: AppBar(title: Text(hex)),
        body: const Center(child: Text('This node is not in the journal.')),
      );
    }
    final name = journalName(mesh, e.nodeId);
    final readings = describeNode(e, mesh.journal, now, distance: (m) => formatDistance(m, units));
    final theme = Theme.of(context);
    final isContact = mesh.contacts.containsKey(e.nodeId);
    final own = mesh.ownPos;
    final pos = e.lastPos;
    String via() {
      const words = {
        HeardVia.beacon: 'beacon',
        HeardVia.ident: 'identity',
        HeardVia.direct: 'direct message',
        HeardVia.channel: 'channel message',
        HeardVia.sos: 'SOS',
      };
      final parts = [
        for (final v in HeardVia.values)
          if ((e.via[v] ?? 0) > 0) '${words[v]} ${e.via[v]}',
      ];
      return parts.isEmpty ? 'none recorded' : parts.join(' · ');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Node details',
            icon: const Icon(Icons.info_outline),
            onPressed: () => unawaited(openNodeDetails(context, e.nodeId)),
          ),
          if (isContact)
            IconButton(
              tooltip: 'Open chat',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => unawaited(
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatScreen(peer: e.nodeId))),
              ),
            ),
        ],
      ),
      body: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(GwSpace.lg, GwSpace.md, GwSpace.lg, GwSpace.xl),
          children: [
            Row(
              children: [
                NodeMark(nodeId: e.nodeId, size: 72, semanticLabel: 'Generated mark for node $hex'),
                const SizedBox(width: GwSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(header: true, child: Text(name, style: theme.textTheme.headlineSmall)),
                      if (name != hex) Text(hex, style: GwText.mono.copyWith(color: GwColors.mutedText)),
                      Text(
                        isContact ? 'In your contacts' : 'Heard, not a contact',
                        style: theme.textTheme.bodySmall?.copyWith(color: GwColors.mutedText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SectionLabel('What it seems to be'),
            if (readings.isEmpty)
              const _InfoCard(
                icon: Icons.hourglass_empty,
                title: 'Still learning',
                body:
                    'Not enough has been heard to say yet. Labels need a few hours of listening, '
                    'positions, or messages to go on.',
              )
            else
              for (final r in readings) _ReadingCard(r),
            const SectionLabel('Record'),
            _RecordRow('First heard', '${clockTime(e.firstHeard, now: now)} (${timeAgo(e.firstHeard, now: now)})'),
            _RecordRow('Last heard', '${clockTime(e.lastHeard, now: now)} (${timeAgo(e.lastHeard, now: now)})'),
            _RecordRow('Times heard', '${e.timesHeard}'),
            _RecordRow('Days heard', '${e.days.length} in the last $kJournalDayWindow days'),
            _RecordRow('Heard by', via()),
            if (e.lastRssi != null)
              _RecordRow(
                'Signal',
                'last ${signalText(e.lastRssi!)}${e.bestRssi == null ? '' : ' · best ${e.bestRssi} dBm'}',
              ),
            if (pos != null)
              _RecordRow(
                'Last position',
                own == null
                    ? '${pos.lat.toStringAsFixed(4)}, ${pos.lon.toStringAsFixed(4)}'
                    : '${formatDistance(own.distanceTo(pos), units)} ${compassPoint(own.bearingTo(pos))} of your node',
              ),
            if (e.fixes.length > 1)
              _RecordRow('Position spread', '${formatDistance(e.spreadM, units)} across ${e.fixes.length} positions'),
            const SectionLabel('Your tags'),
            Wrap(
              spacing: GwSpace.xs,
              runSpacing: GwSpace.xs,
              children: [
                for (final t in e.tags)
                  InputChip(
                    label: Text(t),
                    deleteButtonTooltipMessage: 'Remove tag $t',
                    onDeleted: () => ref.read(meshProvider.notifier).setJournalTags(e.nodeId, [
                      for (final x in e.tags)
                        if (x != t) x,
                    ]),
                  ),
                if (e.tags.length < kJournalMaxTags)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Add tag'),
                    onPressed: () => unawaited(_addTag(e)),
                  ),
              ],
            ),
            const SectionLabel('Notes'),
            TextField(
              controller: _note,
              minLines: 3,
              maxLines: 8,
              maxLength: kJournalMaxNoteLength,
              decoration: const InputDecoration(
                labelText: 'Your note',
                hintText: 'Where it is, who runs it, anything worth remembering',
                alignLabelWithHint: true,
              ),
              onChanged: (v) => ref.read(meshProvider.notifier).setJournalNote(e.nodeId, v),
            ),
            Text(
              'Saved on this phone, encrypted with your chat history, and included in backups.',
              style: theme.textTheme.bodySmall?.copyWith(color: GwColors.mutedText),
            ),
            const SizedBox(height: GwSpace.xl),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => unawaited(_forget(name)),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Forget this node'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard(this.reading);

  final TraitReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = reading;
    return Card(
      margin: const EdgeInsets.only(bottom: GwSpace.sm),
      color: GwColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(GwSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: GwSpace.sm,
              children: [
                Semantics(header: true, child: Text(r.trait.label, style: theme.textTheme.titleMedium)),
                Text(
                  '${r.strength} · ${r.percent}%',
                  style: theme.textTheme.labelLarge?.copyWith(color: GwColors.spectralCyan),
                ),
              ],
            ),
            const SizedBox(height: GwSpace.sm),
            Semantics(
              container: true,
              label: 'Confidence ${r.percent} percent, ${r.strength}',
              excludeSemantics: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(GwRadius.pill),
                child: LinearProgressIndicator(
                  value: r.confidence,
                  minHeight: 6,
                  color: GwColors.spectralCyan,
                  backgroundColor: GwColors.surface3,
                ),
              ),
            ),
            const SizedBox(height: GwSpace.sm),
            Text(r.trait.meaning, style: theme.textTheme.bodyMedium?.copyWith(color: GwColors.mutedText)),
            const SizedBox(height: GwSpace.sm),
            Text('Evidence', style: theme.textTheme.labelLarge),
            for (final line in r.evidence)
              Padding(
                padding: const EdgeInsets.only(top: GwSpace.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ExcludeSemantics(
                      child: Padding(
                        padding: EdgeInsets.only(top: 3, right: GwSpace.sm),
                        child: Icon(Icons.check, size: 14, color: GwColors.mutedText),
                      ),
                    ),
                    Expanded(child: Text(line, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: GwColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(icon, color: GwColors.mutedText),
        title: Text(title),
        subtitle: Text(body),
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GwSpace.xs),
        child: Wrap(
          spacing: GwSpace.sm,
          children: [
            Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: GwColors.mutedText)),
            Text(value, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _AddTagDialog extends StatefulWidget {
  const _AddTagDialog({required this.existing});

  final List<String> existing;

  @override
  State<_AddTagDialog> createState() => _AddTagDialogState();
}

class _AddTagDialogState extends State<_AddTagDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final tag = value.trim();
    if (tag.isEmpty) return;
    Navigator.of(context).pop(tag);
  }

  @override
  Widget build(BuildContext context) {
    final have = {for (final t in widget.existing) t.toLowerCase()};
    return AlertDialog(
      title: const Text('Add a tag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: kJournalMaxTagLength,
            decoration: const InputDecoration(labelText: 'Tag'),
            textInputAction: TextInputAction.done,
            onSubmitted: _submit,
          ),
          Wrap(
            spacing: GwSpace.xs,
            runSpacing: GwSpace.xs,
            children: [
              for (final s in kSuggestedTags)
                if (!have.contains(s)) ActionChip(label: Text(s), onPressed: () => _submit(s)),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => _submit(_text.text), child: const Text('Add')),
      ],
    );
  }
}
