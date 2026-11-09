/// The app's mesh state: contacts, chats, neighbors, SOS. Fed by node events,
/// changed by user actions, saved per node.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mesh_store.dart';
import '../data/message_split.dart';
import '../data/models.dart';
import '../gen/ghostwave.pb.dart' as pb;
import '../link/contact_card.dart';
import '../link/geo.dart';
import '../link/node_link.dart';
import '../link/session.dart';
import 'mesh_alerts.dart';
import 'providers.dart';

/// Largest SOS text the node keeps, in UTF-8 bytes.
const int kMaxSosTextBytes = 60;

/// Everything the screens show about the mesh.
class MeshState {
  /// Creates the state.
  const MeshState({
    this.nodeId,
    this.contacts = const {},
    this.messages = const {},
    this.neighbors = const {},
    this.alerts = const [],
    this.ownSos = const OwnSos(),
    this.ownPos,
    this.unread = const {},
    this.channels = const {},
    this.channelMessages = const {},
    this.channelUnread = const {},
    this.historyProblem = HistoryProblem.none,
  });

  /// The node this history belongs to (null before the first connect).
  final int? nodeId;

  /// Contacts by node ID.
  final Map<int, Contact> contacts;

  /// DMs by peer, oldest first.
  final Map<int, List<ChatMessage>> messages;

  /// Nodes heard nearby (live).
  final Map<int, Neighbor> neighbors;

  /// SOS alerts from others, newest first.
  final List<SosAlertEntry> alerts;

  /// Our SOS.
  final OwnSos ownSos;

  /// Our node's position.
  final LatLon? ownPos;

  /// Unread incoming DMs by peer.
  final Map<int, int> unread;

  /// Group channels joined on the node, by name.
  final Map<String, GroupChannel> channels;

  /// Channel messages by channel, oldest first.
  final Map<String, List<ChannelMessage>> channelMessages;

  /// Unread channel messages by channel.
  final Map<String, int> channelUnread;

  /// Why this node's saved history did not load, if it didn't.
  final HistoryProblem historyProblem;

  /// All unread DMs and channel messages.
  int get totalUnread => unread.values.fold(0, (a, b) => a + b) + channelUnread.values.fold(0, (a, b) => a + b);

  /// Alerts that still want the banner.
  List<SosAlertEntry> get activeAlerts => [
    for (final a in alerts)
      if (!a.acked && !a.dismissed) a,
  ];

  /// A display name for [id].
  String nameOf(int id) {
    final n = contacts[id]?.name ?? '';
    return n.isEmpty ? nodeIdHex(id) : n;
  }

  /// A copy with some fields changed.
  MeshState copyWith({
    int? nodeId,
    Map<int, Contact>? contacts,
    Map<int, List<ChatMessage>>? messages,
    Map<int, Neighbor>? neighbors,
    List<SosAlertEntry>? alerts,
    OwnSos? ownSos,
    LatLon? ownPos,
    bool clearOwnPos = false,
    Map<int, int>? unread,
    Map<String, GroupChannel>? channels,
    Map<String, List<ChannelMessage>>? channelMessages,
    Map<String, int>? channelUnread,
  }) => MeshState(
    nodeId: nodeId ?? this.nodeId,
    contacts: contacts ?? this.contacts,
    messages: messages ?? this.messages,
    neighbors: neighbors ?? this.neighbors,
    alerts: alerts ?? this.alerts,
    ownSos: ownSos ?? this.ownSos,
    ownPos: clearOwnPos ? null : (ownPos ?? this.ownPos),
    unread: unread ?? this.unread,
    channels: channels ?? this.channels,
    channelMessages: channelMessages ?? this.channelMessages,
    channelUnread: channelUnread ?? this.channelUnread,
    historyProblem: historyProblem,
  );
}

/// Where history files live; overridden in `main` (app support dir) and tests.
final meshStoreProvider = Provider<MeshStore?>((ref) => null);

/// Clock, so tests can pin time.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The mesh state and the actions on it.
final meshProvider = NotifierProvider<MeshController, MeshState>(MeshController.new);

