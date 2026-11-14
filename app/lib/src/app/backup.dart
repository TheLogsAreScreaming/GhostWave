/// Backs up what the phone holds to an encrypted file, and restores it.
///
/// The node's private key is not included: it never crosses the client link
/// (docs/CLIENT_PROTOCOL.md §7).
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup_codec.dart';
import '../data/mesh_store.dart';
import 'location_share.dart';
import 'mesh_controller.dart';
import 'preferences.dart';
import 'providers.dart';
import 'radios.dart';

/// Preferences that travel with a backup. Per-phone choices that carry their
/// own consent (background connection, location sharing) are asked afresh.
const List<String> kBackupPrefKeys = [
  'node_address',
  'recent_nodes',
  RadiosNotifier.key,
  'units',
  'walkthrough_done',
  'tile_url',
  'tile_attribution',
];

/// The validated contents of a backup.
class BackupData {
  /// Creates the value.
  const BackupData({required this.prefs, required this.pins, required this.nodes});

  /// Decodes a decrypted payload, or throws [BackupBadFile] before anything is changed.
  factory BackupData.parse(Map<String, Object?> j) {
    try {
      final prefs = (j['prefs']! as Map<String, Object?>);
      for (final v in prefs.values) {
        if (v is! String && v is! bool) throw const FormatException('pref');
      }
      final nodes = {
        for (final e in (j['nodes']! as Map<String, Object?>).entries) e.key: (e.value! as Map<String, Object?>),
      };
      for (final e in nodes.entries) {
        if (!MeshStore.isNodeKey(e.key)) throw const FormatException('node id');
        StoredMesh.fromJson(e.value); // throws if malformed
      }
      return BackupData(
        prefs: {
          for (final e in prefs.entries)
            if (kBackupPrefKeys.contains(e.key)) e.key: e.value!,
        },
        pins: (j['pins']! as Map<String, Object?>).cast<String, String>(),
        nodes: nodes,
      );
    } on Object {
      throw const BackupBadFile('This backup is damaged and was not restored.');
    }
  }

  /// Preference values by key.
  final Map<String, Object> prefs;

  /// Client-link PINs by node address.
  final Map<String, String> pins;

  /// Saved history by node ID (8 hex digits).
  final Map<String, Map<String, Object?>> nodes;

  /// JSON payload.
  Map<String, Object?> toJson() => {'payloadVersion': 1, 'prefs': prefs, 'pins': pins, 'nodes': nodes};
}

/// Lets the user choose where a file goes or comes from. Tests use a fake.
abstract interface class BackupFiles {
  /// Whether this phone has a file chooser the app can use.
  bool get supported;

  /// Asks where to save [bytes] as [suggestedName]. False if the user cancelled.
  Future<bool> save(String suggestedName, Uint8List bytes);

  /// Asks for a file. Null if the user cancelled.
  Future<Uint8List?> pick();
}

/// [BackupFiles] for platforms without it (iPhone for now, tests).
class NoBackupFiles implements BackupFiles {
  /// Creates the no-op.
  const NoBackupFiles();

  @override
  bool get supported => false;

  @override
  Future<bool> save(String suggestedName, Uint8List bytes) async => false;

  @override
  Future<Uint8List?> pick() async => null;
}

/// [BackupFiles] over Android's document picker (`MainActivity.kt`). Needs no storage permission.
class AndroidBackupFiles implements BackupFiles {
  /// Creates the channel user.
  const AndroidBackupFiles();

  static const _channel = MethodChannel('org.ghostwave/backup_files');

  @override
  bool get supported => true;

  @override
  Future<bool> save(String suggestedName, Uint8List bytes) async =>
      await _channel.invokeMethod<bool>('save', {'name': suggestedName, 'bytes': bytes}) ?? false;

  @override
  Future<Uint8List?> pick() => _channel.invokeMethod<Uint8List>('pick');
}

/// The file chooser; `main` installs the Android one.
final backupFilesProvider = Provider<BackupFiles>((ref) => const NoBackupFiles());

/// KDF cost for new backups; tests use a cheap one.
final backupKdfProvider = Provider<BackupKdf>((ref) => BackupKdf.standard);

/// Makes and restores backups.
class BackupController {
  /// Creates the controller.
  BackupController(this._ref);

  final Ref _ref;

  /// The current data, as a payload.
  Future<BackupData> _collect() async {
    _ref.read(meshProvider.notifier).flush();
    final store = _ref.read(meshStoreProvider);
    await store?.idle;
    final prefs = _ref.read(sharedPrefsProvider);
    final values = <String, Object>{
      for (final k in kBackupPrefKeys)
        if (prefs.get(k) case final Object v) k: v,
    };
    final pinStore = _ref.read(pinStoreProvider);
    final pins = <String, String>{};
    for (final address in {
      ?_ref.read(nodeAddressProvider),
      for (final r in _ref.read(recentNodesProvider)) r.address,
      for (final r in _ref.read(radiosProvider)) r.address,
    }) {
      final pin = await pinStore.read(address);
      if (pin != null) pins[address] = pin;
    }
    return BackupData(prefs: values, pins: pins, nodes: await store?.exportAll() ?? const {});
  }

  /// Encrypts everything and asks where to save it. False if the user cancelled.
  Future<bool> create(String passphrase, {DateTime? now}) async {
    final data = await _collect();
    final bytes = await sealBackup(data.toJson(), passphrase, kdf: _ref.read(backupKdfProvider));
    final d = (now ?? DateTime.now()).toIso8601String().substring(0, 10);
    return _ref.read(backupFilesProvider).save('ghostwave-$d.gwbackup', bytes);
  }

  /// Decrypts and checks [file], without changing anything.
  Future<BackupData> read(Uint8List file, String passphrase) async =>
      BackupData.parse(await openBackup(file, passphrase));

  /// Replaces the phone's data with [data] and reconnects.
  Future<void> restore(BackupData data) async {
    _ref.read(nodeLinkProvider).disconnect();
    await _ref.read(meshProvider.notifier).replaceLocalData(data.nodes);
    final prefs = _ref.read(sharedPrefsProvider);
    for (final k in kBackupPrefKeys) {
      await prefs.remove(k);
    }
    for (final MapEntry(:key, :value) in data.prefs.entries) {
      if (value is String) await prefs.setString(key, value);
      if (value is bool) await prefs.setBool(key, value);
    }
    final pins = _ref.read(pinStoreProvider);
    await pins.clear();
    for (final MapEntry(:key, :value) in data.pins.entries) {
      await pins.write(key, value);
    }
    _ref
      ..invalidate(nodeAddressProvider)
      ..invalidate(recentNodesProvider)
      ..invalidate(radiosProvider)
      ..invalidate(unitsProvider)
      ..invalidate(locationShareProvider)
      ..invalidate(tileSourceProvider)
      ..invalidate(walkthroughDoneProvider);
    _ref.read(nodeAddressProvider.notifier).connectSaved();
  }
}

/// The backup controller.
final backupProvider = Provider<BackupController>(BackupController.new);
