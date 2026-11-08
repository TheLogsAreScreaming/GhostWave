/// Composition root: the providers every screen reads.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../gen/ghostwave.pb.dart' as pb;
import '../link/node_link.dart';
import '../link/session.dart';
import '../link/transport.dart';

/// Shared preferences, loaded before `runApp` and injected in `main`.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider is overridden in main()'),
);

/// The one connection manager.
final nodeLinkProvider = Provider<NodeLink>((ref) {
  final os = switch (Platform.operatingSystem) {
    'android' => 'Android',
    'ios' => 'iOS',
    final other => other,
  };
  final link = NodeLink(clientName: 'GhostWave app ($os)');
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

/// Saved node address (`host:port`), remembered between launches.
class NodeAddressNotifier extends Notifier<String?> {
  static const _key = 'node_address';

  @override
  String? build() => ref.watch(sharedPrefsProvider).getString(_key);

  /// Saves [address] and connects to it.
  Future<void> connectTo(TcpAddress address) async {
    state = address.toString();
    await ref.read(sharedPrefsProvider).setString(_key, state!);
    ref.read(nodeLinkProvider).connect(ref.read(transportFactoryProvider)(address));
  }

  /// Connects to the saved address, if any (app start).
  void connectSaved() {
    final a = state == null ? null : TcpAddress.tryParse(state!);
    if (a != null) ref.read(nodeLinkProvider).connect(ref.read(transportFactoryProvider)(a));
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