/// Keeps [MeshState] in step with the node.
class MeshController extends Notifier<MeshState> {
  final Random _rng = Random.secure();
  final Set<int> _inFlight = <int>{};
  Timer? _saveTimer;
  bool _syncing = false;
  MeshStore? _store;
  // the latest state, readable in onDispose (where `state` is off limits)
  MeshState _snap = const MeshState();

  NodeLink get _link => ref.read(nodeLinkProvider);
  DateTime _now() => ref.read(clockProvider)();

  @override
  MeshState build() {
    final link = ref.watch(nodeLinkProvider);
    _store = ref.watch(meshStoreProvider);
    listenSelf((_, next) => _snap = next);
    final evSub = link.events.listen(_onEvent);
    final stSub = link.states.listen(_onState);
    ref.onDispose(() {
      unawaited(evSub.cancel());
      unawaited(stSub.cancel());
      _flushSave();
    });
    if (link.state case final LinkUp up) scheduleMicrotask(() => _onState(up));
    return const MeshState();
  }

  // ------------------------------------------------------------ link state --

  Future<void> _onState(LinkState s) async {
    if (s is! LinkUp) return;
    final id = s.info.nodeId;
    if (state.nodeId != id) {
      _flushSave();
      final store = _store;
      final saved = store == null ? const StoredMesh() : await store.load(id);
      if (!ref.mounted) return;
      state = MeshState(
        nodeId: id,
        contacts: saved.contacts,
        messages: saved.messages,
        alerts: saved.alerts,
        ownSos: saved.ownSos,
        channels: saved.channels,
        channelMessages: saved.channelMessages,
        historyProblem: saved.problem,
      );
    }
    await _sync(s.session);
  }

  /// After every (re)connect: contacts, own position, SOS state, outbox.
  Future<void> _sync(LinkSession session) async {
    if (_syncing) return;
    _syncing = true;
    try {
      await refreshContacts();
      if (!ref.mounted) return;
      await refreshChannels();
      if (!ref.mounted) return;
      try {
        final r = await session.request(pb.ToRadio(getPosition: pb.GetPosition()));
        if (!ref.mounted) return;
        state = r.position.hasPos()
            ? state.copyWith(ownPos: LatLon.fromProto(r.position.pos))
            : state.copyWith(clearOwnPos: true);
      } on Object {
        // not fatal
      }
      try {
        final r = await session.request(pb.ToRadio(getStatus: pb.GetStatus()));
        if (!ref.mounted) return;
        if (state.ownSos.active != r.status.sosActive) {
          state = state.copyWith(
            ownSos: OwnSos(
              active: r.status.sosActive,
              text: state.ownSos.text,
              startedAt: state.ownSos.startedAt,
              acks: state.ownSos.acks,
            ),
          );
          _save();
        }
      } on Object {
        // not fatal
      }
      if (!ref.mounted) return;
      await _flushOutbox(session);
    } finally {
      _syncing = false;
    }
  }

  /// Reloads the node's contact list and merges it with ours.
  Future<void> refreshContacts() async {
    final session = _link.session;
    if (session == null) return;
    final List<pb.Contact> list;
    try {
      list = await session.listContacts();
    } on Object {
      return;
    }
    if (!ref.mounted) return;
    final known = state.contacts.keys.toSet();
    final contacts = Map<int, Contact>.of(state.contacts);
    for (final c in list) {
      final old = contacts[c.nodeId];
      final nodeName = decodeLenient(c.name);
      contacts[c.nodeId] = (old ?? Contact(nodeId: c.nodeId)).copyWith(
        name: (old?.name.isNotEmpty ?? false) ? old!.name : nodeName,
        pinned: c.pinned || (old?.pinned ?? false),
        ed25519Hex: c.ed25519Pub.length == 32 ? hexEncode(c.ed25519Pub) : old?.ed25519Hex,
      );
    }
    state = state.copyWith(contacts: contacts);
    _save();
    _releaseHeld(session, contacts.keys.where((id) => !known.contains(id)));
  }

  // ---------------------------------------------------------------- events --

