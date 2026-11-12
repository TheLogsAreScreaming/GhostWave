/// Small display helpers.
library;

import '../app/preferences.dart';

/// How usable a LoRa link at [dbm] is, in a word, for people who don't read dBm.
/// Rough bands for GhostWave's long-range settings: the radio still decodes well
/// below -120 dBm, but margin shrinks fast past -115.
String signalWord(int dbm) => switch (dbm) {
  >= -90 => 'strong',
  >= -105 => 'good',
  >= -115 => 'fair',
  _ => 'weak',
};

/// "-97 dBm, good": the number and the word, so it never relies on colour.
String signalText(int dbm) => '$dbm dBm, ${signalWord(dbm)}';

/// "12 s ago", "4 min ago", "2 h ago", from a count of seconds.
String secondsAgo(int s) => s < 90
    ? '$s s ago'
    : s < 5400
    ? '${(s / 60).round()} min ago'
    : '${(s / 3600).round()} h ago';

/// "just now", "5 min ago", "3 h ago", "2 d ago".
String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// `HH:mm`, with the date when not today.
String clockTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(t.hour)}:${two(t.minute)}';
  if (t.year == n.year && t.month == n.month && t.day == n.day) return hm;
  return '${t.year}-${two(t.month)}-${two(t.day)} $hm';
}

/// A distance: "850 m" / "1.4 km", or "900 ft" / "2.3 mi".
String formatDistance(double metres, Units units) {
  if (units == Units.imperial) {
    final feet = metres * 3.28084;
    if (feet < 1000) return '${(feet / 10).round() * 10} ft';
    final miles = metres / 1609.344;
    return miles < 10 ? '${miles.toStringAsFixed(1)} mi' : '${miles.round()} mi';
  }
  if (metres < 1000) return '${(metres / 10).round() * 10} m';
  final km = metres / 1000;
  return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}

/// A GPS accuracy: "12 m" or "39 ft", without rounding to tens.
String formatAccuracy(int metres, Units units) =>
    units == Units.imperial ? '${(metres * 3.28084).round()} ft' : '$metres m';

/// The 8-point compass name of a bearing in degrees.
String compassPoint(double bearing) =>
    const ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'][((bearing % 360) / 45).round() % 8];

/// `m:ss`, or `h:mm:ss` from an hour up.
String clockDuration(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  final s = d.isNegative ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  return h > 0 ? '$h:${two(m)}:${two(r)}' : '$m:${two(r)}';
}
