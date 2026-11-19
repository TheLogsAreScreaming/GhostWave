import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../app/preferences.dart';
import '../link/geo.dart';
import '../map/range_rings.dart';
import 'theme.dart';

/// Range rings and compass spokes around [centre], resized as you zoom so
/// about four rings fit on screen. Ring labels sit on the north spoke.
class RangeRingsLayer extends StatelessWidget {
  /// Creates the layer.
  const RangeRingsLayer({required this.centre, required this.units, super.key});

  /// Where the rings are centred (your position).
  final LatLon centre;

  /// Units for the ring distances.
  final Units units;

  static const _distance = ll.Distance();

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final b = camera.visibleBounds;
    final c = camera.center;
    // the nearer edge of the view, from its middle
    final span = [
      _distance(c, ll.LatLng(b.north, c.longitude)),
      _distance(c, ll.LatLng(c.latitude, b.east)),
    ].reduce((a, v) => a < v ? a : v);
    final radii = ringRadii(span, units);
    if (radii.isEmpty) return const SizedBox.shrink();
    final ink = GwColors.mapMe;
    final here = ll.LatLng(centre.lat, centre.lon);
    final outer = radii.last;
    ll.LatLng at(double bearing, double m) {
      final p = pointAt(centre, bearing, m);
      return ll.LatLng(p.lat, p.lon);
    }

    final style = Theme.of(context).textTheme.labelSmall;
    return ExcludeSemantics(
      child: Stack(
        children: [
          PolylineLayer(
            polylines: [
              for (var deg = 0; deg < 360; deg += 45)
                Polyline(
                  points: [here, at(deg.toDouble(), outer)],
                  color: ink.withValues(alpha: deg % 90 == 0 ? 0.55 : 0.3),
                  strokeWidth: 1,
                ),
            ],
          ),
          CircleLayer(
            circles: [
              for (final r in radii)
                CircleMarker(
                  point: here,
                  radius: r,
                  useRadiusInMeter: true,
                  color: Colors.transparent,
                  borderColor: ink.withValues(alpha: 0.75),
                  borderStrokeWidth: 1.5,
                ),
            ],
          ),
          MarkerLayer(
            markers: [
              for (final r in radii)
                Marker(
                  point: at(0, r),
                  width: 72,
                  height: 22,
                  child: Center(child: _Tag(ringLabel(r, units), style)),
                ),
              for (final (deg, name) in const [(0.0, 'N'), (90.0, 'E'), (180.0, 'S'), (270.0, 'W')])
                Marker(
                  point: at(deg, outer * 1.08),
                  width: 24,
                  height: 22,
                  child: Center(child: _Tag(name, style?.copyWith(fontWeight: FontWeight.w700))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.style);

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: GwColors.card.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Text(text, style: style?.copyWith(color: GwColors.text)),
    ),
  );
}