  void _onEvent(pb.FromRadio e) {
    switch (e.whichEvent()) {
      case pb.FromRadio_Event.text:
        _onText(e.text, replayed: e.replayed);
      case pb.FromRadio_Event.delivered:
        _onDelivered(e.delivered);
      case pb.FromRadio_Event.sos:
        _onSos(e.sos, replayed: e.replayed);
      case pb.FromRadio_Event.sosAck:
        _onSosAck(e.sosAck);
      case pb.FromRadio_Event.neighbor:
        _onNeighbor(e.neighbor);
      case pb.FromRadio_Event.peerIdent:
        _onPeerIdent(e.peerIdent);
      case pb.FromRadio_Event.keyChange:
        _onKeyChange(e.keyChange);
      case pb.FromRadio_Event.channelMessage:
        _onChannelMessage(e.channelMessage, replayed: e.replayed);
      case pb.FromRadio_Event.position:
        state = e.position.hasPos()
            ? state.copyWith(ownPos: LatLon.fromProto(e.position.pos))
            : state.copyWith(clearOwnPos: true);
      default:
        break;
    }
  }

  void _onText(pb.TextMessage t, {required bool replayed}) {
    final thread = state.messages[t.src] ?? const <ChatMessage>[];
    // de-duplicate by (src, msg_id): a replayed message may already be here
    if (thread.any((m) => !m.outgoing && m.msgId == t.msgId)) return;
    final msg = ChatMessage(
      peer: t.src,
      outgoing: false,
      text: decodeLenient(t.text),
      at: _now(),
      msgId: t.msgId,
      replayed: replayed,
    );
    final contacts = Map<int, Contact>.of(state.contacts);
    contacts[t.src] = (contacts[t.src] ?? Contact(nodeId: t.src)).copyWith(lastSeen: _now());
    state = state.copyWith(
      messages: {
        ...state.messages,
        t.src: [...thread, msg],
      },
      contacts: contacts,
      unread: {...state.unread, t.src: (state.unread[t.src] ?? 0) + 1},
    );
    _save();
    if (!ref.read(appForegroundProvider)) {
      unawaited(
        ref
            .read(meshAlertsProvider)
            .textReceived(peer: t.src, from: state.nameOf(t.src), text: msg.text)
            .catchError((Object _) {}),
      );
    }
  }

  void _onDelivered(pb.Delivered d) {
    final thread = state.messages[d.dest];
    if (thread == null) return;
    var changed = false;
    final updated = [
      for (final m in thread)
        if (m.outgoing &&
            m.state != MsgState.delivered &&
            ((d.clientMsgId != 0 && m.clientMsgId == d.clientMsgId) || (d.msgId != 0 && m.msgId == d.msgId)))
          () {
            changed = true;
            return m.copyWith(state: MsgState.delivered, msgId: d.msgId == 0 ? null : d.msgId);
          }()
        else
          m,
    ];
    if (!changed) return; // receipts can repeat: idempotent
    state = state.copyWith(messages: {...state.messages, d.dest: updated});
    _save();
  }

  void _onSos(pb.SosAlert a, {required bool replayed}) {
    final existing = state.alerts.where((x) => x.src == a.src).firstOrNull;
    if (existing != null && existing.seq >= a.seq) return;
    // a new SOS from this node (re-sends with a higher seq update it quietly)
    if (existing == null && !ref.read(appForegroundProvider)) {
      unawaited(
        ref
            .read(meshAlertsProvider)
            .sosReceived(src: a.src, from: state.nameOf(a.src), text: decodeLenient(a.text))
            .catchError((Object _) {}),
      );
    }
    final entry = SosAlertEntry(
      src: a.src,
      seq: a.seq,
      receivedAt: _now(),
      pos: a.hasPos() ? LatLon.fromProto(a.pos) : null,
      accuracyM: a.hasAccuracyM() ? a.accuracyM : null,
      batteryPct: a.hasBatteryPct() ? a.batteryPct : null,
      text: decodeLenient(a.text),
      replayed: replayed,
    );
    state = state.copyWith(
      alerts: [
        entry,
        for (final x in state.alerts)
          if (x.src != a.src) x,
      ],
    );
    _save();
  }

