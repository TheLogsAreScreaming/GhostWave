/// Range rings: evenly spaced circles around your position, sized to what is
/// on screen, with round-number distances in your units.
library;

import 'dart:math' as math;

import '../app/preferences.dart';
import '../link/geo.dart';

const _metresPerMile = 1609.344;
const _earthRadiusM = 6371008.8;

/// A round step: 1, 2 or 5 times a power of ten, the largest not above [x].
double niceStep(double x) {
  if (x <= 0 || x.isNaN || x.isInfinite) return 0;
  final p = math.pow(10, (math.log(x) / math.ln10).floor()).toDouble();
  final f = x / p;
  final m = f >= 5
      ? 5
      : f >= 2
      ? 2
      : 1;
  return m * p;
}

/// The radii, in metres, of [count] rings that fill [spanMetres] (the
/// distance from you to the edge of the view) in round steps of [units].
///
/// Metric steps are whole metres from 10 m up; imperial steps are miles
/// from 0.1 mi up. Empty when [spanMetres] is not a usable distance.
List<double> ringRadii(double spanMetres, Units units, {int count = 4}) {
  if (spanMetres <= 0 || spanMetres.isNaN || spanMetres.isInfinite || count < 1) return const [];
  final List<double> out;
  if (units == Units.imperial) {
    final step = math.max(0.1, niceStep(spanMetres / _metresPerMile / count));
    out = [for (var i = 1; i <= count; i++) step * i * _metresPerMile];
  } else {
    final step = math.max(10, niceStep(spanMetres / count)).toDouble();
    out = [for (var i = 1; i <= count; i++) step * i];
  }
  return out;
}

/// A ring's label: "500 m", "2 km", "0.5 mi", "10 mi". Ring distances are
/// round numbers, so no "2.0".
String ringLabel(double metres, Units units) {
  String trim(double v) {
    final s = v.toStringAsFixed(v < 1 ? 1 : (v < 10 && v != v.roundToDouble() ? 1 : 0));
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }

  if (units == Units.imperial) return '${trim(metres / _metresPerMile)} mi';
  if (metres < 1000) return '${metres.round()} m';
  return '${trim(metres / 1000)} km';
}

/// The point [metres] away from [from] along [bearingDeg] (degrees from
/// true north), on a sphere. Good to well under 1 % at ring distances.
LatLon pointAt(LatLon from, double bearingDeg, double metres) {
  final d = metres / _earthRadiusM;
  final b = bearingDeg * math.pi / 180;
  final lat1 = from.lat * math.pi / 180;
  final lon1 = from.lon * math.pi / 180;
  final lat2 = math.asin(math.sin(lat1) * math.cos(d) + math.cos(lat1) * math.sin(d) * math.cos(b));
  final lon2 =
      lon1 + math.atan2(math.sin(b) * math.sin(d) * math.cos(lat1), math.cos(d) - math.sin(lat1) * math.sin(lat2));
  final lon = ((lon2 * 180 / math.pi) + 540) % 360 - 180;
  return LatLon(lat2 * 180 / math.pi, lon);
}
