/// 24-hour trails of trip contacts (and you) and GPX 1.1 export.
///
/// A point is recorded only from a real position: a beacon, a check-in, or
/// your own fix. Trails are kept in the encrypted node history and trimmed to
/// 24 hours, with points thinned so a day of beacons stays small.
library;

import 'dart:convert';
import 'dart:math' as math;

/// How far back trails go.
const trailWindow = Duration(hours: 24);

/// Most points kept per node: one every two minutes for a day.
const kMaxTrailPoints = 720;

/// A point closer than this in time and distance to the last one is skipped.
const kTrailMinGap = Duration(seconds: 60);

/// Metres: see [kTrailMinGap].
const kTrailMinMetres = 20.0;

/// One position at one time.
class TrailFix {
  /// Creates a fix.
  const TrailFix({required this.latitude, required this.longitude, required this.at});

  /// From [toJson]; null for anything malformed.
  static TrailFix? fromJson(Object? j) {
    if (j is! List || j.length != 3) return null;
    final [lat, lon, ms] = j;
    if (lat is! num || lon is! num || ms is! int) return null;
    final f = TrailFix(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      at: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
    );
    return f.valid ? f : null;
  }

  /// Degrees.
  final double latitude;

  /// Degrees.
  final double longitude;

  /// When the position was true.
  final DateTime at;

  /// Whether the coordinates are on Earth.
  bool get valid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  /// Compact JSON: `[lat, lon, epochMs]`.
  List<Object> toJson() => [latitude, longitude, at.toUtc().millisecondsSinceEpoch];
}

double _metres(TrailFix a, TrailFix b) {
  // equirectangular: plenty for "did they move 20 m"
  const r = 6371000.0;
  final x = (b.longitude - a.longitude) * math.pi / 180 * math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
  final y = (b.latitude - a.latitude) * math.pi / 180;
  return r * math.sqrt(x * x + y * y);
}

/// [track] (oldest first) with [fix] added, older than 24 hours dropped,
/// thinned and capped. Returns [track] itself when nothing changes.
List<TrailFix> addTrailFix(List<TrailFix> track, TrailFix fix, DateTime now) {
  final t = now.toUtc();
  final stamp = fix.at.toUtc();
  if (!fix.valid || stamp.isAfter(t.add(const Duration(minutes: 1))) || !stamp.isAfter(t.subtract(trailWindow))) {
    return track;
  }
  if (track.any((p) => p.at.isAtSameMomentAs(stamp))) return track;
  if (track.isNotEmpty) {
    final last = track.last;
    if (!stamp.isBefore(last.at) && stamp.difference(last.at) < kTrailMinGap && _metres(last, fix) < kTrailMinMetres) {
      return track;
    }
  }
  final out = [...track, fix]..sort((a, b) => a.at.compareTo(b.at));
  final cutoff = t.subtract(trailWindow);
  out.removeWhere((p) => !p.at.isAfter(cutoff));
  return out.length > kMaxTrailPoints ? out.sublist(out.length - kMaxTrailPoints) : out;
}

/// [tracks] without points older than 24 hours, and without empty tracks.
Map<int, List<TrailFix>> pruneTrails(Map<int, List<TrailFix>> tracks, DateTime now) {
  final cutoff = now.toUtc().subtract(trailWindow);
  return {
    for (final MapEntry(:key, :value) in tracks.entries)
      if (value.where((p) => p.at.isAfter(cutoff)).toList() case final kept when kept.isNotEmpty) key: kept,
  };
}

/// GPX 1.1, one `trk` per node, names XML-escaped, times in UTC.
String trailsToGpx(Map<int, List<TrailFix>> tracks, Map<int, String> names) {
  final out = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<gpx version="1.1" creator="GhostWave" '
    'xmlns="http://www.topografix.com/GPX/1/1">\n',
  );
  const esc = HtmlEscape(HtmlEscapeMode.element);
  for (final e in tracks.entries) {
    if (e.value.isEmpty) continue;
    out.write('<trk><name>${esc.convert(names[e.key] ?? e.key.toRadixString(16))}</name><trkseg>\n');
    for (final p in e.value) {
      out.write(
        '<trkpt lat="${p.latitude}" lon="${p.longitude}">'
        '<time>${p.at.toUtc().toIso8601String()}</time></trkpt>\n',
      );
    }
    out.write('</trkseg></trk>\n');
  }
  out.write('</gpx>\n');
  return out.toString();
}

/// An in-memory set of trails. The app keeps trails in MeshState; this class
/// is the same rules for callers that want a mutable holder.
class TeamTrails {
  Map<int, List<TrailFix>> _tracks = {};

  /// Records a real, timestamped fix for [nodeId].
  void record(int nodeId, TrailFix fix, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final before = _tracks[nodeId] ?? const <TrailFix>[];
    final after = addTrailFix(before, fix, t);
    if (!identical(before, after)) _tracks = {..._tracks, nodeId: after};
    prune(now: t);
  }

  /// Drops points older than 24 hours.
  void prune({DateTime? now}) => _tracks = pruneTrails(_tracks, now ?? DateTime.now());

  /// Forgets [nodeId]'s trail.
  void clear(int nodeId) => _tracks = {..._tracks}..remove(nodeId);

  /// Forgets every trail.
  void clearAll() => _tracks = {};

  /// The trails now, oldest point first.
  Map<int, List<TrailFix>> snapshot({DateTime? now}) {
    prune(now: now);
    return {for (final e in _tracks.entries) e.key: List<TrailFix>.unmodifiable(e.value)};
  }

  /// GPX 1.1 of [snapshot].
  String exportGpx(Map<int, String> names, {DateTime? now}) => trailsToGpx(snapshot(now: now), names);
}