  void _onSosAck(pb.SosAckReceived a) {
    final own = state.ownSos;
    if (own.acks.any((x) => x.responder == a.responder && x.seq == a.seq)) return;
    state = state.copyWith(
      ownSos: OwnSos(
        active: own.active,
        text: own.text,
        startedAt: own.startedAt,
        acks: [
          ...own.acks,
          SosAck(responder: a.responder, seq: a.seq, at: _now()),
        ],
      ),
    );
    _save();
  }

  void _onNeighbor(pb.Neighbor n) {
    final pos = n.hasPos() ? LatLon.fromProto(n.pos) : null;
    final now = _now();
    state = state.copyWith(
      neighbors: {
        ...state.neighbors,
        n.nodeId: Neighbor(nodeId: n.nodeId, lastSeen: now, pos: pos ?? state.neighbors[n.nodeId]?.pos),
      },
      contacts: state.contacts.containsKey(n.nodeId)
          ? {...state.contacts, n.nodeId: state.contacts[n.nodeId]!.copyWith(lastSeen: now, pos: pos)}
          : null,
    );
    if (state.contacts.containsKey(n.nodeId)) _save();
  }

  void _onPeerIdent(pb.PeerIdent p) {
    final old = state.contacts[p.nodeId];
    final name = decodeLenient(p.name);
    state = state.copyWith(
      contacts: {
        ...state.contacts,
        p.nodeId: (old ?? Contact(nodeId: p.nodeId)).copyWith(
          name: (old?.name.isNotEmpty ?? false) ? old!.name : name,
          lastSeen: _now(),
          ed25519Hex: p.ed25519Pub.length == 32 ? hexEncode(p.ed25519Pub) : old?.ed25519Hex,
        ),
      },
    );
    _save();
    final session = _link.session;
    if (old == null && session != null) _releaseHeld(session, [p.nodeId]);
  }

  void _onKeyChange(pb.KeyChange k) {
    final old = state.contacts[k.nodeId] ?? Contact(nodeId: k.nodeId, name: decodeLenient(k.name));
    state = state.copyWith(
      contacts: {
        ...state.contacts,
        k.nodeId: old.copyWith(
          keyChanged: true,
          pendingKeyHex: k.ed25519Pub.length == 32 ? hexEncode(k.ed25519Pub) : null,
        ),
      },
    );
    _save();
  }

  void _onChannelMessage(pb.ChannelMessage c, {required bool replayed}) {
    final thread = state.channelMessages[c.channel] ?? const <ChannelMessage>[];
    if (thread.any((m) => !m.outgoing && m.src == c.src && m.msgId == c.msgId)) return;
    final msg = ChannelMessage(
      channel: c.channel,
      outgoing: false,
      src: c.src,
      text: decodeLenient(c.text),
      at: _now(),
      msgId: c.msgId,
      replayed: replayed,
    );
    state = state.copyWith(
      channelMessages: {
        ...state.channelMessages,
        c.channel: [...thread, msg],
      },
      channelUnread: {...state.channelUnread, c.channel: (state.channelUnread[c.channel] ?? 0) + 1},
    );
    _save();
    if (!ref.read(appForegroundProvider)) {
      unawaited(
        ref
            .read(meshAlertsProvider)
            .textReceived(
              // one notification per channel, kept apart from the sender's DMs
              peer: c.channel.hashCode | 0x20000000,
              from: '#${c.channel} · ${state.nameOf(c.src)}',
              text: msg.text,
            )
            .catchError((Object _) {}),
      );
    }
  }

  // --------------------------------------------------------------- actions --

  /// Adds a contact from a card. Throws [NodeError] (e.g. `KEY_REJECTED`) or
  /// [StateError] when not connected.
  Future<void> addContact(ContactCard card) async {
    final session = _link.session;
    if (session == null) throw StateError('Not connected to a node');
    await session.request(
      pb.ToRadio(
        addContact: pb.AddContact(nodeId: card.nodeId, ed25519Pub: card.ed25519Pub, name: card.name),
      ),
    );
    if (!ref.mounted) return;
    final old = state.contacts[card.nodeId];
    state = state.copyWith(
      contacts: {
        ...state.contacts,
        card.nodeId: (old ?? Contact(nodeId: card.nodeId)).copyWith(
          name: card.name.isNotEmpty ? card.name : old?.name,
          ed25519Hex: hexEncode(card.ed25519Pub),
          pinned: true,
          keyChanged: false,
          clearPendingKey: true,
        ),
      },
    );
    _save();
    unawaited(refreshContacts());
  }

