/// Trip plans and check-ins.
///
/// A check-in is an ordinary encrypted DM in a fixed, readable form, so an app
/// without this feature still shows it as a message:
///
///     [Check-in] At camp · 45.12345, -110.45678
///
/// The app recognises it and builds the team view from message history: no new
/// radio protocol, and nothing extra on the air.
library;

import '../link/geo.dart';
import 'models.dart';

/// Most trip contacts.
const kMaxTripContacts = 6;

/// Most sent check-ins kept.
const kMaxSentCheckIns = 50;

/// What a check-in says.
enum CheckInKind {
  /// All good.
  ok("I'm OK"),

  /// Stopped for the night.
  camp('At camp'),

  /// Running late, not in trouble.
  delayed('Delayed'),

  /// On the way out.
  headingBack('Heading back');

  const CheckInKind(this.label);

  /// The words sent, and shown.
  final String label;
}

const _prefix = '[Check-in] ';

/// The DM text for a check-in, with the position rounded to 5 decimals (about a
/// metre) when known. Always under 60 bytes.
String checkInText(CheckInKind kind, LatLon? pos) => pos == null
    ? '$_prefix${kind.label}'
    : '$_prefix${kind.label} · ${pos.lat.toStringAsFixed(5)}, ${pos.lon.toStringAsFixed(5)}';

/// A check-in read back from a message.
class CheckIn {
  /// Creates one.
  const CheckIn(this.kind, this.pos);

  /// What it says.
  final CheckInKind kind;

  /// Where the sender was, if it said.
  final LatLon? pos;
}

final RegExp _checkIn = RegExp(
  r"^\[Check-in\] (I'm OK|At camp|Delayed|Heading back)(?: · (-?\d{1,2}\.\d{1,7}), (-?\d{1,3}\.\d{1,7}))?$",
);

/// [text] as a check-in, or null if it is an ordinary message.
CheckIn? parseCheckIn(String text) {
  final m = _checkIn.firstMatch(text.trim());
  if (m == null) return null;
  final kind = CheckInKind.values.firstWhere((k) => k.label == m.group(1));
  LatLon? pos;
  if (m.group(2) != null) {
    final lat = double.parse(m.group(2)!);
    final lon = double.parse(m.group(3)!);
    if (lat.abs() <= 90 && lon.abs() <= 180) pos = LatLon(lat, lon);
  }
  return CheckIn(kind, pos);
}

/// The plan: who to check in with, and how often.
class TripPlan {
  /// Creates a plan.
  const TripPlan({
    this.contacts = const [],
    this.reminderMinutes = 0,
    this.overdueMinutes = 0,
    this.startedAt,
    this.note = '',
  });

  /// From [toJson]. Bad values fall back to defaults.
  factory TripPlan.fromJson(Map<String, Object?> j) => TripPlan(
    contacts: [
      for (final c in (j['contacts'] as List<Object?>?) ?? const <Object?>[])
        if (c is int) c,
    ].take(kMaxTripContacts).toList(),
    reminderMinutes: (j['remind'] as int?) ?? 0,
    overdueMinutes: (j['overdue'] as int?) ?? 0,
    startedAt: j['started'] is int ? DateTime.fromMillisecondsSinceEpoch(j['started']! as int) : null,
    note: (j['note'] as String?) ?? '',
  );

  /// Trip contacts' node IDs, at most [kMaxTripContacts].
  final List<int> contacts;

  /// Remind me to check in this often while the trip is on. 0: never.
  final int reminderMinutes;

  /// Warn me when a trip contact hasn't checked in for this long. 0: never.
  final int overdueMinutes;

  /// When the trip started; null while not on a trip.
  final DateTime? startedAt;

  /// Free text: route, plan, expected return.
  final String note;

  /// Whether a trip is on.
  bool get active => startedAt != null;

  /// A copy with changes. [clearStart] ends the trip.
  TripPlan copyWith({
    List<int>? contacts,
    int? reminderMinutes,
    int? overdueMinutes,
    DateTime? startedAt,
    bool clearStart = false,
    String? note,
  }) => TripPlan(
    contacts: contacts ?? this.contacts,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    overdueMinutes: overdueMinutes ?? this.overdueMinutes,
    startedAt: clearStart ? null : (startedAt ?? this.startedAt),
    note: note ?? this.note,
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'contacts': contacts,
    'remind': reminderMinutes,
    'overdue': overdueMinutes,
    if (startedAt != null) 'started': startedAt!.millisecondsSinceEpoch,
    if (note.isNotEmpty) 'note': note,
  };
}

/// One check-in we sent: what, when, and the message for each contact.
class SentCheckIn {
  /// Creates a record.
  const SentCheckIn({required this.kind, required this.at, required this.messages});

  /// From [toJson].
  factory SentCheckIn.fromJson(Map<String, Object?> j) => SentCheckIn(
    kind: CheckInKind.values.byName(j['kind']! as String),
    at: DateTime.fromMillisecondsSinceEpoch(j['at']! as int),
    messages: {
      for (final MapEntry(:key, :value) in (j['msgs']! as Map<Object?, Object?>).entries)
        int.parse(key! as String): value! as int,
    },
  );

  /// What it said.
  final CheckInKind kind;

  /// When it was sent.
  final DateTime at;

  /// Client message ID by contact node ID, to look up each delivery state.
  final Map<int, int> messages;

  /// With [peer]'s message replaced (a resend).
  SentCheckIn withMessage(int peer, int clientMsgId) =>
      SentCheckIn(kind: kind, at: at, messages: {...messages, peer: clientMsgId});

  /// JSON form.
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'at': at.millisecondsSinceEpoch,
    'msgs': {for (final MapEntry(:key, :value) in messages.entries) '$key': value},
  };
}

/// How a sent check-in fared with one contact.
MsgState? deliveryOf(SentCheckIn c, int peer, Map<int, List<ChatMessage>> messages) {
  final cmid = c.messages[peer];
  if (cmid == null) return null;
  for (final m in (messages[peer] ?? const <ChatMessage>[]).reversed) {
    if (m.outgoing && m.clientMsgId == cmid) return m.state;
  }
  return null; // the message was deleted from this phone
}

/// A trip contact's latest check-in from message history.
(CheckIn, DateTime)? lastCheckInFrom(int peer, Map<int, List<ChatMessage>> messages) {
  for (final m in (messages[peer] ?? const <ChatMessage>[]).reversed) {
    if (m.outgoing) continue;
    final c = parseCheckIn(m.text);
    if (c != null) return (c, m.at);
  }
  return null;
}

/// Whether [peer] is overdue under [plan] at [now]: the trip is on, a limit is
/// set, and its last check-in (or the trip start, if none) is older than that.
bool isOverdue(TripPlan plan, int peer, Map<int, List<ChatMessage>> messages, DateTime now) {
  final start = plan.startedAt;
  if (start == null || plan.overdueMinutes <= 0) return false;
  final last = lastCheckInFrom(peer, messages)?.$2;
  final since = last != null && last.isAfter(start) ? last : start;
  return now.difference(since) > Duration(minutes: plan.overdueMinutes);
}
