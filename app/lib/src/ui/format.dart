/// Small display helpers.
library;

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
