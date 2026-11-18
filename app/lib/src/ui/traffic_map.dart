import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../app/traffic.dart';
import '../data/traffic.dart';
import '../link/geo.dart';
import 'theme.dart';

/// The colour of a packet kind, on routes, pills and the legend.
Color trafficColor(TrafficKind k) => switch (k) {
  TrafficKind.advert => GwColors.trafficAdvert,
  TrafficKind.direct => GwColors.trafficDirect,
  TrafficKind.channel => GwColors.trafficChannel,
  TrafficKind.ack => GwColors.trafficAck,
  TrafficKind.trace => GwColors.trafficTrace,
  TrafficKind.other => GwColors.trafficOther,
};

/// How long the glowing dot takes to cross one hop.
const Duration kTrafficLegTime = Duration(milliseconds: 650);

/// How long a route stays on screen, fading, after its dot arrives.
const Duration kTrafficFadeTime = Duration(milliseconds: 3200);

/// Darkens light map tiles for the traffic view on a dark theme: inverts
/// lightness, keeps hue, and dims, so roads and water stay readable.
const ColorFilter kDarkTiles = ColorFilter.matrix(<double>[
  -0.62, -0.25, -0.05, 0, 225, //
  -0.20, -0.66, -0.06, 0, 225, //
  -0.20, -0.25, -0.50, 0, 230, //
  0, 0, 0, 1, 0, //
]);

/// Draws heard packets travelling hop by hop across the map. Goes inside a
/// FlutterMap as a layer. At most three routes animate at once; the rest wait.
class TrafficRoutesLayer extends ConsumerStatefulWidget {
  /// Creates the layer.
  const TrafficRoutesLayer({required this.posOf, required this.nameOf, super.key});

  /// A node's position, or null when it has none.
  final LatLon? Function(int node) posOf;

  /// A node's display name.
  final String Function(int node) nameOf;

  @override
  ConsumerState<TrafficRoutesLayer> createState() => _TrafficRoutesLayerState();
}

class _TrafficRoutesLayerState extends ConsumerState<TrafficRoutesLayer> with SingleTickerProviderStateMixin {
  final TrafficQueue _queue = TrafficQueue();
  final Map<TrafficRoute, Duration> _started = {};
  final ValueNotifier<Duration> _clock = ValueNotifier(Duration.zero);
  late final Ticker _ticker = createTicker(_tick);

  Duration _total(TrafficRoute r, bool reduce) =>
      (reduce ? Duration.zero : kTrafficLegTime * r.legs) + kTrafficFadeTime;

  void _tick(Duration now) {
    _clock.value = now;
    final reduce = MediaQuery.disableAnimationsOf(context);
    var changed = false;
    for (final r in _queue.active) {
      final start = _started[r] ?? now;
      if (now - start >= _total(r, reduce)) {
        changed = true;
        _started.remove(r);
        final next = _queue.finish(r);
        if (next != null) _started[next] = now;
      }
    }
    if (_queue.active.isEmpty) _ticker.stop();
    if (changed) setState(() {});
  }

  void _enqueue(TrafficPacket p) {
    final r = buildRoute(p, widget.posOf);
    if (r.points.isEmpty) return; // nothing of it is on the map
    if (!_ticker.isActive) {
      _clock.value = Duration.zero;
      _started.updateAll((_, _) => Duration.zero);
      unawaited(_ticker.start());
    }
    setState(() {
      if (_queue.add(r)) _started[r] = _clock.value;
    });
  }

  @override
  void initState() {
    super.initState();
    // a packet heard as the layer appears (traffic just switched on) still plays
    final latest = ref.read(trafficProvider).latest;
    if (latest != null && DateTime.now().difference(latest.at) < kTrafficFadeTime) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enqueue(latest);
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(trafficProvider, (prev, next) {
      if (!next.on) {
        setState(() {
          _queue.clear();
          _started.clear();
        });
        return;
      }
      if (next.serial != (prev?.serial ?? 0) && next.latest != null) _enqueue(next.latest!);
    });
    final camera = MapCamera.of(context);
    final labels = ref.watch(trafficProvider.select((s) => s.hopLabels));
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _RoutesPainter(
            camera: camera,
            clock: _clock,
            routes: _queue.active,
            started: Map.of(_started),
            reduceMotion: MediaQuery.disableAnimationsOf(context),
            labels: labels,
            nameOf: widget.nameOf,
            textStyle: Theme.of(context).textTheme.labelSmall ?? const TextStyle(fontSize: 11),
          ),
        ),
      ),
    );
  }
}

class _RoutesPainter extends CustomPainter {
  _RoutesPainter({
    required this.camera,
    required this.clock,
    required this.routes,
    required this.started,
    required this.reduceMotion,
    required this.labels,
    required this.nameOf,
    required this.textStyle,
  }) : super(repaint: clock);

  final MapCamera camera;
  final ValueNotifier<Duration> clock;
  final List<TrafficRoute> routes;
  final Map<TrafficRoute, Duration> started;
  final bool reduceMotion;
  final bool labels;
  final String Function(int) nameOf;
  final TextStyle textStyle;

