/// Waypoints: pins people drop on the map and share over the mesh.
///
/// A waypoint travels as an ordinary DM or channel message in a fixed,
/// readable form, so an app without this feature still shows it as text:
///
///     [WP 3fa2 water] Spring below ridge · 45.12345,-110.45678 · Filter it
///     [WP 3fa2 removed] Spring below ridge
///
/// `3fa2` is the sender's own ID for the pin: a later message with the same ID
/// from the same node replaces it (an edit) or takes it off the map
/// (`removed`). Nothing new goes on the air and the radio protocol is unchanged.
library;

import 'dart:math';

import '../link/contact_card.dart';
import '../link/geo.dart';

/// Longest waypoint name, in characters.
const int kWaypointNameMax = 32;

/// Longest waypoint note, in characters (the radio's byte limit may cut it
/// shorter when it is sent).
const int kWaypointNoteMax = 120;

/// Most waypoints kept per node history; the oldest received ones go first.
const int kMaxWaypoints = 500;

/// Messages longer than this are never parsed as waypoints.
const int _kMaxParsedLength = 1000;

/// What is at a waypoint.
enum WaypointKind {
  /// A place to camp.
  camp('camp', 'Camp'),

  /// Drinking water.
  water('water', 'Water'),

  /// Something to avoid.
  hazard('hazard', 'Hazard'),

  /// Where the vehicles are.
  parking('parking', 'Parking'),

  /// Where to meet up.
  meet('meet', 'Meeting point'),

  /// Anything else.
  other('other', 'Other');

  const WaypointKind(this.wire, this.label);

  /// The word sent on the air.
  final String wire;

  /// The words shown.
  final String label;

  /// The kind for [wire]; an unknown word (from a newer app) is [other].
  static WaypointKind fromWire(String wire) => values.firstWhere((k) => k.wire == wire, orElse: () => other);
}

/// [s] made safe to show and to send: line breaks, control and text-direction
/// characters become spaces, runs of spaces collapse, and it is cut to
/// [maxChars] characters. With [forName], the `·` field separator becomes `-`.
String cleanWaypointText(String s, int maxChars, {bool forName = false}) {
  final out = StringBuffer();
  var count = 0;
  var space = false;
  for (final r in s.runes) {
    final bad =
        r < 0x20 ||
        (r >= 0x7F && r < 0xA0) ||
        r == 0x2028 ||
        r == 0x2029 ||
        (r >= 0x200E && r <= 0x200F) ||
        (r >= 0x202A && r <= 0x202E) ||
        (r >= 0x2066 && r <= 0x2069) ||
        r == 0xFEFF;
    if (bad || r == 0x20) {
      space = out.isNotEmpty;
      continue;
    }
    if (count >= maxChars) break;
    if (space) {
      if (count + 1 >= maxChars) break;
      out.write(' ');
      count++;
      space = false;
    }
    out.writeCharCode(forName && r == 0xB7 ? 0x2D : r);
    count++;
  }
  return out.toString();
}

/// A waypoint message read from, or about to go on, the air.
sealed class WaypointWire {
  const WaypointWire(this.id);

  /// The sender's ID for the pin: 4 lowercase hex digits.
  final String id;
}

/// A new or changed waypoint.
final class WaypointPut extends WaypointWire {
  /// Creates one.
  const WaypointPut({required String id, required this.kind, required this.name, required this.pos, this.note = ''})
    : super(id);

  /// What is there.
  final WaypointKind kind;

  /// A short name.
  final String name;

  /// Where.
  final LatLon pos;

  /// Optional words.
  final String note;
}

/// The sender took a waypoint off the map.
final class WaypointRemoval extends WaypointWire {
  /// Creates one.
  const WaypointRemoval({required String id, this.name = ''}) : super(id);

  /// The name it had, so older apps show what went.
  final String name;
}

final RegExp _idPattern = RegExp(r'^[0-9a-f]{4}$');

/// A fresh waypoint ID not in [taken].
String newWaypointId(Random rng, Set<String> taken) {
  for (;;) {
    final id = rng.nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    if (!taken.contains(id)) return id;
  }
}

String _coords(LatLon p) => '${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)}';

