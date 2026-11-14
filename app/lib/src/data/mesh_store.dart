/// Local history, one encrypted file per node ID, so chats survive a restart
/// and connecting to a different node does not mix histories.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../link/contact_card.dart';
import 'history_crypto.dart';
import 'models.dart';
import 'node_journal.dart';
import 'timeline.dart';
import 'team_trails.dart';
import 'waypoints.dart';

/// Trails from [toJson]'s `trails`; anything malformed is dropped.
Map<int, List<TrailFix>> _trailsFromJson(Object? j) {
  final out = <int, List<TrailFix>>{};
  if (j is! Map) return out;
  for (final MapEntry(:key, :value) in j.entries) {
    final id = int.tryParse('$key');
    if (id == null || value is! List) continue;
    final fixes = <TrailFix>[];
    for (final p in value) {
      final f = TrailFix.fromJson(p);
      if (f != null) fixes.add(f);
    }
    if (fixes.isNotEmpty) out[id] = fixes;
  }
  return out;
}

/// Why a node's saved history did not load.
enum HistoryProblem {
  /// It loaded, or there was none.
  none,

  /// The phone did not release the key. The file is untouched and new changes
  /// are not saved, so a later start can still open it.
  locked,

  /// The file is damaged, or the key that sealed it is gone. It was set aside.
  unreadable,
}

/// What is saved for one node.
class StoredMesh {
  /// Creates the snapshot.
  const StoredMesh({
    this.contacts = const {},
    this.messages = const {},
    this.alerts = const [],
    this.ownSos = const OwnSos(),
    this.channels = const {},
    this.channelMessages = const {},
    this.drafts = const {},
    this.trails = const {},
    this.journal = const NodeJournal(),
    this.signalLog = const [],
    this.waypoints = const WaypointBook(),
    this.problem = HistoryProblem.none,
  });

  /// From [toJson].
  factory StoredMesh.fromJson(Map<String, Object?> j) {
    Map<String, Object?> m(Object? o) => (o! as Map<Object?, Object?>).cast<String, Object?>();
    final contacts = <int, Contact>{
      for (final c in (j['contacts'] as List<Object?>?) ?? const <Object?>[])
        if (Contact.fromJson(m(c)) case final ct) ct.nodeId: ct,
    };
    final messages = <int, List<ChatMessage>>{};
    for (final x in (j['messages'] as List<Object?>?) ?? const <Object?>[]) {
      final msg = ChatMessage.fromJson(m(x));
      (messages[msg.peer] ??= <ChatMessage>[]).add(msg);
    }
    final channelMessages = <String, List<ChannelMessage>>{};
    for (final x in (j['channelMessages'] as List<Object?>?) ?? const <Object?>[]) {
      final msg = ChannelMessage.fromJson(m(x));
      (channelMessages[msg.channel] ??= <ChannelMessage>[]).add(msg);
    }
    return StoredMesh(
      contacts: contacts,
      messages: messages,
      alerts: [for (final a in (j['alerts'] as List<Object?>?) ?? const <Object?>[]) SosAlertEntry.fromJson(m(a))],
      ownSos: j['ownSos'] == null ? const OwnSos() : OwnSos.fromJson(m(j['ownSos'])),
      channels: {
        for (final c in (j['channels'] as List<Object?>?) ?? const <Object?>[])
          if (GroupChannel.fromJson(m(c)) case final ch) ch.name: ch,
      },
      channelMessages: channelMessages,
      drafts: (j['drafts'] as Map<Object?, Object?>? ?? const {}).map(
        (k, v) => MapEntry(int.parse(k as String), v as String),
      ),
      trails: _trailsFromJson(j['trails']),
      journal: NodeJournal.fromJson(j['journal']),
      signalLog: signalLogFromJson(j['signal']),
      waypoints: WaypointBook.fromJson(j['waypoints']),
    );
  }

  /// Contacts by node ID.
  final Map<int, Contact> contacts;

  /// DMs by peer, oldest first.
  final Map<int, List<ChatMessage>> messages;

  /// SOS alerts from others.
  final List<SosAlertEntry> alerts;

  /// Our SOS.
  final OwnSos ownSos;

  /// Group channels, by name (as last listed by the node).
  final Map<String, GroupChannel> channels;

