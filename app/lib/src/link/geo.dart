/// Positions on the wire are `sint32` in 1e-7 degrees.
library;

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

  @override
  bool operator ==(Object other) => other is LatLon && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
}