  Offset _at(LatLon p) => camera.latLngToScreenOffset(ll.LatLng(p.lat, p.lon));

  @override
  void paint(Canvas canvas, Size size) {
    final now = clock.value;
    for (final r in routes) {
      final start = started[r];
      if (start == null) continue;
      _paintRoute(canvas, r, now - start);
    }
  }

  void _paintRoute(Canvas canvas, TrafficRoute r, Duration elapsed) {
    final color = trafficColor(r.packet.kind);
    final pts = [for (final p in r.points) _at(p.pos)];
    final legMs = kTrafficLegTime.inMilliseconds;
    final travelMs = reduceMotion ? 0 : legMs * r.legs;
    final ms = elapsed.inMilliseconds;
    final fade = ms <= travelMs ? 1.0 : (1 - (ms - travelMs) / kTrafficFadeTime.inMilliseconds).clamp(0.0, 1.0);
    if (fade <= 0) return;

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 9
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final inFlight = ms < travelMs ? ms ~/ legMs : r.legs;
    final frac = ms < travelMs ? (ms % legMs) / legMs : 1.0;
    for (var i = 0; i < r.legs; i++) {
      final a = pts[i], b = pts[i + 1];
      if (i < inFlight) {
        // passed: a solid line, fading
        _solid(canvas, a, b, color, fade * 0.85, line, glow);
      } else if (i == inFlight) {
        final tip = Offset.lerp(a, b, frac)!;
        _solid(canvas, a, tip, color, fade, line, glow);
        _dotted(canvas, tip, b, color.withValues(alpha: 0.55 * fade));
        _dot(canvas, tip, color);
      } else {
        // ahead: dotted
        _dotted(canvas, a, b, color.withValues(alpha: 0.55 * fade));
      }
    }

    // a soft ring at the sender while the packet travels, and at the last hop
    // when it arrives
    final ringT = (ms % 1200) / 1200;
    if (ms < travelMs || r.legs == 0) _ring(canvas, pts.first, color, ringT, fade);
    if (r.legs > 0 && ms >= travelMs) _ring(canvas, pts.last, color, ((ms - travelMs) % 1200) / 1200, fade);

    if (labels) {
      for (var i = 0; i < pts.length; i++) {
        _label(canvas, pts[i], nameOf(r.points[i].node), fade);
      }
    }
  }

  void _solid(Canvas c, Offset a, Offset b, Color color, double alpha, Paint line, Paint glow) {
    c.drawLine(a, b, glow..color = color.withValues(alpha: 0.35 * alpha));
    c.drawLine(a, b, line..color = color.withValues(alpha: alpha));
  }

  void _dotted(Canvas c, Offset a, Offset b, Color color) {
    final d = b - a;
    final len = d.distance;
    if (len < 1) return;
    final dir = d / len;
    final p = Paint()..color = color;
    for (var t = 0.0; t < len; t += 9) {
      c.drawCircle(a + dir * t, 1.6, p);
    }
  }

  void _dot(Canvas c, Offset at, Color color) {
    c.drawCircle(
      at,
      11,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    c.drawCircle(at, 5, Paint()..color = Colors.white);
    c.drawCircle(at, 3.5, Paint()..color = color);
  }

  void _ring(Canvas c, Offset at, Color color, double t, double alpha) {
    final radius = 12 + 22 * t;
    c.drawCircle(
      at,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color.withValues(alpha: (1 - t) * 0.7 * alpha),
    );
  }

  void _label(Canvas c, Offset at, String text, double alpha) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.copyWith(
          color: Colors.white.withValues(alpha: alpha),
          shadows: [Shadow(color: Colors.black.withValues(alpha: alpha), blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 120);
    tp.paint(c, at + const Offset(14, -22));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_RoutesPainter old) =>
      old.camera != camera ||
      old.routes.length != routes.length ||
      old.labels != labels ||
      old.reduceMotion != reduceMotion ||
      !_sameRoutes(old.routes, routes);

  static bool _sameRoutes(List<TrafficRoute> a, List<TrafficRoute> b) {
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}

/// A frosted-glass panel: blurred map behind, a translucent surface on top.
class FrostedPanel extends StatelessWidget {
  /// Creates a panel.
  const FrostedPanel({required this.child, this.radius = GwRadius.lg, this.padding, super.key});

  /// What it holds.
  final Widget child;

  /// Corner radius.
  final double radius;

  /// Inner padding.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.12)),
          ),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}

/// The six packet kinds with their colours.
class TrafficLegend extends StatelessWidget {
  /// Creates the legend.
  const TrafficLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Semantics(
      container: true,
      label: 'Traffic colours',
      child: Wrap(
        spacing: GwSpace.md,
        runSpacing: GwSpace.xs,
        children: [
          for (final k in TrafficKind.values)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 14,
                    height: 4,
                    decoration: BoxDecoration(
                      color: trafficColor(k),
                      borderRadius: BorderRadius.circular(GwRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(k.label, style: style),
              ],
            ),
        ],
      ),
    );
  }
}

/// A packet kind as a small coloured pill.
class TrafficKindPill extends StatelessWidget {
  /// Creates the pill.
  const TrafficKindPill(this.kind, {super.key});

