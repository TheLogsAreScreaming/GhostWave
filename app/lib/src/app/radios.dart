/// The radios this phone has used: remembered, renamed, forgotten and switched
/// between.
///
/// The app talks to one radio at a time (the active one: the saved node
/// address). Each radio keeps its own chats, contacts and channels on the
/// phone, in its own history file sealed for its node ID (`mesh_store.dart`),
/// so switching never mixes one radio's history, or the keys in it, with
/// another's.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../link/ble.dart';
import '../link/contact_card.dart';
import '../link/node_link.dart';
import 'mesh_controller.dart';
import 'providers.dart';

/// Board names from the firmware string, as people know them.
const Map<String, String> kBoardNames = {
  'heltec_v3': 'Heltec V3',
  'heltec_v4': 'Heltec V4',
  'heltec_wsl_v3': 'Heltec Wireless Stick Lite V3',
  'heltec_t114': 'Heltec T114',
  'heltec_wireless_tracker_v2': 'Heltec Wireless Tracker V2',
  'rak4631': 'RAK4631',
  'rak3401_1w': 'RAK3401 1 W',
  'rak_wismesh_tag': 'RAK WisMesh Tag',
  't1000e': 'T1000-E',
  't_beam_sx1276': 'T-Beam',
  't_deck': 'T-Deck',
  't3s3': 'T3-S3',
  'wio_tracker_l1': 'Wio Tracker L1',
  'xiao_s3': 'XIAO ESP32S3',
  'solar_node': 'Solar node',
};

/// The board in a GhostWave firmware string (`ghostwave-<board> <version>`),
/// or null for other firmware.
String? boardFromFirmware(String firmware) {
  if (!firmware.startsWith('ghostwave-')) return null;
  final rest = firmware.substring('ghostwave-'.length);
  final space = rest.indexOf(' ');
  final id = space < 0 ? rest : rest.substring(0, space);
  if (id.isEmpty) return null;
  return kBoardNames[id] ?? id.replaceAll('_', ' ');
}

/// Longest nickname, in characters.
const int kRadioNicknameMax = 30;

/// A radio the phone has connected to.
class SavedRadio {
  /// Creates an entry.
  const SavedRadio({
    required this.address,
    this.nickname = '',
    this.nodeName = '',
    this.nodeId,
    this.firmware = '',
    this.lastConnected,
  });

  /// From [toJson]; null if malformed.
  static SavedRadio? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final address = j['a'];
    if (address is! String || address.isEmpty) return null;
    String str(Object? v) => v is String ? v : '';
    final id = j['id'];
    final last = j['t'];
    return SavedRadio(
      address: address,
      nickname: str(j['nick']),
      nodeName: str(j['n']),
      nodeId: id is int ? id : null,
      firmware: str(j['fw']),
      lastConnected: last is int ? DateTime.fromMillisecondsSinceEpoch(last) : null,
    );
  }

  /// How the app reaches it: `ble:<id>|<name>` or `host:port`.
  final String address;

  /// The user's name for it on this phone; empty for none.
  final String nickname;

  /// The name the node gave in its `NodeInfo`.
  final String nodeName;

  /// Its node ID, once it has answered.
  final int? nodeId;

  /// Its firmware string.
  final String firmware;

  /// When it last finished connecting.
  final DateTime? lastConnected;

  /// Whether it is reached over Bluetooth.
  bool get isBluetooth => BleNodeRef.tryParse(address) != null;

  /// The phone's Bluetooth address (device ID) for it, or null on a network link.
  String? get bluetoothId => BleNodeRef.tryParse(address)?.id;

  /// The board, from the firmware string, or null.
  String? get board => boardFromFirmware(firmware);

  /// The node ID as 8 hex digits, or null.
  String? get idHex => nodeId == null ? null : nodeIdHex(nodeId!);

  /// What to call it: the nickname, else the node's name, else how it was found.
  String get displayName {
    if (nickname.isNotEmpty) return nickname;
    if (nodeName.isNotEmpty) return nodeName;
    final ble = BleNodeRef.tryParse(address);
    if (ble != null) return ble.name;
    return idHex ?? address;
  }

  /// Copy with changes.
  SavedRadio copyWith({String? nickname, String? nodeName, int? nodeId, String? firmware, DateTime? lastConnected}) =>
      SavedRadio(
        address: address,
        nickname: nickname ?? this.nickname,
        nodeName: nodeName ?? this.nodeName,
        nodeId: nodeId ?? this.nodeId,
        firmware: firmware ?? this.firmware,
        lastConnected: lastConnected ?? this.lastConnected,
      );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'a': address,
    if (nickname.isNotEmpty) 'nick': nickname,
    if (nodeName.isNotEmpty) 'n': nodeName,
    if (nodeId != null) 'id': nodeId,
    if (firmware.isNotEmpty) 'fw': firmware,
    if (lastConnected != null) 't': lastConnected!.millisecondsSinceEpoch,
  };
}

/// The saved radios, most recently connected first, and the actions on them.
class RadiosNotifier extends Notifier<List<SavedRadio>> {
  /// Preference key; it travels with backups.
  static const key = 'radios';

