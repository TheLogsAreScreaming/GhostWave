/// A small generated picture per node ID: broken rings around a core shape,
/// in colours picked from the ID. The same ID always draws the same mark, on
/// every phone, so a node can be recognised at a glance before it has a name.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The core shape at the centre of a mark.
enum MarkCore {
  /// A filled dot.
  dot,

  /// A diamond.
  diamond,

  /// A triangle.
  triangle,

  /// A square with soft corners.
  square,

  /// A hollow ring.
  hollow,
}

/// One ring of arcs around the core.
class MarkRing {
  /// Creates a ring.
  const MarkRing({required this.arcs, required this.gap, required this.turn});

  /// How many arcs the ring is broken into (1 to 4).
  final int arcs;

  /// Fraction of each arc's slot left empty (0.08 to 0.5).
  final double gap;

  /// Rotation of the first arc, in turns (0 to 1).
  final double turn;

  @override
  bool operator ==(Object other) => other is MarkRing && other.arcs == arcs && other.gap == gap && other.turn == turn;

  @override
  int get hashCode => Object.hash(arcs, gap, turn);

  @override
  String toString() => 'MarkRing($arcs, gap ${gap.toStringAsFixed(2)}, turn ${turn.toStringAsFixed(3)})';
}

/// Everything needed to draw a node's mark; a pure function of the node ID.
class NodeMarkSpec {
  /// Creates a spec.
  const NodeMarkSpec({
    required this.hue,
    required this.accentHue,
    required this.rings,
    required this.core,
    required this.coreTurn,
    required this.moonTurn,
  });

  /// The spec for [nodeId].
  factory NodeMarkSpec.forNode(int nodeId) {
    final bits = _Bits(nodeId);
    final hue = bits.take(360);
    // the accent sits across the colour wheel, a third to two thirds away
    final accentHue = (hue + 120 + bits.take(121)) % 360;
    final ringCount = 2 + bits.take(2);
    final rings = [
      for (var i = 0; i < ringCount; i++)
        MarkRing(arcs: 1 + bits.take(4), gap: 0.08 + bits.take(43) / 100, turn: bits.take(1000) / 1000),
    ];
    return NodeMarkSpec(
      hue: hue,
      accentHue: accentHue,
      rings: rings,
      core: MarkCore.values[bits.take(MarkCore.values.length)],
      coreTurn: bits.take(1000) / 1000,
      moonTurn: bits.take(1000) / 1000,
    );
  }

  /// Main colour's hue, degrees.
  final int hue;

  /// Accent colour's hue, degrees.
  final int accentHue;

  /// Rings, innermost first (2 or 3).
  final List<MarkRing> rings;

  /// The centre shape.
  final MarkCore core;

  /// Rotation of the centre shape, in turns.
  final double coreTurn;

  /// Where the small accent dot sits on the outer ring, in turns.
  final double moonTurn;

  /// Main colour: light enough to read on the app's dark surfaces.
  Color get color => HSLColor.fromAHSL(1, hue.toDouble(), 0.78, 0.66).toColor();

  /// Accent colour.
  Color get accent => HSLColor.fromAHSL(1, accentHue.toDouble(), 0.82, 0.72).toColor();

  @override
  bool operator ==(Object other) =>
      other is NodeMarkSpec &&
      other.hue == hue &&
      other.accentHue == accentHue &&
      other.core == core &&
      other.coreTurn == coreTurn &&
      other.moonTurn == moonTurn &&
      other.rings.length == rings.length &&
      [for (var i = 0; i < rings.length; i++) other.rings[i] == rings[i]].every((x) => x);

  @override
  int get hashCode => Object.hash(hue, accentHue, core, coreTurn, moonTurn, Object.hashAll(rings));

  @override
  String toString() => 'NodeMarkSpec(hue $hue, accent $accentHue, ${core.name}, $rings)';
}