/// The message text for [p], or null when even a one-letter name cannot fit
/// [maxBytes] of UTF-8. The note is shortened first, then the name, so the
/// text always fits one radio message.
String? waypointText(WaypointPut p, int maxBytes) {
  if (!_idPattern.hasMatch(p.id)) throw ArgumentError.value(p.id, 'id');
  final head = '[WP ${p.id} ${p.kind.wire}] ';
  final coords = _coords(p.pos);
  var name = cleanWaypointText(p.name, kWaypointNameMax, forName: true);
  if (name.isEmpty) name = p.kind.label;
  final note = cleanWaypointText(p.note, kWaypointNoteMax);
  final base = '$head$name · $coords';
  if (note.isNotEmpty) {
    final room = maxBytes - utf8Length(base) - utf8Length(' · ');
    final cut = truncateUtf8(note, room < 0 ? 0 : room).trimRight();
    if (cut.isNotEmpty) return '$base · $cut';
  }
  if (utf8Length(base) <= maxBytes) return base;
  final room = maxBytes - utf8Length('$head · $coords');
  if (room < 1) return null;
  final cut = truncateUtf8(name, room).trimRight();
  return cut.isEmpty ? null : '$head$cut · $coords';
}

/// The message text taking waypoint [id] (named [name]) off others' maps,
/// within [maxBytes] (the name is shortened or left out to fit).
String waypointRemovalText(String id, String name, int maxBytes) {
  if (!_idPattern.hasMatch(id)) throw ArgumentError.value(id, 'id');
  final head = '[WP $id removed]';
  final clean = cleanWaypointText(name, kWaypointNameMax, forName: true);
  final room = maxBytes - utf8Length(head) - 1;
  final cut = room < 1 ? '' : truncateUtf8(clean, room).trimRight();
  return cut.isEmpty ? head : '$head $cut';
}

final RegExp _putRe = RegExp(
  r'^\[WP ([0-9a-f]{4}) ([a-z]{1,12})\] (.+?) · (-?\d{1,2}\.\d{1,7}), ?(-?\d{1,3}\.\d{1,7})(?: · (.+))?$',
);
final RegExp _removeRe = RegExp(r'^\[WP ([0-9a-f]{4}) removed\](?: (.*))?$');

/// [text] as a waypoint message, or null if it is an ordinary message (or a
/// malformed one, which then simply shows as text).
WaypointWire? parseWaypoint(String text) {
  if (text.length > _kMaxParsedLength || !text.startsWith('[WP ')) return null;
  final t = text.trim();
  final rm = _removeRe.firstMatch(t);
  if (rm != null) {
    return WaypointRemoval(id: rm.group(1)!, name: cleanWaypointText(rm.group(2) ?? '', kWaypointNameMax));
  }
  final m = _putRe.firstMatch(t);
  if (m == null || m.group(2) == 'removed') return null;
  final lat = double.tryParse(m.group(4)!);
  final lon = double.tryParse(m.group(5)!);
  if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) return null;
  final name = cleanWaypointText(m.group(3)!, kWaypointNameMax);
  if (name.isEmpty) return null;
  return WaypointPut(
    id: m.group(1)!,
    kind: WaypointKind.fromWire(m.group(2)!),
    name: name,
    pos: LatLon(lat, lon),
    note: cleanWaypointText(m.group(6) ?? '', kWaypointNoteMax),
  );
}

/// One pin, ours or someone else's.
class Waypoint {
  /// Creates one.
  const Waypoint({
    required this.id,
    required this.kind,
    required this.name,
    required this.pos,
    required this.at,
    this.owner,
    this.note = '',
    this.peer,
    this.channel,
    this.hidden = false,
  });