  /// How many radios are kept; the least recently used goes first.
  static const max = 24;

  @override
  List<SavedRadio> build() {
    // straight from the link, not through a provider: it must work with no UI
    final sub = ref.watch(nodeLinkProvider).states.listen((s) {
      if (s is LinkUp) _connected(s);
    });
    ref.onDispose(sub.cancel);
    final prefs = ref.watch(sharedPrefsProvider);
    final raw = prefs.getString(key);
    if (raw == null) return _fromRecent();
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return _sorted([for (final j in list) ?SavedRadio.tryFromJson(j)]);
    } on FormatException {
      return const [];
    }
  }

  /// First start with this version: the radios among the recent nodes.
  List<SavedRadio> _fromRecent() => _sorted([
    for (final r in ref.read(recentNodesProvider))
      if (r.nodeId != null)
        SavedRadio(address: r.address, nodeName: r.name, nodeId: r.nodeId, lastConnected: r.lastUsed),
  ]);

  static List<SavedRadio> _sorted(List<SavedRadio> list) {
    final out = [...list];
    // stable: equal times keep their order
    final index = {for (var i = 0; i < out.length; i++) out[i].address: i};
    out.sort((a, b) {
      final ta = a.lastConnected?.millisecondsSinceEpoch ?? -1;
      final tb = b.lastConnected?.millisecondsSinceEpoch ?? -1;
      return ta != tb ? tb.compareTo(ta) : index[a.address]!.compareTo(index[b.address]!);
    });
    return out.take(max).toList();
  }

  void _connected(LinkUp up) {
    final address = ref.read(nodeAddressProvider);
    if (address == null) return;
    final old = state.where((r) => r.address == address).firstOrNull ?? SavedRadio(address: address);
    _set([
      old.copyWith(
        nodeName: decodeLenient(up.info.name),
        nodeId: up.info.nodeId,
        firmware: up.info.firmware,
        lastConnected: ref.read(clockProvider)(),
      ),
      for (final r in state)
        if (r.address != address) r,
    ]);
  }

  /// The radio at [address], if saved.
  SavedRadio? byAddress(String? address) =>
      address == null ? null : state.where((r) => r.address == address).firstOrNull;

  /// Gives the radio at [address] a nickname on this phone; empty clears it.
  void rename(String address, String nickname) {
    final name = nickname.trim();
    final short = String.fromCharCodes(name.runes.take(kRadioNicknameMax));
    _set([
      for (final r in state)
        if (r.address == address)
          SavedRadio(
            address: r.address,
            nickname: short,
            nodeName: r.nodeName,
            nodeId: r.nodeId,
            firmware: r.firmware,
            lastConnected: r.lastConnected,
          )
        else
          r,
    ]);
  }

  /// Makes [address] the active radio: lets go of the current one, shows the
  /// new one's chats, and connects. Auto-reconnect and the background service
  /// follow the link, so they move to it too.
  Future<void> switchTo(String address) async {
    final link = ref.read(nodeLinkProvider);
    final current = ref.read(nodeAddressProvider);
    final live = link.state is LinkUp || link.state is LinkConnecting || link.state is LinkWaiting;
    if (current == address && live) return;
    final old = link.session;
    link.disconnect();
    await old?.close(); // the old radio is let go before the new one is opened
    if (!ref.mounted) return;
    final mesh = ref.read(meshProvider.notifier);
    if (current != address) await mesh.showRadio(byAddress(address)?.nodeId);
    if (!ref.mounted) return;
    await ref.read(nodeAddressProvider.notifier).connectAddress(address);
  }

  /// Forgets the radio at [address]: its entry, its saved PIN, and its place in
  /// the recent list. If it is the active radio, the app disconnects and stops
  /// reconnecting to it. With [deleteHistory], its chats, contacts and
  /// channels on this phone go too (unless another saved entry is the same radio).
  Future<void> forget(String address, {bool deleteHistory = false}) async {
    final gone = byAddress(address);
    if (ref.read(nodeAddressProvider) == address) {
      ref.read(nodeAddressProvider.notifier).forgetSaved();
    }
    _set([
      for (final r in state)
        if (r.address != address) r,
    ]);
    ref.read(recentNodesProvider.notifier).remove(address);
    await ref.read(pinStoreProvider).delete(address);
    final id = gone?.nodeId;
    if (deleteHistory && id != null && !state.any((r) => r.nodeId == id)) {
      await ref.read(meshProvider.notifier).deleteRadioHistory(id);
    }
  }

  void _set(List<SavedRadio> list) {
    state = _sorted(list);
    unawaited(ref.read(sharedPrefsProvider).setString(key, jsonEncode([for (final r in state) r.toJson()])));
  }
}

/// The saved radios.
final radiosProvider = NotifierProvider<RadiosNotifier, List<SavedRadio>>(RadiosNotifier.new);

/// The active radio (the one the app connects to), if it has connected before.
final activeRadioProvider = Provider<SavedRadio?>((ref) {
  final address = ref.watch(nodeAddressProvider);
  if (address == null) return null;
  return ref.watch(radiosProvider).where((r) => r.address == address).firstOrNull;
});