  /// Queues a DM to [peer]. It is sent now if the link is up, else on the next
  /// connect.
  Future<void> sendText(int peer, String text) async {
    final cmid = 1 + _rng.nextInt(0x7FFFFFFE);
    final msg = ChatMessage(
      peer: peer,
      outgoing: true,
      text: text,
      at: _now(),
      state: MsgState.pending,
      clientMsgId: cmid,
    );
    state = state.copyWith(
      messages: {
        ...state.messages,
        peer: [...?state.messages[peer], msg],
      },
    );
    _save();
    final session = _link.session;
    if (session == null) return;
    if (!_hasKey(peer)) {
      // never hand it to the node: with no key it would not be sealed for this peer
      unawaited(requestKey(peer).then<void>((_) {}, onError: (Object _) {}));
      return;
    }
    await _deliver(session, msg);
  }

  bool _hasKey(int peer) => state.contacts.containsKey(peer);

  /// Whether the connected node can ask a heard node for its key (protocol 1.4).
  bool get nodeCanRequestKey {
    final s = _link.state;
    return s is LinkUp && s.info.protocolMinor >= 4 && !s.info.legacy;
  }

  /// Asks a node in radio range for its key now. Returning means the node asked,
  /// not that the key came: it arrives later as a contact. Throws [NodeError].
  Future<void> requestKey(int peer) async {
    final session = _link.session;
    if (session == null || !nodeCanRequestKey) return;
    await session.request(pb.ToRadio(requestKey: pb.RequestKey(nodeId: peer)));
  }

  /// Sends what was held for [peers], whose keys the node now has.
  void _releaseHeld(LinkSession session, Iterable<int> peers) {
    for (final peer in peers) {
      for (final m in state.messages[peer] ?? const <ChatMessage>[]) {
        if (m.outgoing && m.state == MsgState.pending) unawaited(_deliver(session, m));
      }
    }
  }

  /// Sends [text], in labelled parts if it is too long for one radio message.
  /// Each part is its own message, with its own delivery state and retry.
  Future<void> sendMessage(int peer, String text, int maxBytes) async {
    for (final part in splitMessage(text, maxBytes)) {
      await sendText(peer, part);
    }
  }

  /// Sends a failed message again.
  Future<void> retry(ChatMessage m) async {
    _replace(m, m.copyWith(state: MsgState.pending, clearError: true));
    final session = _link.session;
    if (session != null && _hasKey(m.peer)) await _deliver(session, m);
  }

  Future<void> _flushOutbox(LinkSession session) async {
    final pending = [
      for (final l in state.messages.values)
        for (final m in l)
          if (m.outgoing && m.state == MsgState.pending && _hasKey(m.peer)) m,
    ]..sort((a, b) => a.at.compareTo(b.at));
    for (final m in pending) {
      if (session.isClosed || !ref.mounted) return;
      await _deliver(session, m);
    }
    final pendingChannel = [
      for (final l in state.channelMessages.values)
        for (final m in l)
          if (m.outgoing && m.state == MsgState.pending) m,
    ]..sort((a, b) => a.at.compareTo(b.at));
    for (final m in pendingChannel) {
      if (session.isClosed || !ref.mounted) return;
      await _deliverChannel(session, m);
    }
  }

  Future<void> _deliver(LinkSession session, ChatMessage m) async {
    if (!_inFlight.add(m.clientMsgId)) return;
    try {
      final r = await session.request(
        pb.ToRadio(
          sendText: pb.SendText(dest: m.peer, text: utf8.encode(m.text), clientMsgId: m.clientMsgId),
        ),
      );
      _update(
        m,
        (cur) => cur.state == MsgState.delivered ? cur : cur.copyWith(state: MsgState.sent, msgId: r.sendQueued.msgId),
      );
    } on NodeError catch (e) {
      _update(m, (cur) => cur.copyWith(state: MsgState.failed, error: e.message));
    } on Object {
      // link dropped or timed out: stays pending, sent again on reconnect
    } finally {
      _inFlight.remove(m.clientMsgId);
    }
  }

