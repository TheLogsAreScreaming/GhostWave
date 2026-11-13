/// The node journal: every node this app has heard, kept on the phone with
/// the connected node's history. Each entry is a compact record of when and
/// how the node was heard; [describeNode] turns it into behaviour labels with
/// a confidence and the evidence behind each one.
library;

import 'dart:math' as math;

import '../link/geo.dart';

/// How a node was heard.
enum HeardVia {
  /// Its periodic beacon (neighbor event).
  beacon,

  /// Its signed identity announcement.
  ident,

  /// A direct message from it.
  direct,

  /// A group channel message from it.
  channel,

  /// An SOS from it.
  sos,
}

/// Hours are counted in whole UTC hours since the epoch.
int hourKey(DateTime t) => t.millisecondsSinceEpoch ~/ Duration.millisecondsPerHour;

/// Days are counted in whole UTC days since the epoch.
int dayKey(DateTime t) => t.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

/// Hour-by-hour detail is kept this long; behaviour labels look at this window.
const int kJournalHourWindow = 7 * 24;

/// Day-by-day detail is kept this long.
const int kJournalDayWindow = 60;

/// Positions kept per node (spread out by at least [kJournalFixSpacingM]).
const int kJournalMaxFixes = 16;

/// A new position is only kept when it is this far from the last kept one.
const double kJournalFixSpacingM = 100;

/// Most nodes kept; the ones heard longest ago go first.
const int kJournalMaxNodes = 1000;

/// Longest tag, in characters.
const int kJournalMaxTagLength = 24;

/// Most tags per node.
const int kJournalMaxTags = 12;

/// Longest note, in characters.
const int kJournalMaxNoteLength = 1000;

List<int> _ints(Object? j) => [
  if (j is List)
    for (final x in j)
      if (x is int) x,
];

/// One node's record.
class JournalEntry {
  /// Creates an entry.
  const JournalEntry({
    required this.nodeId,
    required this.firstHeard,
    required this.lastHeard,
    this.timesHeard = 0,
    this.hours = const [],
    this.days = const [],
    this.via = const {},
    this.fixes = const [],
    this.lastPos,
    this.bestRssi,
    this.lastRssi,
    this.name = '',
    this.tags = const [],
    this.note = '',
  });

  /// From [toJson]; null if malformed.
  static JournalEntry? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final first = j['first'];
    final last = j['last'];
    if (id is! int || first is! int || last is! int) return null;
    LatLon? pos(Object? p) {
      if (p is! Map) return null;
      final lat = p['lat'];
      final lon = p['lon'];
      return lat is num && lon is num ? LatLon(lat.toDouble(), lon.toDouble()) : null;
    }

