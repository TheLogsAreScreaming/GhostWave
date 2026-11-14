/// App data: contacts, chat messages, SOS. Plain Dart, JSON-serializable.
library;

import '../link/geo.dart';

/// Where an outgoing DM is.
enum MsgState {
  /// Saved on the phone, not yet accepted by the node (no link, or waiting
  /// for `SendQueued`). Sent automatically when the link is up.
  pending,

  /// The node queued it for the mesh (`SendQueued`).
  sent,

  /// End-to-end receipt (`Delivered`).
  delivered,

  /// The node refused it (e.g. `TOO_LONG`). Can be retried.
  failed,
}

/// One DM, either way.
class ChatMessage {
  /// Creates a message.
  const ChatMessage({
    required this.peer,
    required this.outgoing,
    required this.text,
    required this.at,
    this.state = MsgState.delivered,
    this.clientMsgId = 0,
    this.msgId = 0,
    this.error,
    this.replayed = false,
    this.rssiDbm,
  });

  /// From [toJson].
  factory ChatMessage.fromJson(Map<String, Object?> j) => ChatMessage(
    peer: j['peer']! as int,
    outgoing: j['out']! as bool,
    text: j['text']! as String,
    at: DateTime.fromMillisecondsSinceEpoch(j['at']! as int),
    state: MsgState.values.byName(j['state']! as String),
    clientMsgId: (j['cmid'] as int?) ?? 0,
    msgId: (j['mid'] as int?) ?? 0,
    error: j['err'] as String?,
    replayed: (j['replayed'] as bool?) ?? false,
    rssiDbm: j['rssi'] as int?,
  );

  /// The other node.
  final int peer;

  /// Sent by us.
  final bool outgoing;

  /// The text.
  final String text;

  /// When it was written (outgoing) or received (incoming).
  final DateTime at;

  /// Delivery state (outgoing only; incoming are [MsgState.delivered]).
  final MsgState state;

  /// App-chosen ID (outgoing).
  final int clientMsgId;

  /// Mesh message ID (from `SendQueued`, or the incoming `TextMessage`).
  final int msgId;

  /// Why it failed.
  final String? error;

  /// Incoming message held by the node while no app was connected.
  final bool replayed;

  /// Signal, whole dBm, of the last hop as our node heard it: the message
  /// itself (incoming) or its receipt (outgoing). Null from older nodes.
  final int? rssiDbm;

  /// A copy with some fields changed.
  ChatMessage copyWith({MsgState? state, int? msgId, String? error, bool clearError = false, int? rssiDbm}) =>
      ChatMessage(
        peer: peer,
        outgoing: outgoing,
        text: text,
        at: at,
        state: state ?? this.state,
        clientMsgId: clientMsgId,
        msgId: msgId ?? this.msgId,
        error: clearError ? null : (error ?? this.error),
        replayed: replayed,
        rssiDbm: rssiDbm ?? this.rssiDbm,
      );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'peer': peer,
    'out': outgoing,
    'text': text,
    'at': at.millisecondsSinceEpoch,
    'state': state.name,
    if (clientMsgId != 0) 'cmid': clientMsgId,
    if (msgId != 0) 'mid': msgId,
    if (error != null) 'err': error,
    if (replayed) 'replayed': true,
    'rssi': ?rssiDbm,
  };
}

/// A node we can DM: added by card, or known to the node (IDENT).
class Contact {
  /// Creates a contact.
  const Contact({
    required this.nodeId,
    this.name = '',
    this.ed25519Hex,
    this.pinned = false,
    this.lastSeen,
    this.pos,
    this.keyChanged = false,
    this.pendingKeyHex,
  });

  /// From [toJson].
  factory Contact.fromJson(Map<String, Object?> j) => Contact(
    nodeId: j['id']! as int,
    name: (j['name'] as String?) ?? '',
    ed25519Hex: j['ed'] as String?,
    pinned: (j['pinned'] as bool?) ?? false,
    lastSeen: j['seen'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['seen']! as int),
    pos: j['pos'] == null ? null : LatLon.fromJson((j['pos']! as Map<Object?, Object?>).cast<String, Object?>()),
    keyChanged: (j['keyChanged'] as bool?) ?? false,
    pendingKeyHex: j['pendingKey'] as String?,
  );

