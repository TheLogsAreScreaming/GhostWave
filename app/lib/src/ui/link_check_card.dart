/// The link check card: who checked whom, when, how long the answer took,
/// the signal on every hop, and the path drawn on a small map. Shareable as
/// an image or as text.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../app/preferences.dart';
import '../app/providers.dart';
import '../app/share_gateway.dart';
import '../data/link_check.dart';
import '../link/contact_card.dart';
import '../link/geo.dart';
import '../link/node_link.dart';
import 'format.dart';
import 'theme.dart';

/// `yyyy-mm-dd HH:mm`, always with the date: a shared card outlives the day.
String linkCheckTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// "1.4 s".
String elapsedText(Duration d) => '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

String _who(LinkCheckNode n) => n.name == nodeIdHex(n.nodeId) ? n.name : '${n.name} (${nodeIdHex(n.nodeId)})';

/// What was measured on hop [i], in words; never guesses a missing reading.
List<String> hopLines(LinkCheck c, int i) {
  final a = c.nodes[i];
  final b = c.nodes[i + 1];
  final h = c.hops[i];
  return [
    if (h.forwardDbm case final f?) '${b.name} heard ${a.name} at ${signalText(f)}',
    if (h.reverseDbm case final r?) '${a.name} heard ${b.name} at ${signalText(r)}',
    if (h.forwardDbm == null && h.reverseDbm == null) '${a.name} to ${b.name}: not measured',
  ];
}

/// The headline result.
String linkCheckResult(LinkCheck c) {
  if (!c.answered) return 'No answer within 10 seconds';
  final hops = c.hops.length == 1 ? 'one hop' : '${c.hops.length} hops';
  return c.elapsed == null ? 'Answered, $hops' : 'Answered in ${elapsedText(c.elapsed!)}, $hops';
}

/// The distance line, or null when a position is missing.
String? linkCheckDistance(LinkCheck c, Units units) {
  final d = c.totalDistanceM;
  if (d == null) return null;
  final first = c.origin.pos!;
  final last = c.target.pos!;
  final bearing = c.nodes.length == 2 ? ', ${compassPoint(first.bearingTo(last))}' : '';
  return '${formatDistance(d, units)}$bearing (straight line between last known positions)';
}

/// The whole card as plain text, for sharing.
String linkCheckText(LinkCheck c, Units units) => [
  'GhostWave ${c.kind.toLowerCase()} · ${linkCheckTime(c.at)}',
  'From: ${_who(c.origin)}',
  'To: ${_who(c.target)}',
  linkCheckResult(c),
  if (c.answered)
    for (var i = 0; i < c.hops.length; i++)
      for (final l in hopLines(c, i)) c.hops.length == 1 ? l : 'Hop ${i + 1}: $l',
  ?linkCheckDistance(c, units),
].join('\n');

/// Builds the card's data from a link ping [o] run by the connected node.
LinkCheck linkCheckFromPing(MeshState mesh, LinkState link, LinkPingOutcome o, DateTime at) {
  final ownId = mesh.nodeId ?? (link is LinkUp ? link.info.nodeId : 0);
  final ownName = link is LinkUp ? decodeLenient(link.info.name) : '';
  LatLon? posOf(int id) => mesh.contacts[id]?.pos ?? mesh.neighbors[id]?.pos ?? mesh.journal.entries[id]?.lastPos;
  return LinkCheck.linkPing(
    origin: LinkCheckNode(nodeId: ownId, name: ownName.isEmpty ? nodeIdHex(ownId) : ownName, pos: mesh.ownPos),
    target: LinkCheckNode(nodeId: o.node, name: mesh.nameOf(o.node), pos: posOf(o.node)),
    at: at,
    answered: o.answered,
    forwardDbm: o.forwardDbm,
    reverseDbm: o.reverseDbm,
    elapsed: o.elapsed,
  );
}

/// One sentence describing the path map, for screen readers.
String pathMapDescription(LinkCheck c, Units units) {
  final names = [for (final n in c.nodes) n.name].join(' to ');
  final placed = c.placed.length;
  if (placed < 2) return 'Path diagram: $names. Positions not known, drawn in a straight line.';
  return 'Path map: $names. ${linkCheckDistance(c, units) ?? '$placed of ${c.nodes.length} nodes have a position.'}';
}

