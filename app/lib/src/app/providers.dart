/// Composition root: the providers every screen reads.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../gen/ghostwave.pb.dart' as pb;
import '../link/contact_card.dart';
import '../link/node_link.dart';
import '../link/session.dart';
import '../link/transport.dart';

/// Shared preferences, loaded before `runApp` and injected in `main`.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider is overridden in main()'),
);

/// Where client-link PINs are kept, one per node address.
abstract interface class PinStore {
  /// The PIN for [address], if saved.
  Future<String?> read(String address);

  /// Saves the PIN for [address].
  Future<void> write(String address, String pin);

  /// Forgets the PIN for [address].
  Future<void> delete(String address);

  /// Forgets every PIN.
  Future<void> clear();
}

/// [PinStore] in memory (tests).
class MemoryPinStore implements PinStore {
  final Map<String, String> _pins = {};

  @override
  Future<String?> read(String address) async => _pins[address];

  @override
  Future<void> write(String address, String pin) async => _pins[address] = pin;

  @override
  Future<void> delete(String address) async => _pins.remove(address);

  @override
  Future<void> clear() async => _pins.clear();
}

/// [PinStore] in the platform's secure storage (Android Keystore, iOS Keychain).
class SecurePinStore implements PinStore {
  /// Creates the store.
  const SecurePinStore();

  static const _storage = FlutterSecureStorage();
  static String _key(String address) => 'pin_$address';

  @override
  Future<String?> read(String address) async {
    try {
      return await _storage.read(key: _key(address));
    } on Object {
      return null; // treated as "not saved": the app asks again
    }
  }

  @override
  Future<void> write(String address, String pin) => _storage.write(key: _key(address), value: pin);

  @override
  Future<void> delete(String address) => _storage.delete(key: _key(address));

  @override
  Future<void> clear() => _storage.deleteAll();
}

/// The PIN store; `main` installs [SecurePinStore].
final pinStoreProvider = Provider<PinStore>((ref) => MemoryPinStore());

/// The one connection manager.
final nodeLinkProvider = Provider<NodeLink>((ref) {
  final os = switch (Platform.operatingSystem) {
    'android' => 'Android',
    'ios' => 'iOS',
    final other => other,
  };
  final link = NodeLink(clientName: 'GhostWave app ($os)');
  final pins = ref.watch(pinStoreProvider);
  link
    ..pinFor = pins.read
    ..onBadPin = pins.delete;
  ref.onDispose(link.dispose);
  return link;
});

/// The link state, starting with the current one.
final linkStateProvider = StreamProvider<LinkState>((ref) async* {
  final link = ref.watch(nodeLinkProvider);
  yield link.state;
  yield* link.states;
});

/// `NodeInfo` while the link is up, else null.
final nodeInfoProvider = Provider<pb.NodeInfo?>((ref) {
  final s = ref.watch(linkStateProvider).value;
  return s is LinkUp ? s.info : null;
});

/// The live session while the link is up, else null.
final sessionProvider = Provider<LinkSession?>((ref) {
  final s = ref.watch(linkStateProvider).value;
  return s is LinkUp ? s.session : null;
});

/// Makes the transport for an address. Tests override it; BLE will add its own.
final transportFactoryProvider = Provider<Transport Function(TcpAddress)>((ref) => TcpTransport.new);

/// Whether the app is in the foreground. `main` updates it from the app
/// lifecycle; location sharing runs and notifications stay quiet while true.
class AppForegroundNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  /// Records a lifecycle change.
  void set({required bool foreground}) => state = foreground;
}

/// True while the app is in the foreground.
final appForegroundProvider = NotifierProvider<AppForegroundNotifier, bool>(AppForegroundNotifier.new);

/// A node the app connected to before, for one-tap reconnect.
class RecentNode {
  /// Creates an entry.
  const RecentNode({required this.address, required this.lastUsed, this.name = '', this.nodeId});

