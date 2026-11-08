/// Local history, one JSON file per node ID, so chats survive a restart and
/// connecting to a different node does not mix histories.
library;

import 'dart:convert';
import 'dart:io';

import '../link/contact_card.dart';
import 'models.dart';

/// What is saved for one node.
class StoredMesh {
  /// Creates the snapshot.
  const StoredMesh({
    this.contacts = const {},
    this.messages = const {},
    this.alerts = const [],
    this.ownSos = const OwnSos(),
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
    return StoredMesh(
      contacts: contacts,
      messages: messages,
      alerts: [for (final a in (j['alerts'] as List<Object?>?) ?? const <Object?>[]) SosAlertEntry.fromJson(m(a))],
      ownSos: j['ownSos'] == null ? const OwnSos() : OwnSos.fromJson(m(j['ownSos'])),
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
  };
}

/// Reads and writes [StoredMesh] files under [dir].
class MeshStore {
  /// Creates a store in [dir].
  MeshStore(this.dir);

  /// Base directory (app support dir on a phone, a temp dir in tests).
  final Directory dir;

  File _file(int nodeId) => File('${dir.path}/node_${nodeIdHex(nodeId)}.json');

  /// Loads [nodeId]'s history; empty if none or unreadable.
  Future<StoredMesh> load(int nodeId) async {
    final f = _file(nodeId);
    try {
      if (!f.existsSync()) return const StoredMesh();
      final j = jsonDecode(await f.readAsString());
      return StoredMesh.fromJson((j as Map<Object?, Object?>).cast<String, Object?>());
    } on Object {
      // a corrupt file must not stop the app; keep it aside for debugging
      try {
        await f.rename('${f.path}.bad');
      } on FileSystemException {
        // ignore
      }
      return const StoredMesh();
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
    await dir.create(recursive: true);
    final f = _file(nodeId);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data.toJson()), flush: true);
    await tmp.rename(f.path);
  }
}