  /// Channel messages by channel, oldest first.
  final Map<String, List<ChannelMessage>> channelMessages;

  /// Unsent DM text, encrypted with the node's history.
  final Map<int, String> drafts;

  /// 24-hour trails of trip contacts and this node, oldest point first.
  final Map<int, List<TrailFix>> trails;

  /// Every node heard while connected to this node.
  final NodeJournal journal;

  /// Signal changes of heard nodes, oldest first (for the timeline).
  final List<SignalShift> signalLog;

  /// Waypoints, ours and others'.
  final WaypointBook waypoints;

  /// Why this snapshot is empty, if the saved one could not be read. Not saved.
  final HistoryProblem problem;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'version': 1,
    'contacts': [for (final c in contacts.values) c.toJson()],
    'messages': [
      for (final l in messages.values)
        for (final msg in l) msg.toJson(),
    ],
    'alerts': [for (final a in alerts) a.toJson()],
    'ownSos': ownSos.toJson(),
    'channels': [for (final c in channels.values) c.toJson()],
    'drafts': {for (final e in drafts.entries) '${e.key}': e.value},
    if (trails.isNotEmpty)
      'trails': {
        for (final e in trails.entries) '${e.key}': [for (final p in e.value) p.toJson()],
      },
    'channelMessages': [
      for (final l in channelMessages.values)
        for (final msg in l) msg.toJson(),
    ],
    if (!journal.isEmpty) 'journal': journal.toJson(),
    if (signalLog.isNotEmpty) 'signal': [for (final x in signalLog) x.toJson()],
    if (!waypoints.isEmpty) 'waypoints': waypoints.toJson(),
  };
}

/// Reads and writes sealed [StoredMesh] files under [dir].
class MeshStore {
  /// Creates a store in [dir], with its key in [keys].
  MeshStore(this.dir, this.keys);

  /// Base directory (app support dir on a phone, a temp dir in tests).
  final Directory dir;

  /// Where the key is kept.
  final HistoryKeys keys;

  File _file(int nodeId) => File('${dir.path}/node_${nodeIdHex(nodeId)}.gwh');

  static final RegExp _nodeFile = RegExp(r'^node_([0-9a-f]{8})\.gwh$');
  static final RegExp _legacyFile = RegExp(r'^node_([0-9a-f]{8})\.json$');
  static final RegExp _legacyLeftover = RegExp(r'^node_[0-9a-f]{8}\.json\.(tmp|bad)$');

  /// Whether [id] is a node ID as used in file names (8 lowercase hex digits).
  static bool isNodeKey(String id) => RegExp(r'^[0-9a-f]{8}$').hasMatch(id);

  Future<SecretKey>? _opening;

  /// Nodes whose history could not be opened: saving would replace it.
  final Set<int> _blocked = <int>{};

  /// The key, once any plaintext files from older versions are sealed.
  Future<SecretKey> _ready() async {
    final pending = _opening ??= _open();
    try {
      return await pending;
    } on Object {
      if (identical(_opening, pending)) _opening = null; // try again next time
      rethrow;
    }
  }

  Future<SecretKey> _open() async {
    final key = await readOrCreateHistoryKey(keys);
    try {
      await _sealLegacy(key);
    } on FileSystemException {
      // e.g. disk full: keep the old file, and do not start a new one over it
      throw const HistoryLocked();
    }
    return key;
  }