    final via = <HeardVia, int>{};
    if (j['via'] case final Map<Object?, Object?> m) {
      for (final v in HeardVia.values) {
        if (m[v.name] case final int n when n > 0) via[v] = n;
      }
    }
    final name = j['name'];
    final note = j['note'];
    final tags = j['tags'];
    final count = j['n'];
    final best = j['best'];
    final lastRssi = j['rssi'];
    return JournalEntry(
      nodeId: id,
      firstHeard: DateTime.fromMillisecondsSinceEpoch(first),
      lastHeard: DateTime.fromMillisecondsSinceEpoch(last),
      timesHeard: count is int ? count : 0,
      hours: _ints(j['h']),
      days: _ints(j['d']),
      via: via,
      fixes: [
        if (j['fix'] case final List<Object?> l)
          for (final p in l) ?pos(p),
      ],
      lastPos: pos(j['pos']),
      bestRssi: best is int ? best : null,
      lastRssi: lastRssi is int ? lastRssi : null,
      name: name is String ? name : '',
      tags: [
        if (tags is List)
          for (final t in tags)
            if (t is String) t,
      ],
      note: note is String ? note : '',
    );
  }

  /// The node.
  final int nodeId;

  /// When this app first heard it.
  final DateTime firstHeard;

  /// When this app last heard it.
  final DateTime lastHeard;

  /// Every time it was heard (beacons, messages, identity).
  final int timesHeard;

  /// UTC hours (see [hourKey]) it was heard in, oldest first, last
  /// [kJournalHourWindow] hours only.
  final List<int> hours;

  /// UTC days (see [dayKey]) it was heard on, oldest first, last
  /// [kJournalDayWindow] days only.
  final List<int> days;

  /// How many times it was heard each way.
  final Map<HeardVia, int> via;

  /// Positions it reported, at least [kJournalFixSpacingM] apart, oldest first.
  final List<LatLon> fixes;

  /// Its latest reported position.
  final LatLon? lastPos;

  /// Strongest signal heard from it, whole dBm.
  final int? bestRssi;

  /// Signal of the last time it was heard, whole dBm.
  final int? lastRssi;

  /// The name it announced (may be empty).
  final String name;

  /// The user's tags.
  final List<String> tags;

  /// The user's note.
  final String note;

  /// Widest distance between any two of its reported positions, metres.
  double get spreadM {
    var widest = 0.0;
    for (var i = 0; i < fixes.length; i++) {
      for (var k = i + 1; k < fixes.length; k++) {
        widest = math.max(widest, fixes[i].distanceTo(fixes[k]));
      }
    }
    return widest;
  }

  /// A copy with some fields changed.
  JournalEntry copyWith({
    DateTime? lastHeard,
    int? timesHeard,
    List<int>? hours,
    List<int>? days,
    Map<HeardVia, int>? via,
    List<LatLon>? fixes,
    LatLon? lastPos,
    int? bestRssi,
    int? lastRssi,
    String? name,
    List<String>? tags,
    String? note,
  }) => JournalEntry(
    nodeId: nodeId,
    firstHeard: firstHeard,
    lastHeard: lastHeard ?? this.lastHeard,
    timesHeard: timesHeard ?? this.timesHeard,
    hours: hours ?? this.hours,
    days: days ?? this.days,
    via: via ?? this.via,
    fixes: fixes ?? this.fixes,
    lastPos: lastPos ?? this.lastPos,
    bestRssi: bestRssi ?? this.bestRssi,
    lastRssi: lastRssi ?? this.lastRssi,
    name: name ?? this.name,
    tags: tags ?? this.tags,
    note: note ?? this.note,
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'id': nodeId,
    'first': firstHeard.millisecondsSinceEpoch,
    'last': lastHeard.millisecondsSinceEpoch,
    'n': timesHeard,
    if (hours.isNotEmpty) 'h': hours,
    if (days.isNotEmpty) 'd': days,
    if (via.isNotEmpty) 'via': {for (final e in via.entries) e.key.name: e.value},
    if (fixes.isNotEmpty) 'fix': [for (final p in fixes) p.toJson()],
    if (lastPos != null) 'pos': lastPos!.toJson(),
    'best': ?bestRssi,
    'rssi': ?lastRssi,
    if (name.isNotEmpty) 'name': name,
    if (tags.isNotEmpty) 'tags': tags,
    if (note.isNotEmpty) 'note': note,
  };
}

/// Adds [key] to the sorted [list] (if new) and drops keys below [floor].
List<int> _addKey(List<int> list, int key, int floor) {
  if (list.isNotEmpty && list.last == key) return list;
  return [
    for (final k in list)
      if (k >= floor && k != key) k,
    key,
  ]..sort();
}

/// Tidies user tags: trimmed, at most [kJournalMaxTagLength] characters, no
/// blanks or case-insensitive repeats, at most [kJournalMaxTags].
List<String> cleanTags(Iterable<String> tags) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in tags) {
    final t = _clip(raw.trim().replaceAll(RegExp(r'\s+'), ' '), kJournalMaxTagLength).trim();
    if (t.isEmpty || !seen.add(t.toLowerCase())) continue;
    out.add(t);
    if (out.length == kJournalMaxTags) break;
  }
  return out;
}

/// [s] cut to at most [max] code points (never splitting a surrogate pair).
String _clip(String s, int max) {
  final runes = s.runes;
  return runes.length <= max ? s : String.fromCharCodes(runes.take(max));
}

/// Every node heard, plus the hours this app was listening (so "heard in 20
/// of 22 hours" compares against time the app could actually hear).
class NodeJournal {
  /// Creates a journal.
  const NodeJournal({this.entries = const {}, this.listened = const []});

  /// From [toJson]; anything malformed is dropped.
  factory NodeJournal.fromJson(Object? j) {
    if (j is! Map) return const NodeJournal();
    final entries = <int, JournalEntry>{};
    if (j['nodes'] case final List<Object?> nodes) {
      for (final n in nodes) {
        final e = JournalEntry.tryFromJson(n);
        if (e != null) entries[e.nodeId] = e;
      }
    }
    return NodeJournal(entries: entries, listened: _ints(j['listened']));
  }

  /// Entries by node ID.
  final Map<int, JournalEntry> entries;

  /// UTC hours (see [hourKey]) the app was connected and listening, oldest
  /// first, last [kJournalHourWindow] hours only.
  final List<int> listened;

  /// Whether nothing has been logged.
  bool get isEmpty => entries.isEmpty;

  /// Notes that the app was listening at [at]. Returns this journal unchanged
  /// when the hour is already counted.
  NodeJournal markListening(DateTime at) {
    final h = hourKey(at);
    if (listened.isNotEmpty && listened.last == h) return this;
    return NodeJournal(entries: entries, listened: _addKey(listened, h, h - kJournalHourWindow + 1));
  }

