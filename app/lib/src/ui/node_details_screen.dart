/// One node, everything the app knows about it: name and ID, when it was last
/// heard and whether directly, its signal over time, where it is relative to
/// you, and the telemetry its beacons carry (client protocol 1.12).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/location_share.dart';
import '../app/mesh_controller.dart';
import '../app/preferences.dart';
import '../app/providers.dart';
import '../data/models.dart';
import '../data/signal_history.dart';
import '../link/contact_card.dart';
import '../link/geo.dart';
import 'chat_screen.dart';
import 'format.dart';
import 'link_ping.dart';
import 'node_journal_screen.dart';
import 'node_mark.dart';
import 'theme.dart';
import 'trace_route.dart';
import 'widgets.dart';

/// Opens [NodeDetailsScreen] for [nodeId].
Future<void> openNodeDetails(BuildContext context, int nodeId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NodeDetailsScreen(nodeId: nodeId)));

/// The node details page.
class NodeDetailsScreen extends ConsumerStatefulWidget {
  /// Creates the page for [nodeId].
  const NodeDetailsScreen({required this.nodeId, super.key});

  /// The node shown.
  final int nodeId;

  /// Heard within this long counts as a direct neighbor now (beacons are minutes apart).
  static const neighborFor = Duration(minutes: 15);

  @override
  ConsumerState<NodeDetailsScreen> createState() => _NodeDetailsScreenState();
}

