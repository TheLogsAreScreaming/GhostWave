/// Privacy-conscious, local 24-hour trail history and GPX 1.1 serialization.
/// A point is only recorded after the application receives a real position fix.
library;

import 'dart:convert';

const trailWindow = Duration(hours: 24);

class TrailFix {
  const TrailFix({required this.latitude, required this.longitude, required this.at});
  final double latitude;
  final double longitude;
  final DateTime at;

  bool get valid => latitude.isFinite && longitude.isFinite &&
      latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
}

class TeamTrails {
  final Map<int, List<TrailFix>> _tracks = {};

  /// Record a real, timestamped fix for a selected trip contact.
  /// Callers must enforce their own opt-in and authorization before recording.
  void record(int nodeId, TrailFix fix, {DateTime? now}) {
    final time = (now ?? DateTime.now()).toUtc();
    final stamp = fix.at.toUtc();
    if (!fix.valid || stamp.isAfter(time) || !stamp.isAfter(time.subtract(trailWindow))) return;
    final track = _tracks.putIfAbsent(nodeId, () => []);
    if (track.any((p) => p.at.isAtSameMomentAs(stamp))) return;
    track.add(fix);
    track.sort((a, b) => a.at.compareTo(b.at));
    prune(now: time);
  }

  void prune({DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).toUtc().subtract(trailWindow);
    for (final id in _tracks.keys.toList()) {
      _tracks[id]!.removeWhere((p) => !p.at.toUtc().isAfter(cutoff));
      if (_tracks[id]!.isEmpty) _tracks.remove(id);
    }
  }

  void clear(int nodeId) => _tracks.remove(nodeId);
  void clearAll() => _tracks.clear();

  Map<int, List<TrailFix>> snapshot({DateTime? now}) {
    prune(now: now);
    return {for (final e in _tracks.entries) e.key: List.unmodifiable(e.value)};
  }

  /// GPX 1.1 tracks; one trk per contact. XML-escaped display names.
  String exportGpx(Map<int, String> names, {DateTime? now}) {
    final tracks = snapshot(now: now);
    final out = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<gpx version="1.1" creator="GhostWave" '
        'xmlns="http://www.topografix.com/GPX/1/1">\n');
    for (final e in tracks.entries) {
      if (e.value.isEmpty) continue;
      final name = const HtmlEscape(HtmlEscapeMode.element).convert(names[e.key] ?? e.key.toString());
      out.write('<trk><name>$name</name><trkseg>\n');
      for (final p in e.value) {
        out.write('<trkpt lat="${p.latitude}" lon="${p.longitude}">'
            '<time>${p.at.toUtc().toIso8601String()}</time></trkpt>\n');
      }
      out.write('</trkseg></trk>\n');
    }
    out.write('</gpx>\n');
    return out.toString();
  }
}