/// The card itself. Wrap it in a [RepaintBoundary] to capture it as an image.
class LinkCheckCard extends ConsumerWidget {
  /// Creates the card.
  const LinkCheckCard({required this.check, super.key});

  /// The result shown.
  final LinkCheck check;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitsProvider);
    final c = check;
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final distance = linkCheckDistance(c, units);
    return Card(
      margin: EdgeInsets.zero,
      // each line reads on its own: header, result, every hop, the map
      semanticContainer: false,
      child: Padding(
        padding: const EdgeInsets.all(GwSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows),
                const SizedBox(width: GwSpace.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('GhostWave ${c.kind.toLowerCase()}', style: text.titleMedium),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GwSpace.xs),
            Text(linkCheckTime(c.at), style: GwText.mono.merge(text.bodySmall)),
            const SizedBox(height: GwSpace.sm),
            Text('From ${_who(c.origin)}', style: text.bodyMedium),
            Text('To ${_who(c.target)}', style: text.bodyMedium),
            const SizedBox(height: GwSpace.sm),
            Row(
              children: [
                Icon(c.answered ? Icons.check_circle_outline : Icons.highlight_off, size: 20),
                const SizedBox(width: GwSpace.xs),
                Expanded(child: Text(linkCheckResult(c), style: text.titleSmall)),
              ],
            ),
            if (c.answered)
              for (var i = 0; i < c.hops.length; i++)
                for (final l in hopLines(c, i))
                  Padding(
                    padding: const EdgeInsets.only(top: GwSpace.xs),
                    child: Text(c.hops.length == 1 ? l : 'Hop ${i + 1}: $l'),
                  ),
            const SizedBox(height: GwSpace.sm),
            Semantics(
              label: pathMapDescription(c, units),
              image: true,
              child: ExcludeSemantics(
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(GwRadius.sm),
                    child: CustomPaint(
                      painter: PathMapPainter(
                        PathMapScene.of(c, units),
                        PathMapColors(
                          background: theme.colorScheme.surfaceContainerHighest,
                          grid: theme.colorScheme.outlineVariant,
                          line: theme.colorScheme.primary,
                          node: theme.colorScheme.onSurface,
                          text: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (distance != null) ...[const SizedBox(height: GwSpace.xs), Text(distance, style: text.bodySmall)],
          ],
        ),
      ),
    );
  }
}

/// Colours for [PathMapPainter].
@immutable
class PathMapColors {
  /// Creates the set.
  const PathMapColors({
    required this.background,
    required this.grid,
    required this.line,
    required this.node,
    required this.text,
  });

  /// Fill.
  final Color background;

  /// Grid lines.
  final Color grid;

  /// Hop lines.
  final Color line;

  /// Node dots.
  final Color node;

  /// Labels.
  final Color text;

  @override
  bool operator ==(Object other) =>
      other is PathMapColors &&
      other.background == background &&
      other.grid == grid &&
      other.line == line &&
      other.node == node &&
      other.text == text;

  @override
  int get hashCode => Object.hash(background, grid, line, node, text);
}

/// What the path map draws: each node at a point in the unit square, and
/// whether it was placed by position (true) or laid out in a line (false).
@immutable
class PathMapScene {
  /// Creates a scene.
  const PathMapScene({
    required this.points,
    required this.labels,
    required this.geographic,
    this.metresPerUnit = 0,
    this.units = Units.metric,
  });

  /// Lays out [c]: by position when at least two nodes have one, else in a line.
  factory PathMapScene.of(LinkCheck c, Units units) {
    final labels = [for (final n in c.nodes) n.name];
    final placed = c.placed;
    if (placed.length < 2) {
      final n = c.nodes.length;
      return PathMapScene(
        points: [for (var i = 0; i < n; i++) Offset(0.1 + 0.8 * i / (n - 1), 0.5)],
        labels: labels,
        geographic: false,
      );
    }
    // equirectangular around the mean latitude: fine at link-check distances
    final meanLat = placed.map((n) => n.pos!.lat).reduce((a, b) => a + b) / placed.length;
    final k = math.cos(meanLat * math.pi / 180);
    Offset project(LatLon p) => Offset(p.lon * k, -p.lat);
    final raw = [for (final n in placed) project(n.pos!)];
    final minX = raw.map((o) => o.dx).reduce(math.min);
    final maxX = raw.map((o) => o.dx).reduce(math.max);
    final minY = raw.map((o) => o.dy).reduce(math.min);
    final maxY = raw.map((o) => o.dy).reduce(math.max);
    final span = math.max(math.max(maxX - minX, maxY - minY), 1e-9);
    Offset unit(LatLon p) {
      final o = project(p);
      return Offset(0.5 + (o.dx - (minX + maxX) / 2) / span * 0.7, 0.5 + (o.dy - (minY + maxY) / 2) / span * 0.7);
    }

    // a node with no position sits halfway between its neighbours on the path
    final points = <Offset?>[for (final n in c.nodes) n.pos == null ? null : unit(n.pos!)];
    for (var i = 0; i < points.length; i++) {
      if (points[i] != null) continue;
      final before = points.take(i).lastWhere((p) => p != null, orElse: () => null);
      final after = points.skip(i + 1).firstWhere((p) => p != null, orElse: () => null);
      points[i] = before != null && after != null ? Offset.lerp(before, after, 0.5) : (before ?? after);
    }
    return PathMapScene(
      points: [for (final p in points) p!],
      labels: labels,
      geographic: true,
      metresPerUnit: span * math.pi / 180 * 6371008.8 / 0.7,
      units: units,
    );
  }

  /// Node positions, 0..1 in both axes, path order.
  final List<Offset> points;

  /// Node names, path order.
  final List<String> labels;

  /// Whether [points] come from real positions.
  final bool geographic;

  /// Ground distance of one unit (the shorter side of the map), when geographic.
  final double metresPerUnit;

  /// Units for the scale label.
  final Units units;

  @override
  bool operator ==(Object other) =>
      other is PathMapScene &&
      other.geographic == geographic &&
      other.metresPerUnit == metresPerUnit &&
      other.units == units &&
      _listEq(other.points, points) &&
      _listEq(other.labels, labels);

  @override
  int get hashCode => Object.hash(geographic, metresPerUnit, units, Object.hashAll(points), Object.hashAll(labels));
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Draws a [PathMapScene]: grid, hop lines, numbered nodes, names, north mark.
class PathMapPainter extends CustomPainter {
  /// Creates the painter.
  const PathMapPainter(this.scene, this.colors);

  /// What to draw.
  final PathMapScene scene;

  /// How to colour it.
  final PathMapColors colors;

  void _text(Canvas canvas, String s, Offset at, double maxWidth, {double size = 12, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(color: colors.text, fontSize: size, fontFamily: GwFonts.mono),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, maxWidth));
    tp.paint(canvas, center ? at - Offset(tp.width / 2, 0) : at);
    tp.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.background);
    final grid = Paint()
      ..color = colors.grid
      ..strokeWidth = 1;
    if (scene.geographic) {
      for (var i = 1; i < 6; i++) {
        final x = size.width * i / 6;
        final y = size.height * i / 6;
        canvas
          ..drawLine(Offset(x, 0), Offset(x, size.height), grid)
          ..drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
      // north mark, top right
      final n = Offset(size.width - 16, 10);
      final arrow = Path()
        ..moveTo(n.dx, n.dy)
        ..lineTo(n.dx - 5, n.dy + 12)
        ..lineTo(n.dx + 5, n.dy + 12)
        ..close();
      canvas.drawPath(arrow, Paint()..color = colors.node);
      _text(canvas, 'N', n + const Offset(0, 13), 20, size: 10, center: true);
    }
    // geographic: one scale on both axes, the unit square on the shorter side
    final side = math.min(size.width, size.height);
    final centre = size.center(Offset.zero);
    final pts = [
      for (final p in scene.points)
        scene.geographic ? centre + (p - const Offset(0.5, 0.5)) * side : Offset(p.dx * size.width, p.dy * size.height),
    ];
    if (scene.geographic && scene.metresPerUnit > 0) {
      final across = formatDistance(scene.metresPerUnit * size.width / side, scene.units);
      _text(canvas, 'map width ≈ $across', Offset(6, size.height - 18), size.width - 12, size: 10);
    }
    final line = Paint()
      ..color = colors.line
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i + 1 < pts.length; i++) {
      canvas.drawLine(pts[i], pts[i + 1], line);
    }
    final dot = Paint()..color = colors.node;
    final ring = Paint()
      ..color = colors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < pts.length; i++) {
      canvas
        ..drawCircle(pts[i], 7, dot)
        ..drawCircle(pts[i], 7, ring);
      final below = pts[i].dy < size.height - 30;
      _text(
        canvas,
        '${i + 1} ${scene.labels[i]}',
        pts[i] + Offset(0, below ? 10 : -26),
        size.width / math.max(2, pts.length) + 40,
        center: true,
      );
    }
  }

  @override
  bool shouldRepaint(PathMapPainter old) => old.scene != scene || old.colors != colors;
}