  void _update(ChatMessage m, ChatMessage Function(ChatMessage) f) {
    if (!ref.mounted) return;
    final thread = state.messages[m.peer];
    if (thread == null) return;
    final updated = [for (final x in thread) x.clientMsgId == m.clientMsgId && x.outgoing ? f(x) : x];
    state = state.copyWith(messages: {...state.messages, m.peer: updated});
    _save();
  }

  void _replace(ChatMessage old, ChatMessage now) => _update(old, (_) => now);

  /// Removes one DM from the history (on this phone only).
  void deleteMessage(ChatMessage m) {
    final thread = state.messages[m.peer];
    if (thread == null) return;
    state = state.copyWith(
      messages: {
        ...state.messages,
        m.peer: [
          for (final x in thread)
            if (!identical(x, m)) x,
        ],
      },
    );
    _save();
  }

  /// Deletes the whole conversation with [peer] (on this phone only).
  void deleteThread(int peer) {
    state = state.copyWith(messages: {...state.messages}..remove(peer), unread: {...state.unread}..remove(peer));
    _save();
  }

  /// Accepts the new key a contact announced (KeyChange): the node pins it.
  /// Throws [NodeError] or [StateError] when not connected.
  Future<void> acceptKeyChange(int peer) async {
    final c = state.contacts[peer];
    final key = c?.pendingKeyHex == null ? null : hexDecode(c!.pendingKeyHex!);
    if (c == null || key == null || key.length != 32) throw StateError('No new key to accept');
    await addContact(ContactCard(nodeId: peer, ed25519Pub: key, name: c.name));
  }

  /// Keeps the old key (the node already does) and hides the warning. The
  /// contact stays unverified until its QR code is scanned again.
  void rejectKeyChange(int peer) {
    final c = state.contacts[peer];
    if (c == null) return;
    state = state.copyWith(
      contacts: {...state.contacts, peer: c.copyWith(keyChanged: false, pinned: false, clearPendingKey: true)},
    );
    _save();
  }

  // -------------------------------------------------------------- channels --

  /// Whether the connected node speaks protocol 1.1 (channels, SetName).
  bool get nodeSupportsChannels {
    final s = _link.state;
    return s is LinkUp && s.info.protocolMinor >= 1 && s.info.maxChannelTextBytes > 0;
  }

  /// Reloads the node's channel list (protocol 1.1 nodes only).
  Future<void> refreshChannels() async {
    final session = _link.session;
    if (session == null || !nodeSupportsChannels) return;
    final List<pb.Channel> list;
    try {
      list = await session.listChannels();
      // radio firmware keeps channels in RAM: after a reboot, join them again
      final firmware = (_link.state as LinkUp).info.firmware;
      if (firmware.startsWith('ghostwave-')) {
        final held = {for (final c in list) c.name};
        for (final c in state.channels.values) {
          if (held.contains(c.name)) continue;
          final psk = hexDecode(c.pskHex);
          if (psk == null) continue;
          await session.request(
            pb.ToRadio(
              addChannel: pb.AddChannel(name: c.name, psk: psk),
            ),
          );
          list.add(pb.Channel(name: c.name, psk: psk));
        }
      }
    } on Object {
      return;
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      channels: {for (final c in list) c.name: GroupChannel(name: c.name, pskHex: hexEncode(c.psk))},
    );
    _save();
  }

  /// Joins [card]'s channel on the node. Throws [NodeError] / [StateError].
  Future<void> joinChannel(ChannelCard card) async {
    final session = _link.session;
    if (session == null) throw StateError('Not connected to a node');
    if (!nodeSupportsChannels) throw StateError('Group channels are not available on this node.');
    await session.request(
      pb.ToRadio(
        addChannel: pb.AddChannel(name: card.name, psk: card.psk),
      ),
    );
    if (!ref.mounted) return;
    state = state.copyWith(
      channels: {
        ...state.channels,
        card.name: GroupChannel(name: card.name, pskHex: hexEncode(card.psk)),
      },
    );
    _save();
    unawaited(refreshChannels());
  }