  /// Logs that [nodeId] was heard at [at]. When [timed] is false (a message
  /// the node held while no app was connected) the node still counts as heard,
  /// but [at] is only when it reached the app, so no hour or day is counted.
  NodeJournal record(
    int nodeId,
    DateTime at,
    HeardVia via, {
    LatLon? pos,
    int? rssiDbm,
    String? name,
    bool timed = true,
  }) {
    final h = hourKey(at);
    final d = dayKey(at);
    final old = entries[nodeId] ?? JournalEntry(nodeId: nodeId, firstHeard: at, lastHeard: at);
    var fixes = old.fixes;
    if (pos != null && (fixes.isEmpty || fixes.last.distanceTo(pos) >= kJournalFixSpacingM)) {
      fixes = [...fixes, pos];
      if (fixes.length > kJournalMaxFixes) fixes = fixes.sublist(fixes.length - kJournalMaxFixes);
    }
    final entry = old.copyWith(
      lastHeard: at.isAfter(old.lastHeard) ? at : old.lastHeard,
      timesHeard: old.timesHeard + 1,
      hours: timed ? _addKey(old.hours, h, h - kJournalHourWindow + 1) : null,
      days: timed ? _addKey(old.days, d, d - kJournalDayWindow + 1) : null,
      via: {...old.via, via: (old.via[via] ?? 0) + 1},
      fixes: fixes,
      lastPos: pos,
      bestRssi: rssiDbm == null ? null : math.max(rssiDbm, old.bestRssi ?? rssiDbm),
      lastRssi: rssiDbm,
      name: (name == null || name.isEmpty) ? null : name,
    );
    var next = {...entries, nodeId: entry};
    if (next.length > kJournalMaxNodes) {
      final oldest = next.values.reduce((a, b) => a.lastHeard.isBefore(b.lastHeard) ? a : b);
      next = {...next}..remove(oldest.nodeId);
    }
    return NodeJournal(entries: next, listened: timed ? _addKey(listened, h, h - kJournalHourWindow + 1) : listened);
  }

  /// Sets the user's tags for [nodeId] (see [cleanTags]).
  NodeJournal withTags(int nodeId, Iterable<String> tags) {
    final e = entries[nodeId];
    if (e == null) return this;
    return NodeJournal(
      entries: {
        ...entries,
        nodeId: e.copyWith(tags: cleanTags(tags)),
      },
      listened: listened,
    );
  }

  /// Sets the user's note for [nodeId] (trimmed, at most
  /// [kJournalMaxNoteLength] characters).
  NodeJournal withNote(int nodeId, String note) {
    final e = entries[nodeId];
    if (e == null) return this;
    return NodeJournal(
      entries: {
        ...entries,
        nodeId: e.copyWith(note: _clip(note.trim(), kJournalMaxNoteLength)),
      },
      listened: listened,
    );
  }

  /// Removes [nodeId] (it comes back if heard again).
  NodeJournal forget(int nodeId) => NodeJournal(entries: {...entries}..remove(nodeId), listened: listened);

  /// JSON form.
  Map<String, Object?> toJson() => {
    'nodes': [for (final e in entries.values) e.toJson()],
    if (listened.isNotEmpty) 'listened': listened,
  };
}

// ------------------------------------------------------------ behaviour --

/// A behaviour the journal can recognise.
enum NodeTrait {
  /// Heard nearly every hour the app listens, from one place.
  steadyRelay('Always-on relay', 'Heard almost every hour this app listens, from the same place.'),

  /// Reports positions far apart.
  roamer('Roamer', 'Its reported position moves around.'),

  /// Comes and goes, but turns up on many days.
  regular('Regular', 'Not always on, but heard on many different days.'),

  /// Heard only a handful of times over a long stretch.
  rarelyHeard('Rarely heard', 'Heard only a few times over a long stretch.'),

  /// First heard within the last three days.
  newcomer('New arrival', 'First heard in the last three days.'),

  /// Writes to you or to your channels.
  talker('Talker', 'Sends you direct or channel messages.');

  const NodeTrait(this.label, this.meaning);

  /// Short name shown on chips.
  final String label;

  /// One-sentence meaning.
  final String meaning;
}

/// One label for a node, how sure the journal is, and why.
class TraitReading {
  /// Creates a reading.
  const TraitReading(this.trait, this.confidence, this.evidence);

  /// The behaviour.
  final NodeTrait trait;

  /// 0 (a guess) to 1 (certain).
  final double confidence;

  /// What was observed, as plain sentences.
  final List<String> evidence;

  /// Confidence as a whole percentage.
  int get percent => (confidence * 100).round();

  /// "likely", "probable" or "possible".
  String get strength => confidence >= 0.75
      ? 'likely'
      : confidence >= 0.5
      ? 'probable'
      : 'possible';
}

/// A label is only shown from this confidence up.
const double kTraitThreshold = 0.35;