  /// Node ID.
  final int nodeId;

  /// Display name (may be empty).
  final String name;

  /// Pinned Ed25519 key, hex, if we know it.
  final String? ed25519Hex;

  /// Key pinned by us (card), not learned over the air.
  final bool pinned;

  /// Last time we heard from it (beacon or DM).
  final DateTime? lastSeen;

  /// Last known position (from its beacons).
  final LatLon? pos;

  /// A signed IDENT carried a different key (the node kept the old one).
  /// The contact counts as unverified until the user accepts or rejects it.
  final bool keyChanged;

  /// The new Ed25519 key from that IDENT (hex), offered for acceptance.
  final String? pendingKeyHex;

  /// Whether the key has been checked: pinned from a card, and no key change
  /// is waiting for a decision.
  bool get verified => pinned && !keyChanged;

  /// A copy with some fields changed.
  Contact copyWith({
    String? name,
    String? ed25519Hex,
    bool? pinned,
    DateTime? lastSeen,
    LatLon? pos,
    bool? keyChanged,
    String? pendingKeyHex,
    bool clearPendingKey = false,
  }) => Contact(
    nodeId: nodeId,
    name: name ?? this.name,
    ed25519Hex: ed25519Hex ?? this.ed25519Hex,
    pinned: pinned ?? this.pinned,
    lastSeen: lastSeen ?? this.lastSeen,
    pos: pos ?? this.pos,
    keyChanged: keyChanged ?? this.keyChanged,
    pendingKeyHex: clearPendingKey ? null : (pendingKeyHex ?? this.pendingKeyHex),
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'id': nodeId,
    if (name.isNotEmpty) 'name': name,
    if (ed25519Hex != null) 'ed': ed25519Hex,
    if (pinned) 'pinned': true,
    if (lastSeen != null) 'seen': lastSeen!.millisecondsSinceEpoch,
    if (pos != null) 'pos': pos!.toJson(),
    if (keyChanged) 'keyChanged': true,
    if (pendingKeyHex != null) 'pendingKey': pendingKeyHex,
  };
}

/// A group channel joined on the node (protocol 1.1).
class GroupChannel {
  /// Creates an entry.
  const GroupChannel({required this.name, required this.pskHex});

  /// From [toJson].
  factory GroupChannel.fromJson(Map<String, Object?> j) =>
      GroupChannel(name: j['name']! as String, pskHex: j['psk']! as String);

  /// Channel name.
  final String name;

  /// Pre-shared key, hex (for the share QR code).
  final String pskHex;

  /// JSON form.
  Map<String, Object?> toJson() => {'name': name, 'psk': pskHex};
}

/// One group channel message, either way. Channels have no delivery receipt,
/// so outgoing messages end at [MsgState.sent].
class ChannelMessage {
  /// Creates a message.
  const ChannelMessage({
    required this.channel,
    required this.outgoing,
    required this.text,
    required this.at,
    this.src = 0,
    this.state = MsgState.delivered,
    this.clientMsgId = 0,
    this.msgId = 0,
    this.error,
    this.replayed = false,
    this.rssiDbm,
  });

  /// From [toJson].
  factory ChannelMessage.fromJson(Map<String, Object?> j) => ChannelMessage(
    channel: j['ch']! as String,
    outgoing: j['out']! as bool,
    text: j['text']! as String,
    at: DateTime.fromMillisecondsSinceEpoch(j['at']! as int),
    src: (j['src'] as int?) ?? 0,
    state: MsgState.values.byName(j['state']! as String),
    clientMsgId: (j['cmid'] as int?) ?? 0,
    msgId: (j['mid'] as int?) ?? 0,
    error: j['err'] as String?,
    replayed: (j['replayed'] as bool?) ?? false,
    rssiDbm: j['rssi'] as int?,
  );

  /// Channel name.
  final String channel;

  /// Sent by us.
  final bool outgoing;

  /// The text.
  final String text;