  /// Makes a new channel with a random key and joins it.
  Future<ChannelCard> createChannel(String name) async {
    final psk = Uint8List.fromList(List<int>.generate(32, (_) => _rng.nextInt(256)));
    final card = ChannelCard(name: name, psk: psk);
    await joinChannel(card);
    return card;
  }

  /// Leaves [name] on the node; the history on this phone is deleted too.
  Future<void> leaveChannel(String name) async {
    final session = _link.session;
    if (session == null) throw StateError('Not connected to a node');
    try {
      await session.request(pb.ToRadio(removeChannel: pb.RemoveChannel(name: name)));
    } on NodeError catch (e) {
      if (e.code != pb.Error_Code.NOT_FOUND) rethrow;
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      channels: {...state.channels}..remove(name),
      channelMessages: {...state.channelMessages}..remove(name),
      channelUnread: {...state.channelUnread}..remove(name),
    );
    _save();
  }

  /// Queues a channel message; sent now if the link is up, else on reconnect.
  Future<void> sendChannelText(String channel, String text) async {
    final msg = ChannelMessage(
      channel: channel,
      outgoing: true,
      text: text,
      at: _now(),
      state: MsgState.pending,
      clientMsgId: 1 + _rng.nextInt(0x7FFFFFFE),
    );
    state = state.copyWith(
      channelMessages: {
        ...state.channelMessages,
        channel: [...?state.channelMessages[channel], msg],
      },
    );
    _save();
    final session = _link.session;
    if (session != null) await _deliverChannel(session, msg);
  }

  /// Sends a failed channel message again.
  Future<void> retryChannel(ChannelMessage m) async {
    _updateChannel(m, (cur) => cur.copyWith(state: MsgState.pending, clearError: true));
    final session = _link.session;
    if (session != null) await _deliverChannel(session, m);
  }

  Future<void> _deliverChannel(LinkSession session, ChannelMessage m) async {
    if (!_inFlight.add(m.clientMsgId)) return;
    try {
      final r = await session.request(
        pb.ToRadio(
          sendChannelText: pb.SendChannelText(
            channel: m.channel,
            text: utf8.encode(m.text),
            clientMsgId: m.clientMsgId,
          ),
        ),
      );
      _updateChannel(m, (cur) => cur.copyWith(state: MsgState.sent, msgId: r.sendQueued.msgId));
    } on NodeError catch (e) {
      _updateChannel(m, (cur) => cur.copyWith(state: MsgState.failed, error: e.message));
    } on Object {
      // link dropped or timed out: stays pending, sent again on reconnect
    } finally {
      _inFlight.remove(m.clientMsgId);
    }
  }

  void _updateChannel(ChannelMessage m, ChannelMessage Function(ChannelMessage) f) {
    if (!ref.mounted) return;
    final thread = state.channelMessages[m.channel];
    if (thread == null) return;
    final updated = [for (final x in thread) x.clientMsgId == m.clientMsgId && x.outgoing ? f(x) : x];
    state = state.copyWith(channelMessages: {...state.channelMessages, m.channel: updated});
    _save();
  }

  /// Clears [channel]'s unread count.
  void markChannelRead(String channel) {
    if ((state.channelUnread[channel] ?? 0) == 0) return;
    state = state.copyWith(channelUnread: {...state.channelUnread, channel: 0});
  }

  /// Removes one channel message from the history (on this phone only).
  void deleteChannelMessage(ChannelMessage m) {
    final thread = state.channelMessages[m.channel];
    if (thread == null) return;
    state = state.copyWith(
      channelMessages: {
        ...state.channelMessages,
        m.channel: [
          for (final x in thread)
            if (!identical(x, m)) x,
        ],
      },
    );
    _save();
  }

  /// Deletes [channel]'s history on this phone (stays joined).
  void clearChannelHistory(String channel) {
    state = state.copyWith(
      channelMessages: {...state.channelMessages}..remove(channel),
      channelUnread: {...state.channelUnread}..remove(channel),
    );
    _save();
  }