/// A deterministic stream of small numbers from a node ID (32-bit integer
/// mixing, the same on every platform).
class _Bits {
  _Bits(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;
  int _pool = 0;
  int _left = 0;

  static int _mix(int x) {
    var h = x & 0xFFFFFFFF;
    h ^= h >> 16;
    h = (h * 0x7FEB352D) & 0xFFFFFFFF;
    h ^= h >> 15;
    h = (h * 0x846CA68B) & 0xFFFFFFFF;
    h ^= h >> 16;
    return h;
  }

  /// A number in 0 ..< [n] (n at most 1024).
  int take(int n) {
    if (_left < 10) {
      _state = (_state + 0x9E3779B9) & 0xFFFFFFFF;
      _pool = _mix(_state);
      _left = 32;
    }
    final v = _pool & 0x3FF;
    _pool >>= 10;
    _left -= 10;
    return v * n >> 10;
  }
}

/// Draws [nodeId]'s mark in a circle [size] across. Decorative by default;
/// give [semanticLabel] when nothing next to it names the node.
class NodeMark extends StatelessWidget {
  /// Creates the mark.
  const NodeMark({required this.nodeId, this.size = 44, this.semanticLabel, super.key});

  /// The node.
  final int nodeId;

  /// Diameter, logical px.
  final double size;

  /// Spoken description, or null to hide the picture from screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: NodeMarkPainter(NodeMarkSpec.forNode(nodeId))),
    );
    final label = semanticLabel;
    return label == null
        ? ExcludeSemantics(child: mark)
        : Semantics(container: true, label: label, image: true, excludeSemantics: true, child: mark);
  }
}

/// Paints a [NodeMarkSpec].
class NodeMarkPainter extends CustomPainter {
  /// Creates the painter.
  NodeMarkPainter(this.spec);

  /// What to draw.
  final NodeMarkSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, r, Paint()..color = GwColors.surface2);
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = spec.color.withValues(alpha: 0.35),
    );

    final stroke = math.max(1.5, r * 0.11);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final n = spec.rings.length;
    final outer = r * 0.80;
    final inner = r * 0.40;
    for (var i = 0; i < n; i++) {
      final ring = spec.rings[i];
      final radius = n == 1 ? outer : inner + (outer - inner) * i / (n - 1);
      arc.color = i.isEven ? spec.color : spec.accent;
      final slot = 2 * math.pi / ring.arcs;
      final sweep = slot * (1 - ring.gap);
      for (var k = 0; k < ring.arcs; k++) {
        final start = ring.turn * 2 * math.pi + k * slot - math.pi / 2;
        canvas.drawArc(Rect.fromCircle(center: c, radius: radius), start, sweep, false, arc);
      }
    }

    // accent dot riding the outer ring
    final moon = spec.moonTurn * 2 * math.pi - math.pi / 2;
    canvas.drawCircle(
      c + Offset(math.cos(moon), math.sin(moon)) * outer,
      stroke * 0.95,
      Paint()..color = GwColors.mistWhite,
    );

    final core = r * 0.22;
    final fill = Paint()..color = spec.color;
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(spec.coreTurn * 2 * math.pi);
    switch (spec.core) {
      case MarkCore.dot:
        canvas.drawCircle(Offset.zero, core * 0.8, fill);
      case MarkCore.diamond:
        canvas.drawPath(
          Path()
            ..moveTo(0, -core)
            ..lineTo(core * 0.75, 0)
            ..lineTo(0, core)
            ..lineTo(-core * 0.75, 0)
            ..close(),
          fill,
        );
      case MarkCore.triangle:
        canvas.drawPath(
          Path()
            ..moveTo(0, -core)
            ..lineTo(core * 0.87, core * 0.5)
            ..lineTo(-core * 0.87, core * 0.5)
            ..close(),
          fill,
        );
      case MarkCore.square:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCircle(center: Offset.zero, radius: core * 0.7),
            Radius.circular(core * 0.2),
          ),
          fill,
        );
      case MarkCore.hollow:
        canvas.drawCircle(
          Offset.zero,
          core * 0.7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * 0.8
            ..color = spec.accent,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(NodeMarkPainter oldDelegate) => oldDelegate.spec != spec;
}