  /// When it was written (outgoing) or received (incoming).
  final DateTime at;

  /// Sender (incoming).
  final int src;

  /// pending / sent / failed (outgoing); delivered for incoming.
  final MsgState state;

  /// App-chosen ID (outgoing).
  final int clientMsgId;

  /// Mesh message ID.
  final int msgId;

  /// Why it failed.
  final String? error;

  /// Held by the node while no app was connected.
  final bool replayed;

  /// Signal, whole dBm, of the last hop as our node heard it (incoming).
  final int? rssiDbm;

  /// A copy with some fields changed.
  ChannelMessage copyWith({MsgState? state, int? msgId, String? error, bool clearError = false, int? rssiDbm}) =>
      ChannelMessage(
        channel: channel,
        outgoing: outgoing,
        text: text,
        at: at,
        src: src,
        state: state ?? this.state,
        clientMsgId: clientMsgId,
        msgId: msgId ?? this.msgId,
        error: clearError ? null : (error ?? this.error),
        replayed: replayed,
        rssiDbm: rssiDbm ?? this.rssiDbm,
      );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'ch': channel,
    'out': outgoing,
    'text': text,
    'at': at.millisecondsSinceEpoch,
    if (src != 0) 'src': src,
    'state': state.name,
    if (clientMsgId != 0) 'cmid': clientMsgId,
    if (msgId != 0) 'mid': msgId,
    if (error != null) 'err': error,
    if (replayed) 'replayed': true,
    'rssi': ?rssiDbm,
  };
}

/// A node heard nearby (beacon), contact or not. Live only, not saved.
class Neighbor {
  /// Creates an entry.
  const Neighbor({required this.nodeId, required this.lastSeen, this.pos, this.rssiDbm});

  /// Node ID.
  final int nodeId;

  /// When its last beacon arrived.
  final DateTime lastSeen;

  /// Position from the beacon.
  final LatLon? pos;

  /// Signal of its last beacon, whole dBm. Null from older nodes.
  final int? rssiDbm;
}

/// A node's own readings, from the telemetry its beacons carry (client
/// protocol 1.12). Each value is null when that node did not report it: the
/// app never guesses one. Live only, not saved.
class NodeTelemetry {
  /// Creates a reading.
  const NodeTelemetry({required this.nodeId, required this.heardAt, this.batteryPct, this.batteryMv, this.uptime});

  /// The node.
  final int nodeId;

  /// When the beacon that carried it was heard.
  final DateTime heardAt;

  /// Battery charge, 0-100 %.
  final int? batteryPct;

  /// Battery voltage, mV.
  final int? batteryMv;

  /// How long it had been running when that beacon was sent.
  final Duration? uptime;

  /// Its uptime at [now], assuming it has not restarted since [heardAt].
  Duration? uptimeAt(DateTime now) {
    final u = uptime;
    if (u == null) return null;
    final since = now.difference(heardAt);
    return since.isNegative ? u : u + since;
  }

  /// Whether it carries anything at all.
  bool get isEmpty => batteryPct == null && batteryMv == null && uptime == null;
}

/// An SOS from another node.
class SosAlertEntry {
  /// Creates an alert.
  const SosAlertEntry({
    required this.src,
    required this.seq,
    required this.receivedAt,
    this.pos,
    this.accuracyM,
    this.batteryPct,
    this.text = '',
    this.replayed = false,
    this.acked = false,
    this.dismissed = false,
    this.cancelled = false,
    this.cancelVerified = false,
  });

  /// From [toJson].
  factory SosAlertEntry.fromJson(Map<String, Object?> j) => SosAlertEntry(
    src: j['src']! as int,
    seq: j['seq']! as int,
    receivedAt: DateTime.fromMillisecondsSinceEpoch(j['at']! as int),
    pos: j['pos'] == null ? null : LatLon.fromJson((j['pos']! as Map<Object?, Object?>).cast<String, Object?>()),
    accuracyM: j['acc'] as int?,
    batteryPct: j['bat'] as int?,
    text: (j['text'] as String?) ?? '',
    replayed: (j['replayed'] as bool?) ?? false,
    acked: (j['acked'] as bool?) ?? false,
    dismissed: (j['dismissed'] as bool?) ?? false,
    cancelled: (j['cancelled'] as bool?) ?? false,
    cancelVerified: (j['cancelVerified'] as bool?) ?? false,
  );