  // ------------------------------------------------------------ node name --

  /// Renames the node (`SetName`, protocol 1.1) and refreshes its `NodeInfo`.
  Future<void> setNodeName(String name) async {
    final session = _link.session;
    if (session == null) throw StateError('Not connected to a node');
    final s = _link.state;
    if (s is! LinkUp || s.info.protocolMinor < 1 || s.info.legacy) {
      throw StateError('This node cannot be renamed from the app.');
    }
    await session.request(pb.ToRadio(setName: pb.SetName(name: name)));
    await _link.rehello();
  }

  /// Records our own position after the app sent it (`SetOwnPosition`).
  void noteOwnPosition(LatLon p) => state = state.copyWith(ownPos: p);

  /// Clears [peer]'s unread count.
  void markRead(int peer) {
    if ((state.unread[peer] ?? 0) == 0) return;
    state = state.copyWith(unread: {...state.unread, peer: 0});
  }

  /// Raises (or updates) our SOS. Throws [NodeError] (e.g. `RATE_LIMITED`).
  Future<void> startSos(String text) async {
    final session = _link.session;
    if (session == null) throw StateError('Not connected to a node');
    final t = truncateUtf8(text.trim(), kMaxSosTextBytes);
    await session.request(pb.ToRadio(sosStart: pb.SosStart(text: utf8.encode(t))));
    if (!ref.mounted) return;
    final own = state.ownSos;
    state = state.copyWith(
      ownSos: OwnSos(
        active: true,
        text: t,
        startedAt: own.active ? own.startedAt : _now(),
        acks: own.active ? own.acks : const [],
      ),
    );
    _save();
  }

  /// Stops our SOS.
  Future<void> stopSos() async {
    final session = _link.session;
    if (session == null) throw StateError('Not connected to a node');
    await session.request(pb.ToRadio(sosStop: pb.SosStop()));
    if (!ref.mounted) return;
    final own = state.ownSos;
    state = state.copyWith(
      ownSos: OwnSos(text: own.text, startedAt: own.startedAt, acks: own.acks),
    );
    _save();
  }

  /// Acknowledges [src]'s SOS. Throws [NodeError] (`NOT_FOUND`).
  Future<void> ackSos(int src) async {
    final session = _link.session;
    if (session == null) throw StateError('Not connected to a node');
    await session.request(pb.ToRadio(sosAck: pb.SosAck(nodeId: src)));
    if (!ref.mounted) return;
    _setAlert(src, (a) => a.copyWith(acked: true));
  }

  /// Hides [src]'s banner (the alert stays on the SOS screen).
  void dismissAlert(int src) => _setAlert(src, (a) => a.copyWith(dismissed: true));

  void _setAlert(int src, SosAlertEntry Function(SosAlertEntry) f) {
    state = state.copyWith(alerts: [for (final a in state.alerts) a.src == src ? f(a) : a]);
    _save();
  }

  // ----------------------------------------------------------- persistence --

  void _save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _flushSave);
  }

  void _flushSave() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final id = _snap.nodeId;
    final store = _store;
    if (id == null || store == null) return;
    final data = StoredMesh(
      contacts: _snap.contacts,
      messages: _snap.messages,
      alerts: _snap.alerts,
      ownSos: _snap.ownSos,
      channels: _snap.channels,
      channelMessages: _snap.channelMessages,
    );
    // a failed write (disk full, app dir gone) must not crash the app; the
    // next change tries again
    unawaited(store.save(id, data).catchError((Object _) {}));
  }

  /// Writes pending changes now (app going to background).
  void flush() => _flushSave();

  /// Forgets everything on this phone (app data reset): saved histories are
  /// deleted and the state is emptied. The node keeps its own data.
  Future<void> resetLocalData() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _store?.deleteAll();
    if (!ref.mounted) return;
    state = const MeshState();
  }

  /// Replaces all saved history with [nodes] (restore). The link must be down;
  /// the matching history loads on the next connect.
  Future<void> replaceLocalData(Map<String, Map<String, Object?>> nodes) async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _store?.replaceAll(nodes);
    if (!ref.mounted) return;
    state = const MeshState();
  }
}