  /// The kind.
  final TrafficKind kind;

  @override
  Widget build(BuildContext context) {
    final color = trafficColor(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(GwRadius.pill),
      ),
      child: Text(kind.label, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

/// The card at the bottom of the traffic view: the latest packet's route,
/// kind, signal and hops off the map, then the colour legend.
class TrafficRouteCard extends ConsumerWidget {
  /// Creates the card.
  const TrafficRouteCard({required this.posOf, required this.nameOf, required this.now, super.key});

  /// A node's position, or null when it has none.
  final LatLon? Function(int node) posOf;

  /// A node's display name.
  final String Function(int node) nameOf;

  /// The current time, for the packet's age.
  final DateTime Function() now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traffic = ref.watch(trafficProvider);
    final p = traffic.latest;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final route = p == null ? null : buildRoute(p, posOf);
    return FrostedPanel(
      padding: const EdgeInsets.fromLTRB(GwSpace.md, GwSpace.sm, GwSpace.md, GwSpace.sm),
      child: InkWell(
        onTap: traffic.recent.isEmpty ? null : () => showTrafficLog(context, nameOf: nameOf, posOf: posOf, now: now),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p == null || route == null)
              Padding(
                padding: const EdgeInsets.only(bottom: GwSpace.sm),
                child: Text('Listening for traffic. Packets your node hears show here.', style: text.bodyMedium),
              )
            else ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(routeText(p, nameOf), style: text.titleSmall, maxLines: 1),
              ),
              const SizedBox(height: GwSpace.xs),
              Row(
                children: [
                  TrafficKindPill(p.kind),
                  const SizedBox(width: GwSpace.sm),
                  Expanded(child: Text(heardText(p, nameOf), style: muted)),
                ],
              ),
              const SizedBox(height: GwSpace.xs),
              Text(detailText(route, now()), style: muted),
              if (route.offMap.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_off_outlined, size: 14, color: muted?.color),
                      const SizedBox(width: 4),
                      Expanded(child: Text('Not on map: ${route.offMap.map(nameOf).join(', ')}', style: muted)),
                    ],
                  ),
                ),
              const SizedBox(height: GwSpace.sm),
            ],
            const TrafficLegend(),
          ],
        ),
      ),
    );
  }
}

/// Lists the packets heard lately, newest first.
Future<void> showTrafficLog(
  BuildContext context, {
  required String Function(int) nameOf,
  required LatLon? Function(int) posOf,
  required DateTime Function() now,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => Consumer(
    builder: (context, ref, _) {
      final recent = ref.watch(trafficProvider).recent;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        builder: (context, scroll) => ListView(
          controller: scroll,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: GwSpace.lg),
              child: Text('Heard lately', style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final p in recent)
              ListTile(
                leading: Icon(Icons.circle, size: 14, color: trafficColor(p.kind)),
                title: Text(routeText(p, nameOf)),
                subtitle: Text('${p.kind.label} · ${heardText(p, nameOf)}\n${detailText(buildRoute(p, posOf), now())}'),
                isThreeLine: true,
              ),
          ],
        ),
      );
    },
  ),
);

/// One button of the map toolbar: an icon over a short label.
class MapToolButton extends StatelessWidget {
  /// Creates a button.
  const MapToolButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  /// The icon.
  final IconData icon;

  /// The short label under it.
  final String label;

  /// What it does, for the tooltip and screen readers.
  final String tooltip;

  /// What tapping does.
  final VoidCallback? onPressed;

  /// Whether it shows a mode that is on.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        toggled: selected ? true : null,
        label: tooltip,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(GwRadius.md),
          onTap: onPressed,
          child: SizedBox(
            width: 60,
            height: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The vertical frosted pill of map controls on the right.
class MapToolbar extends StatelessWidget {
  /// Creates the toolbar.
  const MapToolbar({required this.children, super.key});

  /// The buttons, top to bottom.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => FrostedPanel(
    radius: 30,
    padding: const EdgeInsets.symmetric(vertical: GwSpace.xs),
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );
}

/// A heard node as the traffic view draws it: a tower in a rounded square,
/// ringed green when heard in the last [kHeardRecently].
class TrafficNodePin extends StatelessWidget {
  /// Creates a pin.
  const TrafficNodePin({required this.color, required this.heardRecently, this.icon = Icons.cell_tower, super.key});

  /// The square's fill.
  final Color color;

  /// Whether to ring it green.
  final bool heardRecently;

  /// What it shows.
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(GwRadius.sm),
      border: Border.all(color: heardRecently ? GwColors.trafficHeard : Colors.white70, width: heardRecently ? 3 : 1.5),
      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
    ),
    child: Icon(icon, size: 20, color: Colors.white),
  );
}

/// How recently a node must be heard for its pin to get the green ring.
const Duration kHeardRecently = Duration(minutes: 15);

/// Whether a node last heard at [seen] counts as heard recently at [now].
bool heardRecently(DateTime? seen, DateTime now) => seen != null && now.difference(seen) <= kHeardRecently;