  /// The node in trouble.
  final int src;

  /// Its SOS sequence number (higher is newer).
  final int seq;

  /// When this app got it.
  final DateTime receivedAt;

  /// Its position; null if it had no fix.
  final LatLon? pos;

  /// Position accuracy, metres (4 m steps).
  final int? accuracyM;

  /// Battery, percent.
  final int? batteryPct;

  /// Its message.
  final String text;

  /// Held by the node while no app was connected: may be old.
  final bool replayed;

  /// We sent an ack.
  final bool acked;

  /// The banner was dismissed (it stays in the SOS list).
  final bool dismissed;

  /// The sender ended this SOS (protocol 1.5).
  final bool cancelled;

  /// The cancel's signature was checked against the sender's key. When false,
  /// the node had no key to check it with, so it is only the sender's claim.
  final bool cancelVerified;

  /// A copy with some fields changed.
  SosAlertEntry copyWith({bool? acked, bool? dismissed, bool? cancelled, bool? cancelVerified}) => SosAlertEntry(
    src: src,
    seq: seq,
    receivedAt: receivedAt,
    pos: pos,
    accuracyM: accuracyM,
    batteryPct: batteryPct,
    text: text,
    replayed: replayed,
    acked: acked ?? this.acked,
    dismissed: dismissed ?? this.dismissed,
    cancelled: cancelled ?? this.cancelled,
    cancelVerified: cancelVerified ?? this.cancelVerified,
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'src': src,
    'seq': seq,
    'at': receivedAt.millisecondsSinceEpoch,
    if (pos != null) 'pos': pos!.toJson(),
    if (accuracyM != null) 'acc': accuracyM,
    if (batteryPct != null) 'bat': batteryPct,
    if (text.isNotEmpty) 'text': text,
    if (replayed) 'replayed': true,
    if (acked) 'acked': true,
    if (dismissed) 'dismissed': true,
    if (cancelled) 'cancelled': true,
    if (cancelVerified) 'cancelVerified': true,
  };
}

/// Someone acknowledged our SOS.
class SosAck {
  /// Creates an ack.
  const SosAck({required this.responder, required this.seq, required this.at});

  /// From [toJson].
  factory SosAck.fromJson(Map<String, Object?> j) => SosAck(
    responder: j['from']! as int,
    seq: j['seq']! as int,
    at: DateTime.fromMillisecondsSinceEpoch(j['at']! as int),
  );

  /// Who acked.
  final int responder;

  /// Which of our SOS sequence numbers.
  final int seq;

  /// When we got it.
  final DateTime at;

  /// JSON form.
  Map<String, Object?> toJson() => {'from': responder, 'seq': seq, 'at': at.millisecondsSinceEpoch};
}

/// Our own SOS.
class OwnSos {
  /// Creates the state.
  const OwnSos({this.active = false, this.text = '', this.startedAt, this.acks = const []});

  /// From [toJson].
  factory OwnSos.fromJson(Map<String, Object?> j) => OwnSos(
    active: (j['active'] as bool?) ?? false,
    text: (j['text'] as String?) ?? '',
    startedAt: j['at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['at']! as int),
    acks: [
      for (final a in (j['acks'] as List<Object?>?) ?? const <Object?>[])
        SosAck.fromJson((a! as Map<Object?, Object?>).cast<String, Object?>()),
    ],
  );

  /// The node is repeating our SOS.
  final bool active;

  /// Our SOS text.
  final String text;

  /// When we raised it.
  final DateTime? startedAt;

  /// Acks received, oldest first.
  final List<SosAck> acks;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'active': active,
    if (text.isNotEmpty) 'text': text,
    if (startedAt != null) 'at': startedAt!.millisecondsSinceEpoch,
    'acks': [for (final a in acks) a.toJson()],
  };
}
