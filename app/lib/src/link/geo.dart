/// Positions on the wire are `sint32` in 1e-7 degrees.
library;

import 'dart:math' as math;

import '../gen/ghostwave.pb.dart' as pb;

/// A plain latitude/longitude pair in degrees.
class LatLon {
  /// Creates a position.
  const LatLon(this.lat, this.lon);

  /// From a wire [pb.Position].
  factory LatLon.fromProto(pb.Position p) => LatLon(p.latE7 / 1e7, p.lonE7 / 1e7);

  /// From JSON written by [toJson].
  factory LatLon.fromJson(Map<String, Object?> j) =>
      LatLon((j['lat']! as num).toDouble(), (j['lon']! as num).toDouble());

  /// Latitude, degrees.
  final double lat;

  /// Longitude, degrees.
  final double lon;

  /// To a wire [pb.Position] (rounded to 1e-7°).
  pb.Position toProto() => pb.Position(latE7: (lat * 1e7).round(), lonE7: (lon * 1e7).round());

  /// JSON form.
  Map<String, Object?> toJson() => {'lat': lat, 'lon': lon};

  /// Great-circle distance to [other] in metres (haversine, mean Earth radius).
  double distanceTo(LatLon other) {
    const r = 6371008.8;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(other.lat - lat);
    final dLon = rad(other.lon - lon);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat)) * math.cos(rad(other.lat)) * math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(h)));
  }

  @override
  bool operator ==(Object other) => other is LatLon && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
}