/// The card with share and copy buttons.
class LinkCheckScreen extends ConsumerStatefulWidget {
  /// Creates the screen for [check].
  const LinkCheckScreen({required this.check, super.key});

  /// The result.
  final LinkCheck check;

  @override
  ConsumerState<LinkCheckScreen> createState() => _LinkCheckScreenState();
}

class _LinkCheckScreenState extends ConsumerState<LinkCheckScreen> {
  final _card = GlobalKey();
  bool _busy = false;

  Rect? _origin(BuildContext context) {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  }

  String get _fileName {
    final t = widget.check.at;
    String two(int v) => v.toString().padLeft(2, '0');
    return 'ghostwave-link-check-${nodeIdHex(widget.check.target.nodeId)}-'
        '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}.png';
  }

  Future<void> _shareImage(BuildContext button) async {
    final origin = _origin(button);
    final text = linkCheckText(widget.check, ref.read(unitsProvider));
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('no image data');
      await ref
          .read(shareGatewayProvider)
          .shareImage(
            data.buffer.asUint8List(),
            _fileName,
            text: text,
            subject: 'GhostWave link check',
            origin: origin,
          );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not share the image: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareText(BuildContext button) async {
    final origin = _origin(button);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(shareGatewayProvider)
          .shareText(
            linkCheckText(widget.check, ref.read(unitsProvider)),
            subject: 'GhostWave link check',
            origin: origin,
          );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not share: $e')));
    }
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: linkCheckText(widget.check, ref.read(unitsProvider))));
    messenger.showSnackBar(const SnackBar(content: Text('Copied the result as text')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Link check'),
      actions: [IconButton(tooltip: 'Copy as text', onPressed: () => unawaited(_copy()), icon: const Icon(Icons.copy))],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(GwSpace.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RepaintBoundary(
                key: _card,
                child: LinkCheckCard(check: widget.check),
              ),
              const SizedBox(height: GwSpace.md),
              Text(
                'Positions are the last ones this app heard, not measured during the check. '
                'Sharing hands the card to an app you pick; GhostWave sends nothing itself.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: GwSpace.md),
              Wrap(
                spacing: GwSpace.sm,
                runSpacing: GwSpace.sm,
                children: [
                  Builder(
                    builder: (b) => FilledButton.icon(
                      onPressed: _busy ? null : () => unawaited(_shareImage(b)),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Share image'),
                    ),
                  ),
                  Builder(
                    builder: (b) => OutlinedButton.icon(
                      onPressed: () => unawaited(_shareText(b)),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share text'),
                    ),
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

/// Opens the card for a finished link ping [o].
Future<void> openLinkCheckCard(BuildContext context, WidgetRef ref, LinkPingOutcome o) {
  final check = linkCheckFromPing(
    ref.read(meshProvider),
    ref.read(nodeLinkProvider).state,
    o,
    ref.read(clockProvider)(),
  );
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LinkCheckScreen(check: check)));
}