  /// From JSON written by [toJson]; null if malformed.
  static RecentNode? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final address = j['a'];
    final used = j['t'];
    if (address is! String || used is! int) return null;
    final name = j['n'];
    final id = j['id'];
    return RecentNode(
      address: address,
      lastUsed: DateTime.fromMillisecondsSinceEpoch(used),
      name: name is String ? name : '',
      nodeId: id is int ? id : null,
    );
  }

  /// `host:port`.
  final String address;

  /// Node name from its `NodeInfo`, once connected.
  final String name;

  /// Node ID from its `NodeInfo`, once connected.
  final int? nodeId;

  /// Last connect.
  final DateTime lastUsed;

  /// "N1 (9d66916b)", or the address before the first successful connect.
  String get label {
    if (nodeId == null) return address;
    final id = nodeIdHex(nodeId!);
    return name.isEmpty ? id : '$name ($id)';
  }

  /// JSON form.
  Map<String, Object?> toJson() => {
    'a': address,
    't': lastUsed.millisecondsSinceEpoch,
    if (name.isNotEmpty) 'n': name,
    if (nodeId != null) 'id': nodeId,
  };
}

/// Recently used node addresses, newest first (at most [max]).
class RecentNodesNotifier extends Notifier<List<RecentNode>> {
  static const _key = 'recent_nodes';

  /// How many addresses are kept.
  static const max = 6;

  @override
  List<RecentNode> build() {
    final raw = ref.watch(sharedPrefsProvider).getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final j in list) ?RecentNode.tryFromJson(j)];
    } on FormatException {
      return const [];
    }
  }

  /// Moves [address] to the top (keeping its known name and ID).
  void touch(String address, {DateTime? now}) {
    final old = state.where((r) => r.address == address).firstOrNull;
    _set([
      RecentNode(address: address, lastUsed: now ?? DateTime.now(), name: old?.name ?? '', nodeId: old?.nodeId),
      for (final r in state)
        if (r.address != address) r,
    ]);
  }

  /// Records which node answered at [address].
  void label(String address, {required String name, required int nodeId}) {
    final old = state.where((r) => r.address == address).firstOrNull;
    if (old == null || (old.name == name && old.nodeId == nodeId)) return;
    _set([
      for (final r in state)
        if (r.address == address) RecentNode(address: address, lastUsed: r.lastUsed, name: name, nodeId: nodeId) else r,
    ]);
  }

  /// Forgets [address].
  void remove(String address) => _set([
    for (final r in state)
      if (r.address != address) r,
  ]);

  void _set(List<RecentNode> list) {
    state = list.take(max).toList();
    unawaited(ref.read(sharedPrefsProvider).setString(_key, jsonEncode([for (final r in state) r.toJson()])));
  }
}

/// Recently used nodes.
final recentNodesProvider = NotifierProvider<RecentNodesNotifier, List<RecentNode>>(RecentNodesNotifier.new);

/// Saved node address (`host:port`), remembered between launches.
class NodeAddressNotifier extends Notifier<String?> {
  static const _key = 'node_address';

  @override
  String? build() {
    // label the recent-nodes entry with the node that answered
    ref.listen(linkStateProvider, (_, next) {
      final s = next.value;
      final address = state;
      if (s is LinkUp && address != null) {
        ref.read(recentNodesProvider.notifier).label(address, name: decodeLenient(s.info.name), nodeId: s.info.nodeId);
      }
    });
    return ref.watch(sharedPrefsProvider).getString(_key);
  }

  /// Saves [address] and connects to it.
  Future<void> connectTo(TcpAddress address) async {
    state = address.toString();
    ref.read(recentNodesProvider.notifier).touch(state!);
    await ref.read(sharedPrefsProvider).setString(_key, state!);
    ref.read(nodeLinkProvider).connect(ref.read(transportFactoryProvider)(address));
  }

  /// Connects to the saved address, if any (app start).
  void connectSaved() {
    final a = state == null ? null : TcpAddress.tryParse(state!);
    if (a == null) return;
    ref.read(recentNodesProvider.notifier).touch(state!);
    ref.read(nodeLinkProvider).connect(ref.read(transportFactoryProvider)(a));
  }

  /// Saves [pin] for [target] and tries again.
  Future<void> submitPin(String target, String pin) async {
    await ref.read(pinStoreProvider).write(target, pin);
    ref.read(nodeLinkProvider).retryNow();
  }

  /// Disconnects and stops reconnecting. The address stays saved.
  void disconnect() => ref.read(nodeLinkProvider).disconnect();
}

/// The saved node address.
final nodeAddressProvider = NotifierProvider<NodeAddressNotifier, String?>(NodeAddressNotifier.new);

/// Node status, fetched with `GetStatus`; refresh with `ref.invalidate`.
final nodeStatusProvider = FutureProvider.autoDispose<pb.Status?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  final r = await session.request(pb.ToRadio(getStatus: pb.GetStatus()));
  return r.status;
});