  /// Seals histories written by versions before encryption, then removes the
  /// plaintext. A damaged one can't be read by the app, so it is only removed.
  Future<void> _sealLegacy(SecretKey key) async {
    if (!dir.existsSync()) return;
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      final id = _legacyFile.firstMatch(name)?.group(1);
      if (id == null) {
        if (_legacyLeftover.hasMatch(name)) await f.delete();
        continue;
      }
      final target = File('${dir.path}/node_$id.gwh');
      if (!target.existsSync()) {
        final text = await f.readAsString();
        try {
          jsonDecode(text);
        } on FormatException {
          await f.delete();
          continue;
        }
        await _writeSealed(target, text, key, id);
      }
      await f.delete();
    }
  }

  Future<void> _writeSealed(File target, String json, SecretKey key, String nodeHex) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(await sealHistory(json, key, nodeHex), flush: true);
    await tmp.rename(target.path);
  }

  /// Every saved history, as JSON by node ID. Unreadable files are left out.
  /// Throws [HistoryLocked] if the key is unavailable.
  Future<Map<String, Map<String, Object?>>> exportAll() async {
    await idle;
    final key = await _ready();
    final out = <String, Map<String, Object?>>{};
    if (!dir.existsSync()) return out;
    for (final f in dir.listSync().whereType<File>()) {
      final id = _nodeFile.firstMatch(f.uri.pathSegments.last)?.group(1);
      if (id == null) continue;
      try {
        final text = await openHistory(await f.readAsBytes(), key, id);
        out[id] = (jsonDecode(text) as Map<Object?, Object?>).cast<String, Object?>();
      } on FormatException {
        // a damaged history cannot be backed up; the app sets it aside when it next loads it
      } on SecretBoxAuthenticationError {
        // likewise
      }
    }
    return out;
  }

  /// Replaces every saved history with [nodes], sealing all of them in a
  /// staging folder first so a failed write leaves the old data in place.
  Future<void> replaceAll(Map<String, Map<String, Object?>> nodes) async {
    await idle;
    final key = await _ready();
    await dir.create(recursive: true);
    final staging = Directory('${dir.path}/restore_staging');
    if (staging.existsSync()) await staging.delete(recursive: true);
    await staging.create();
    for (final e in nodes.entries) {
      if (!isNodeKey(e.key)) throw ArgumentError.value(e.key, 'node id');
      await File('${staging.path}/node_${e.key}.gwh')
          .writeAsBytes(await sealHistory(jsonEncode(e.value), key, e.key), flush: true);
    }
    await _deleteFiles();
    _blocked.clear();
    for (final f in staging.listSync().whereType<File>()) {
      await f.rename('${dir.path}/${f.uri.pathSegments.last}');
    }
    await staging.delete();
  }

  /// Deletes every saved history and the key (app data reset). A later save
  /// makes a new key.
  Future<void> deleteAll() async {
    await _deleteFiles();
    _blocked.clear();
    _opening = null;
    try {
      await keys.delete();
    } on Object {
      // the files are gone either way; a stale key seals nothing readable
    }
  }

  Future<void> _deleteFiles() async {
    await _queue.catchError((Object _) {});
    if (!dir.existsSync()) return;
    for (final f in dir.listSync()) {
      final name = f.uri.pathSegments.isEmpty ? '' : f.uri.pathSegments.last;
      if (f is File && name.startsWith('node_')) await f.delete();
    }
  }

  /// Loads [nodeId]'s history; empty if none or unreadable, with the reason in
  /// [StoredMesh.problem].
  Future<StoredMesh> load(int nodeId) async {
    final SecretKey key;
    try {
      key = await _ready();
    } on HistoryLocked {
      _blocked.add(nodeId);
      return const StoredMesh(problem: HistoryProblem.locked);
    }
    _blocked.remove(nodeId);
    final f = _file(nodeId);
    try {
      if (!f.existsSync()) return const StoredMesh();
      final text = await openHistory(await f.readAsBytes(), key, nodeIdHex(nodeId));
      final j = jsonDecode(text);
      return StoredMesh.fromJson((j as Map<Object?, Object?>).cast<String, Object?>());
    } on Object {
      // a damaged file must not stop the app; keep it aside (it stays sealed)
      try {
        await f.rename('${f.path}.bad');
      } on FileSystemException {
        // ignore
      }
      return const StoredMesh(problem: HistoryProblem.unreadable);
    }
  }

  Future<void> _queue = Future<void>.value();

  /// Saves [data] atomically (temp file + rename). Saves run one at a time, in
  /// order; a failed save is reported through the returned future only.
  Future<void> save(int nodeId, StoredMesh data) {
    final run = _queue.then((_) => _write(nodeId, data));
    _queue = run.catchError((Object _) {});
    return run;
  }

  /// Completes when every queued save has finished.
  Future<void> get idle => _queue;

  Future<void> _write(int nodeId, StoredMesh data) async {
    if (_blocked.contains(nodeId)) throw const HistoryLocked();
    final key = await _ready();
    await dir.create(recursive: true);
    await _writeSealed(_file(nodeId), jsonEncode(data.toJson()), key, nodeIdHex(nodeId));
  }
}