String _metres(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

String _ago(Duration d) {
  if (d.inMinutes < 60) return '${math.max(1, d.inMinutes)} min ago';
  if (d.inHours < 48) return '${d.inHours} h ago';
  return '${d.inDays} days ago';
}

String _times(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// Labels for [e], strongest first, each at least [kTraitThreshold] sure.
/// [journal] supplies the hours the app was listening; [distance] formats
/// metres for the evidence text.
List<TraitReading> describeNode(
  JournalEntry e,
  NodeJournal journal,
  DateTime now, {
  String Function(double metres) distance = _metres,
}) {
  final out = <TraitReading>[];
  final nowHour = hourKey(now);
  final windowStart = nowHour - kJournalHourWindow + 1;
  final listened = journal.listened.where((h) => h >= windowStart && h <= nowHour).toSet();
  final heard = e.hours.where(listened.contains).length;
  final listenedCount = listened.length;
  final coverage = listenedCount == 0 ? 0.0 : heard / listenedCount;
  final spread = e.spreadM;
  final nowDay = dayKey(now);
  final daysLast30 = e.days.where((d) => d > nowDay - 30).length;
  final age = now.difference(e.firstHeard);
  final quiet = now.difference(e.lastHeard);
  final hoursLine = 'Heard in $heard of the ${_times(listenedCount, 'hour')} this app was listening in the last 7 days';
  String place() => e.fixes.isEmpty
      ? 'It has not reported a position'
      : e.fixes.length == 1
      ? 'It reported one position'
      : 'Its reported positions all lie within ${distance(spread)}';

  // Always-on relay: heard nearly every listened hour, and it stays put.
  if (listenedCount >= 6 && coverage >= 0.6 && spread < 300) {
    final evidenceWeight = math.min(1.0, listenedCount / 24);
    final c = ((coverage - 0.6) / 0.4 * 0.6 + 0.4) * (0.5 + 0.5 * evidenceWeight);
    out.add(
      TraitReading(NodeTrait.steadyRelay, c, [
        hoursLine,
        place(),
        if (e.days.length > 1) 'Heard on ${_times(e.days.length, 'different day')}',
      ]),
    );
  }

  // Roamer: positions far apart.
  if (e.fixes.length >= 2 && spread >= 1000) {
    final c = math.min(1.0, spread / 5000) * 0.6 + math.min(1.0, e.fixes.length / 6) * 0.4;
    out.add(
      TraitReading(NodeTrait.roamer, c, [
        'Its reported positions span ${distance(spread)}',
        '${_times(e.fixes.length, 'distinct position')} logged',
      ]),
    );
  }

  // Regular: many days, but not always on.
  if (daysLast30 >= 3 && (listenedCount < 6 || coverage < 0.6)) {
    final c = math.min(1.0, daysLast30 / 10);
    out.add(
      TraitReading(NodeTrait.regular, c, [
        'Heard on $daysLast30 of the last 30 days',
        if (listenedCount > 0) hoursLine,
      ]),
    );
  }

  // Rarely heard: few times over a long time.
  if (age.inDays >= 7 && e.days.length <= 2 && e.timesHeard <= 5) {
    final c = math.min(1.0, age.inDays / 30) * 0.6 + (e.timesHeard <= 2 ? 0.4 : 0.2);
    out.add(
      TraitReading(NodeTrait.rarelyHeard, c, [
        'Heard only ${_times(e.timesHeard, 'time')} since it was first logged ${_ago(age)}',
        'Last heard ${_ago(quiet)}',
      ]),
    );
  }

  // New arrival: first heard in the last three days.
  if (age < const Duration(days: 3)) {
    // new to this app, but maybe not to the area; kept below behaviour
    // labels with real evidence so it never hides them
    final c = 0.4 + 0.2 * math.min(1.0, listenedCount / 24);
    out.add(
      TraitReading(NodeTrait.newcomer, c, [
        'First logged ${_ago(age)}',
        if (listenedCount < 24) 'This app has only listened for ${_times(listenedCount, 'hour')} this week',
      ]),
    );
  }

  // Talker: writes to you.
  final direct = e.via[HeardVia.direct] ?? 0;
  final channel = e.via[HeardVia.channel] ?? 0;
  if (direct + channel >= 3) {
    out.add(
      TraitReading(NodeTrait.talker, math.min(1.0, (direct + channel) / 10), [
        if (direct > 0) 'Sent you ${_times(direct, 'direct message')}',
        if (channel > 0) 'Posted ${_times(channel, 'channel message')} you received',
      ]),
    );
  }

  return [
    for (final r in out)
      if (r.confidence >= kTraitThreshold) TraitReading(r.trait, r.confidence.clamp(0, 1).toDouble(), r.evidence),
  ]..sort((a, b) => b.confidence.compareTo(a.confidence));
}
