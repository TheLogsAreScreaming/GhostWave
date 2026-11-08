/// Bluetooth LE transport for the client link (`docs/CLIENT_PROTOCOL.md` §9).
/// Plain Dart: the platform plugin sits behind [BleRadio], so tests use a fake.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'transport.dart';

/// GhostWave GATT service.
const String kBleService = '47570001-eea4-45e8-ac37-ff6530d92471';

/// App → node characteristic (write with response).
const String kBleToRadio = '47570002-eea4-45e8-ac37-ff6530d92471';

/// Node → app characteristic (notify).
const String kBleFromRadio = '47570003-eea4-45e8-ac37-ff6530d92471';

/// The ATT MTU to ask for (what the node offers).
const int kBleWantMtu = 247;

/// The default ATT MTU, if the exchange fails.
const int kBleMinMtu = 23;

/// Longest single write the node accepts.
const int kBleMaxWrite = 244;

/// Whether the phone's Bluetooth can be used.
enum BleAvailability {
  /// Ready.
  on,

  /// Switched off.
  off,

  /// The app lacks permission.
  unauthorized,

  /// No Bluetooth LE on this phone.
  unsupported,

  /// Not known yet.
  unknown,
}

/// A node seen while scanning.
class BleAdvert {
  /// Creates a sighting.
  const BleAdvert(this.id, this.name, this.rssi);

  /// Platform device ID.
  final String id;

  /// Advertised name (`GhostWave-a11b`).
  final String name;

  /// Signal strength, dBm.
  final int rssi;
}

/// Pairing failed or the bond is gone. Retrying would only repeat the failure
/// (and the system's passkey dialog), so the user has to act.
class BleAuthException implements Exception {
  /// Creates the exception.
  const BleAuthException();
}

/// The user refused the Bluetooth permissions.
class BlePermissionException implements Exception {
  /// Creates the exception.
  const BlePermissionException();
}

/// One open GATT connection.
abstract interface class BleLink {
  /// Negotiates the ATT MTU; returns the result.
  Future<int> negotiateMtu(int want);

  /// FromRadio notifications. Only those after [subscribe] arrive.
  Stream<Uint8List> get notifications;

  /// Enables FromRadio notifications. On a new node this is what starts
  /// pairing, so it can take as long as the passkey entry. Throws
  /// [BleAuthException] if pairing fails.
  Future<void> subscribe();

  /// Writes to ToRadio, with response.
  Future<void> write(Uint8List bytes);

  /// Completes when the link drops.
  Future<void> get disconnected;

  /// Disconnects.
  Future<void> close();
}

/// The phone's Bluetooth.
abstract interface class BleRadio {
  /// Current state.
  Future<BleAvailability> availability();

  /// Asks for what scanning and connecting need. Throws [BlePermissionException].
  Future<void> ensurePermissions();

  /// GhostWave nodes in range, repeated as they advertise, until cancelled.
  Stream<BleAdvert> scan();

  /// Connects to a node and discovers its services.
  Future<BleLink> connect(String id);
}

/// A remembered Bluetooth node. Stored as `ble:<id>|<name>`, next to `host:port`.
class BleNodeRef {
  /// Creates a reference.
  const BleNodeRef(this.id, this.name);

  /// Parses [encode] output; null for anything else.
  static BleNodeRef? tryParse(String text) {
    if (!text.startsWith('ble:')) return null;
    final rest = text.substring(4);
    final bar = rest.indexOf('|');
    if (bar <= 0) return null;
    return BleNodeRef(rest.substring(0, bar), rest.substring(bar + 1));
  }

  /// Platform device ID.
  final String id;

  /// Display name.
  final String name;

  /// The stored form.
  String encode() => 'ble:$id|$name';
}

/// [Transport] over Bluetooth LE. Each [open] is a fresh GATT connection, so
/// `NodeLink`'s heartbeat and reconnect work exactly as they do on TCP.
class BleTransport implements Transport {
  /// Creates a transport to [node].
  BleTransport(this.node, this.radio);

  /// The node.
  final BleNodeRef node;

  /// The phone's Bluetooth.
  final BleRadio radio;

  static const String _authHelp =
      'Bluetooth pairing failed. Check the 6-digit passkey on the node\'s USB serial console and '
      'try again. If the node\'s pairings were cleared, first forget it in Android\'s Bluetooth settings.';

  @override
  String get label => node.name;

  // pairing already encrypts and authenticates the link (CLIENT_PROTOCOL §7)
  @override
  bool get needsEncryption => false;

  @override
  Future<TransportConnection> open() async {
    switch (await radio.availability()) {
      case BleAvailability.off:
        throw StateError('Bluetooth is off'); // retried: recovers when it is switched on
      case BleAvailability.unauthorized:
        throw const TransportFatalException('Bluetooth permission is off. Allow Nearby devices for GhostWave.');
      case BleAvailability.unsupported:
        throw const TransportFatalException('This phone has no Bluetooth LE.');
      case BleAvailability.on:
      case BleAvailability.unknown:
        break;
    }
    final link = await radio.connect(node.id);
    int mtu;
    try {
      mtu = await link.negotiateMtu(kBleWantMtu);
    } on Object {
      mtu = kBleMinMtu;
    }
    final conn = _BleConnection(link, mtu);
    try {
      await link.subscribe();
    } on BleAuthException {
      await conn.close();
      throw const TransportFatalException(_authHelp);
    } on Object {
      await conn.close();
      rethrow;
    }
    return conn;
  }
}

class _BleConnection implements TransportConnection {
  _BleConnection(this._link, int mtu) : _chunk = math.max(1, math.min(mtu - 3, kBleMaxWrite)) {
    // listening before subscribe(), so the first notification is not lost
    _notes = _link.notifications.listen(_in.add, onError: (Object _) => _finish());
    unawaited(_link.disconnected.then((_) => _finish(), onError: (Object _) => _finish()));
  }

  final BleLink _link;
  final int _chunk;
  final StreamController<Uint8List> _in = StreamController<Uint8List>();
  late final StreamSubscription<Uint8List> _notes;
  Future<void> _writes = Future<void>.value();
  bool _closed = false;

  @override
  Stream<Uint8List> get input => _in.stream;

  /// Writes go one at a time, in order: a frame may span several.
  @override
  void write(List<int> bytes) {
    if (_closed) return;
    final data = Uint8List.fromList(bytes);
    _writes = _writes
        .then((_) async {
          for (var off = 0; off < data.length && !_closed; off += _chunk) {
            await _link.write(Uint8List.sublistView(data, off, math.min(off + _chunk, data.length)));
          }
        })
        .catchError((Object _) => _finish());
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    unawaited(_notes.cancel());
    unawaited(_in.close());
    unawaited(_link.close().catchError((Object _) {}));
  }

  @override
  Future<void> close() async => _finish();
}
