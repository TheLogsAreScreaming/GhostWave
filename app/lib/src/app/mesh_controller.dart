/// The app's mesh state: contacts, chats, neighbors, SOS. Fed by node events,
/// changed by user actions, saved per node.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mesh_store.dart';
import '../data/models.dart';
import '../gen/ghostwave.pb.dart' as pb;
import '../link/contact_card.dart';
import '../link/geo.dart';
import '../link/node_link.dart';
import '../link/session.dart';
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
  }) => MeshState(
    nodeId: nodeId ?? this.nodeId,
    contacts: contacts ?? this.contacts,
    messages: messages ?? this.messages,
    neighbors: neighbors ?? this.neighbors,
    alerts: alerts ?? this.alerts,
    ownSos: ownSos ?? this.ownSos,
    ownPos: clearOwnPos ? null : (ownPos ?? this.ownPos),
    unread: unread ?? this.unread,
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
        ),
      },
    );
    _save();
  }

  void _onKeyChange(pb.KeyChange k) {
    final old = state.contacts[k.nodeId] ?? Contact(nodeId: k.nodeId, name: decodeLenient(k.name));
    state = state.copyWith(contacts: {...state.contacts, k.nodeId: old.copyWith(keyChanged: true)});
    _save();
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
    if (session != null) await _deliver(session, msg);
  }

  /// Sends a failed message again.
  Future<void> retry(ChatMessage m) async {
    _replace(m, m.copyWith(state: MsgState.pending, clearError: true));
    final session = _link.session;
    if (session != null) await _deliver(session, m);
  }

  Future<void> _flushOutbox(LinkSession session) async {
    final pending = [
      for (final l in state.messages.values)
        for (final m in l)
          if (m.outgoing && m.state == MsgState.pending) m,
    ]..sort((a, b) => a.at.compareTo(b.at));
    for (final m in pending) {
      if (session.isClosed || !ref.mounted) return;
      await _deliver(session, m);
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
    );
    // a failed write (disk full, app dir gone) must not crash the app; the
    // next change tries again
    unawaited(store.save(id, data).catchError((Object _) {}));
  }

  /// Writes pending changes now (app going to background).
  void flush() => _flushSave();
}