class _NodeDetailsScreenState extends ConsumerState<NodeDetailsScreen> {
  bool _asking = false;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_askTelemetry());
    });
  }

  /// Asks the connected node for the latest telemetry it holds for this node.
  Future<void> _askTelemetry() async {
    final ctl = ref.read(meshProvider.notifier);
    if (!ctl.nodeCanTelemetry || _asking) return;
    setState(() => _asking = true);
    try {
      await ctl.requestTelemetry(widget.nodeId);
    } on Object {
      // shown as "nothing heard"; the link status bar says if the node is gone
    } finally {
      if (mounted) {
        setState(() {
          _asking = false;
          _asked = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    final ctl = ref.read(meshProvider.notifier);
    final now = ref.watch(clockProvider)();
    final units = ref.watch(unitsProvider);
    final share = ref.watch(locationShareProvider);
    final id = widget.nodeId;
    final hex = nodeIdHex(id);
    final isSelf = id == mesh.nodeId;
    final name = isSelf ? 'Your node' : journalName(mesh, id);
    final contact = mesh.contacts[id];
    final neighbor = mesh.neighbors[id];
    final entry = mesh.journal.entries[id];
    final theme = Theme.of(context);

    final heardTimes = [?neighbor?.lastSeen, ?contact?.lastSeen, ?entry?.lastHeard];
    final lastHeard = heardTimes.isEmpty ? null : heardTimes.reduce((a, b) => a.isAfter(b) ? a : b);
    final direct = neighbor != null && now.difference(neighbor.lastSeen) < NodeDetailsScreen.neighborFor;

    // its position, and when that report arrived
    final (LatLon? pos, DateTime? posAt) = isSelf
        ? (mesh.ownPos, null)
        : neighbor?.pos != null
        ? (neighbor!.pos, neighbor.lastSeen)
        : contact?.pos != null
        ? (contact!.pos, contact.lastSeen)
        : (entry?.lastPos, entry?.lastHeard);

    // where "you" are: the phone's own fix while it is shared, else the node's
    final phoneFix = share.active ? share.lastSent : null;
    final (LatLon? from, String fromWhat) = phoneFix != null ? (phoneFix, 'your phone') : (mesh.ownPos, 'your node');

    final history = signalHistory(
      nodeId: id,
      messages: mesh.messages[id] ?? const [],
      channelMessages: mesh.channelMessages.values,
      signalLog: mesh.signalLog,
      neighbor: neighbor,
    );
    final telemetry = mesh.telemetry[id];
    final info = ref.watch(nodeInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Copy node ID',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: hex));
              if (context.mounted) showSnack(context, 'Node ID copied');
            },
          ),
        ],
      ),
      body: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(GwSpace.lg, GwSpace.md, GwSpace.lg, GwSpace.xl),
          children: [
            Row(
              children: [
                NodeMark(nodeId: id, size: 64, semanticLabel: 'Generated mark for node $hex'),
                const SizedBox(width: GwSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(header: true, child: Text(name, style: theme.textTheme.headlineSmall)),
                      Semantics(
                        label: 'Node ID ${hex.split('').join(' ')}',
                        excludeSemantics: true,
                        child: Text(hex, style: GwText.mono.copyWith(color: GwColors.mutedText)),
                      ),
                      if (!isSelf)
                        Text(
                          contact == null
                              ? 'Not a contact'
                              : contact.keyChanged
                              ? 'Contact · announced a different key'
                              : contact.pinned
                              ? 'Contact · key verified by QR'
                              : 'Contact · key learned over the air',
                          style: theme.textTheme.bodySmall?.copyWith(color: GwColors.mutedText),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SectionLabel('Heard'),
            _Fact(
              icon: Icons.schedule,
              label: 'Last heard',
              value: lastHeard == null
                  ? (isSelf ? 'Connected to this phone' : 'Not heard yet')
                  : '${timeAgo(lastHeard, now: now)} (${clockTime(lastHeard, now: now)})',
            ),
            if (!isSelf)
              _Fact(
                icon: direct ? Icons.circle : Icons.call_split,
                iconColor: direct ? GwColors.success : null,
                label: 'Direct neighbor',
                value: direct
                    ? 'Yes: your node heard its beacon ${timeAgo(neighbor.lastSeen, now: now)}'
                    : neighbor != null
                    ? 'Not lately: its last beacon was ${timeAgo(neighbor.lastSeen, now: now)}'
                    : 'No beacon heard while connected; messages may come through relays',
              ),
            if (!isSelf && entry != null)
              _Fact(
                icon: Icons.history,
                label: 'First heard',
                value: '${timeAgo(entry.firstHeard, now: now)} · heard ${entry.timesHeard} times',
              ),
            const SectionLabel('Where'),
            if (pos == null)
              _Fact(
                icon: Icons.location_off_outlined,
                label: 'Position',
                value: isSelf ? 'Your node has no position yet' : 'It has not reported a position',
              )
            else ...[
              _Fact(
                icon: Icons.place_outlined,
                label: 'Position',
                value: posAt == null ? pos.toString() : '$pos · reported ${timeAgo(posAt, now: now)}',
              ),
              if (!isSelf)
                if (from == null)
                  const _Fact(
                    icon: Icons.near_me_disabled_outlined,
                    label: 'Distance',
                    value: 'Your position is not known yet, so no distance',
                  )
                else
                  _Bearing(
                    distance: formatDistance(from.distanceTo(pos), units),
                    bearing: from.bearingTo(pos),
                    fromWhat: fromWhat,
                  ),
            ],
            const SectionLabel('Signal'),
            _SignalSection(history: history, best: entry?.bestRssi, now: now),
            const SectionLabel('Telemetry'),
            _TelemetrySection(
              reading: telemetry,
              connected: info != null,
              supported: info != null && info.protocolMinor >= 12,
              asking: _asking,
              asked: _asked,
              isSelf: isSelf,
              now: now,
              onRefresh: _askTelemetry,
            ),
            if (!isSelf) ...[
              const SectionLabel('Actions'),
              Wrap(
                spacing: GwSpace.sm,
                runSpacing: GwSpace.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => unawaited(
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatScreen(peer: id))),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Message'),
                  ),
                  if (entry != null)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => JournalNodeScreen(nodeId: id))),
                      ),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('Journal'),
                    ),
                  if (ctl.nodeCanLinkPing && neighbor != null)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(showLinkPing(context, ref, id)),
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Ping'),
                    ),
                  if (ctl.nodeCanTrace)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(showTraceRoute(context, id)),
                      icon: const Icon(Icons.route_outlined),
                      label: const Text('Trace route'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One labelled fact, read as "label: value".
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value, this.iconColor});

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GwSpace.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: ExcludeSemantics(
                child: Icon(icon, size: icon == Icons.circle ? 12 : 20, color: iconColor ?? GwColors.mutedText),
              ),
            ),
            const SizedBox(width: GwSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: text.labelMedium?.copyWith(color: GwColors.mutedText)),
                  Text(value, style: text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Distance and compass bearing, with an arrow turned to the bearing.
class _Bearing extends StatelessWidget {
  const _Bearing({required this.distance, required this.bearing, required this.fromWhat});

  final String distance;
  final double bearing;
  final String fromWhat;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final deg = bearing.round() % 360;
    final words = '$distance ${compassPoint(bearing)} of $fromWhat, bearing $deg degrees';
    return Semantics(
      label: 'Distance: $words',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GwSpace.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Transform.rotate(
              angle: bearing * math.pi / 180,
              child: const Icon(Icons.navigation, size: 20, color: GwColors.spectralCyan),
            ),
            const SizedBox(width: GwSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Distance', style: text.labelMedium?.copyWith(color: GwColors.mutedText)),
                  Text('$distance ${compassPoint(bearing)} of $fromWhat (bearing $deg°)', style: text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The signal graph, its summary, and the readings as text.
class _SignalSection extends StatelessWidget {
  const _SignalSection({required this.history, required this.best, required this.now});

  final List<SignalReading> history;
  final int? best;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (history.isEmpty) {
      return const _Fact(
        icon: Icons.signal_cellular_off_outlined,
        label: 'Signal history',
        value: 'No signal readings yet. They come from its beacons and the messages it sends you.',
      );
    }
    final latest = history.last;
    final lo = history.map((r) => r.dbm).reduce(math.min);
    final hi = history.map((r) => r.dbm).reduce(math.max);
    final span = latest.at.difference(history.first.at);
    final summary =
        'Signal history graph: ${history.length} ${history.length == 1 ? 'reading' : 'readings'}'
        '${history.length > 1 ? ' over ${formatUptime(span)}' : ''}, from $lo to $hi dBm. '
        'Latest ${signalText(latest.dbm)}, ${timeAgo(latest.at, now: now)}.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Fact(
          icon: Icons.signal_cellular_alt,
          label: 'Latest',
          value: '${signalText(latest.dbm)} · ${latest.source.label}, ${timeAgo(latest.at, now: now)}',
        ),
        if (best case final b?) _Fact(icon: Icons.star_outline, label: 'Strongest heard', value: signalText(b)),
        const SizedBox(height: GwSpace.sm),
        Semantics(
          label: summary,
          image: true,
          excludeSemantics: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: GwColors.surface1,
              borderRadius: BorderRadius.circular(GwRadius.md),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(GwSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$hi dBm', style: text.labelSmall?.copyWith(color: GwColors.mutedText)),
                  SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: CustomPaint(painter: SignalGraphPainter(history)),
                  ),
                  Text('$lo dBm', style: text.labelSmall?.copyWith(color: GwColors.mutedText)),
                  const SizedBox(height: GwSpace.xs),
                  Wrap(
                    spacing: GwSpace.md,
                    runSpacing: GwSpace.xs,
                    children: [
                      Text(
                        '${clockTime(history.first.at, now: now)} → ${clockTime(latest.at, now: now)}',
                        style: text.labelSmall?.copyWith(color: GwColors.mutedText),
                      ),
                      Text(
                        '● beacon  ■ message  ◆ change',
                        style: text.labelSmall?.copyWith(color: GwColors.mutedText),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('All ${history.length} readings', style: text.bodyMedium),
            children: [
              for (final r in history.reversed)
                MergeSemantics(
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(signalText(r.dbm)),
                    subtitle: Text('${r.source.label} · ${clockTime(r.at, now: now)}'),
                  ),
                ),
            ],
          ),
        ),
        Text(
          'A message can arrive through a relay; its reading is the last hop, not this node.',
          style: text.bodySmall?.copyWith(color: GwColors.mutedText),
        ),
      ],
    );
  }
}

/// Draws signal readings over time: a line, and a mark per reading whose shape
/// says where it came from (circle beacon, square message, diamond change).
class SignalGraphPainter extends CustomPainter {
  /// Creates the painter.
  SignalGraphPainter(this.readings);

  /// Readings, oldest first.
  final List<SignalReading> readings;

  @override
  void paint(Canvas canvas, Size size) {
    if (readings.isEmpty) return;
    final lo = readings.map((r) => r.dbm).reduce(math.min) - 3;
    final hi = readings.map((r) => r.dbm).reduce(math.max) + 3;
    final t0 = readings.first.at.millisecondsSinceEpoch;
    final t1 = readings.last.at.millisecondsSinceEpoch;
    const pad = 6.0;
    Offset at(SignalReading r) {
      final x = t1 == t0
          ? size.width / 2
          : pad + (r.at.millisecondsSinceEpoch - t0) / (t1 - t0) * (size.width - 2 * pad);
      final y = pad + (hi - r.dbm) / (hi - lo) * (size.height - 2 * pad);
      return Offset(x, y);
    }

    final grid = Paint()
      ..color = GwColors.outlineVariant
      ..strokeWidth = 1;
    // band edges (-90 strong, -105 good, -115 fair) where they fall inside
    for (final edge in const [-90, -105, -115]) {
      if (edge <= lo || edge >= hi) continue;
      final y = pad + (hi - edge) / (hi - lo) * (size.height - 2 * pad);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final line = Paint()
      ..color = GwColors.spectralCyan.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(at(readings.first).dx, at(readings.first).dy);
    for (final r in readings.skip(1)) {
      final p = at(r);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = GwColors.spectralCyan;
    for (final r in readings) {
      final p = at(r);
      switch (r.source) {
        case SignalSource.beacon:
          canvas.drawCircle(p, 3.5, dot);
        case SignalSource.message:
          canvas.drawRect(Rect.fromCenter(center: p, width: 7, height: 7), dot);
        case SignalSource.change:
          canvas.drawPath(
            Path()
              ..moveTo(p.dx, p.dy - 4.5)
              ..lineTo(p.dx + 4.5, p.dy)
              ..lineTo(p.dx, p.dy + 4.5)
              ..lineTo(p.dx - 4.5, p.dy)
              ..close(),
            dot,
          );
      }
    }
  }

  @override
  bool shouldRepaint(SignalGraphPainter old) => old.readings != readings;
}

/// Battery and uptime, or why there are none.
class _TelemetrySection extends StatelessWidget {
  const _TelemetrySection({
    required this.reading,
    required this.connected,
    required this.supported,
    required this.asking,
    required this.asked,
    required this.isSelf,
    required this.now,
    required this.onRefresh,
  });

  final NodeTelemetry? reading;
  final bool connected;
  final bool supported;
  final bool asking;
  final bool asked;
  final bool isSelf;
  final DateTime now;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final refresh = Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: asking ? null : () => unawaited(onRefresh()),
        icon: asking
            ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh),
        label: Text(asking ? 'Asking your node…' : 'Ask your node again'),
      ),
    );
    if (r == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Fact(
            icon: Icons.battery_unknown_outlined,
            label: 'Battery and uptime',
            value: !connected
                ? 'Connect to your node to ask it for battery and uptime.'
                : !supported
                ? 'Your node\'s firmware does not pass on telemetry. Update it to see battery and uptime.'
                : asking && !asked
                ? 'Asking your node…'
                : isSelf
                ? 'Your node reports no telemetry.'
                : 'None heard. Telemetry rides on its beacons, so it shows only for nodes your node hears '
                      'directly that run current firmware.',
          ),
          if (supported) refresh,
        ],
      );
    }
    final canAsk = supported;
    final pct = r.batteryPct;
    final mv = r.batteryMv;
    final up = r.uptimeAt(now);
    final battery = pct == null && mv == null
        ? 'Not reported (the board cannot read it)'
        : [if (pct != null) '$pct %', if (mv != null) '${(mv / 1000).toStringAsFixed(2)} V'].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Fact(icon: pct == null ? Icons.battery_unknown_outlined : _batteryIcon(pct), label: 'Battery', value: battery),
        _Fact(
          icon: Icons.timer_outlined,
          label: 'Uptime',
          value: up == null ? 'Not reported' : 'About ${formatUptime(up)} (if it has not restarted since)',
        ),
        _Fact(
          icon: Icons.update,
          label: 'Reported',
          value: isSelf
              ? 'By your node, ${timeAgo(r.heardAt, now: now)}'
              : 'In its beacon ${timeAgo(r.heardAt, now: now)}',
        ),
        if (canAsk) refresh,
      ],
    );
  }

  static IconData _batteryIcon(int pct) => switch (pct) {
    >= 90 => Icons.battery_full,
    >= 60 => Icons.battery_5_bar,
    >= 35 => Icons.battery_3_bar,
    >= 15 => Icons.battery_2_bar,
    _ => Icons.battery_alert,
  };
}