  /// From [toJson]; null when malformed.
  static Waypoint? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final kind = j['kind'];
    final name = j['name'];
    final lat = j['lat'];
    final lon = j['lon'];
    final at = j['at'];
    final owner = j['owner'];
    final note = j['note'];
    final peer = j['peer'];
    final channel = j['ch'];
    if (id is! String || !_idPattern.hasMatch(id)) return null;
    if (kind is! String || name is! String || name.isEmpty || lat is! num || lon is! num || at is! int) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    if ((owner != null && owner is! int) || (peer != null && peer is! int) || (channel != null && channel is! String)) {
      return null;
    }
    return Waypoint(
      id: id,
      kind: WaypointKind.fromWire(kind),
      name: cleanWaypointText(name, kWaypointNameMax),
      pos: LatLon(lat.toDouble(), lon.toDouble()),
      at: DateTime.fromMillisecondsSinceEpoch(at),
      owner: owner as int?,
      note: note is String ? cleanWaypointText(note, kWaypointNoteMax) : '',
      peer: peer as int?,
      channel: channel as String?,
      hidden: j['hidden'] == true,
    );
  }

  /// The owner's ID for it (4 hex digits).
  final String id;

  /// What is there.
  final WaypointKind kind;

  /// Short name.
  final String name;

  /// Where.
  final LatLon pos;

  /// When it was made, or last changed, as this phone saw it.
  final DateTime at;

  /// The node that shared it; null for ours.
  final int? owner;

  /// Optional words.
  final String note;

  /// Ours: the contact it was shared with. Others': the contact it came from
  /// as a DM. Null otherwise.
  final int? peer;

  /// The channel it was shared in or came from, if any.
  final String? channel;

  /// Others' only: the user hid it from the map.
  final bool hidden;

  /// Whether we made it.
  bool get mine => owner == null;

  /// Whether it went out (ours) to a contact or channel.
  bool get shared => peer != null || channel != null;

  /// Unique within one history: the owner and its ID.
  String get key => waypointKey(owner, id);

  /// A copy with changes.
  Waypoint copyWith({
    WaypointKind? kind,
    String? name,
    LatLon? pos,
    DateTime? at,
    String? note,
    int? peer,
    String? channel,
    bool clearPlace = false,
    bool? hidden,
  }) => Waypoint(
    id: id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    pos: pos ?? this.pos,
    at: at ?? this.at,
    owner: owner,
    note: note ?? this.note,
    peer: clearPlace ? peer : (peer ?? this.peer),
    channel: clearPlace ? channel : (channel ?? this.channel),
    hidden: hidden ?? this.hidden,
  );

  /// The wire form of its content.
  WaypointPut toWire() => WaypointPut(id: id, kind: kind, name: name, pos: pos, note: note);

  /// JSON form.
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.wire,
    'name': name,
    'lat': pos.lat,
    'lon': pos.lon,
    'at': at.millisecondsSinceEpoch,
    if (owner != null) 'owner': owner,
    if (note.isNotEmpty) 'note': note,
    if (peer != null) 'peer': peer,
    if (channel != null) 'ch': channel,
    if (hidden) 'hidden': true,
  };
}

/// The key of [owner]'s waypoint [id] (null owner: ours).
String waypointKey(int? owner, String id) => owner == null ? 'me:$id' : '${nodeIdHex(owner)}:$id';

/// Every waypoint in one node's history, by [Waypoint.key].
class WaypointBook {
  /// Creates a book.
  const WaypointBook([this.byKey = const {}]);

  /// From [toJson]; malformed entries are dropped.
  factory WaypointBook.fromJson(Object? j) {
    if (j is! List) return const WaypointBook();
    final out = <String, Waypoint>{};
    for (final x in j) {
      final w = Waypoint.tryFromJson(x);
      if (w != null) out[w.key] = w;
    }
    return WaypointBook(out);
  }

  /// Waypoints by key.
  final Map<String, Waypoint> byKey;

  /// Whether there are none.
  bool get isEmpty => byKey.isEmpty;

  /// All of them, newest first.
  List<Waypoint> get all => byKey.values.toList()..sort((a, b) => b.at.compareTo(a.at));

  /// The IDs we have used for our own.
  Set<String> get ownIds => {
    for (final w in byKey.values)
      if (w.mine) w.id,
  };

  /// With [w] added or replaced (keeping a hidden flag the user set).
  WaypointBook put(Waypoint w) {
    final old = byKey[w.key];
    final next = {...byKey, w.key: old != null && old.hidden && !w.mine ? w.copyWith(hidden: true) : w};
    return WaypointBook(_capped(next));
  }

  /// Without [key].
  WaypointBook remove(String key) => byKey.containsKey(key) ? WaypointBook({...byKey}..remove(key)) : this;

  /// With [key]'s hidden flag set to [hidden] (others' only).
  WaypointBook setHidden(String key, bool hidden) {
    final w = byKey[key];
    if (w == null || w.mine || w.hidden == hidden) return this;
    return WaypointBook({...byKey, key: w.copyWith(hidden: hidden)});
  }

  /// With [msg] from node [src] applied: a put adds or replaces, a removal
  /// drops it. [peer] or [channel] is where it came from.
  WaypointBook receive(int src, WaypointWire msg, DateTime at, {int? peer, String? channel}) => switch (msg) {
    WaypointRemoval(:final id) => remove(waypointKey(src, id)),
    WaypointPut(:final id, :final kind, :final name, :final pos, :final note) => put(
      Waypoint(id: id, kind: kind, name: name, pos: pos, at: at, owner: src, note: note, peer: peer, channel: channel),
    ),
  };

  /// Keeps at most [kMaxWaypoints], dropping the oldest received ones.
  static Map<String, Waypoint> _capped(Map<String, Waypoint> m) {
    if (m.length <= kMaxWaypoints) return m;
    final others = m.values.where((w) => !w.mine).toList()..sort((a, b) => a.at.compareTo(b.at));
    final out = {...m};
    for (final w in others) {
      if (out.length <= kMaxWaypoints) break;
      out.remove(w.key);
    }
    return out;
  }

  /// JSON form.
  List<Object?> toJson() => [for (final w in byKey.values) w.toJson()];
}
