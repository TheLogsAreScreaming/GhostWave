/// [BleRadio] on the `universal_ble` plugin (BSD-3-Clause).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import '../link/ble.dart';

/// The real Bluetooth radio.
class UniversalBleRadio implements BleRadio {
  /// Creates the radio.
  const UniversalBleRadio();

  @override
  Future<BleAvailability> availability() async => switch (await UniversalBle.getBluetoothAvailabilityState()) {
    AvailabilityState.poweredOn => BleAvailability.on,
    AvailabilityState.poweredOff => BleAvailability.off,
    AvailabilityState.unauthorized => BleAvailability.unauthorized,
    AvailabilityState.unsupported => BleAvailability.unsupported,
    AvailabilityState.unknown || AvailabilityState.resetting => BleAvailability.unknown,
  };

  @override
  Future<void> ensurePermissions() async {
    try {
      // Android 12+: Nearby devices only. Android 11 and older also need
      // location to scan, which the plugin requests there on its own.
      await UniversalBle.requestPermissions();
    } on Object {
      throw const BlePermissionException();
    }
  }

  @override
  Stream<BleAdvert> scan() {
    StreamSubscription<BleDevice>? sub;
    late final StreamController<BleAdvert> out;
    out = StreamController<BleAdvert>(
      onListen: () async {
        sub = UniversalBle.scanStream.listen((d) {
          out.add(BleAdvert(d.deviceId, d.name ?? d.rawName ?? 'GhostWave node', d.rssi ?? -127));
        });
        try {
          await UniversalBle.startScan(scanFilter: ScanFilter(withServices: [kBleService]));
        } on Object catch (e) {
          out.addError(e);
        }
      },
      onCancel: () async {
        await sub?.cancel();
        await UniversalBle.stopScan().catchError((Object _) {});
      },
    );
    return out.stream;
  }

  @override
  Future<BleLink> connect(String id) async {
    await UniversalBle.connect(id, timeout: const Duration(seconds: 20));
    try {
      await UniversalBle.discoverServices(id);
    } on Object {
      await UniversalBle.disconnect(id).catchError((Object _) {});
      rethrow;
    }
    return _Link(id);
  }
}

class _Link implements BleLink {
  _Link(this._id);

  final String _id;

  static const _authCodes = {
    UniversalBleErrorCode.notPaired,
    UniversalBleErrorCode.pairingFailed,
    UniversalBleErrorCode.pairingCancelled,
    UniversalBleErrorCode.pairingTimeout,
    UniversalBleErrorCode.pairingNotAllowed,
    UniversalBleErrorCode.authenticationFailure,
    UniversalBleErrorCode.insufficientAuthentication,
    UniversalBleErrorCode.insufficientAuthorization,
    UniversalBleErrorCode.insufficientEncryption,
  };

  @override
  Future<int> negotiateMtu(int want) => UniversalBle.requestMtu(_id, want);

  @override
  Stream<Uint8List> get notifications => UniversalBle.characteristicValueStream(_id, kBleFromRadio);

  @override
  Future<void> subscribe() async {
    try {
      // long enough for a person to read and type the passkey
      await UniversalBle.subscribeNotifications(_id, kBleService, kBleFromRadio, timeout: const Duration(seconds: 90));
    } on UniversalBleException catch (e) {
      if (_authCodes.contains(e.code)) throw const BleAuthException();
      if (e.code == UniversalBleErrorCode.characteristicNotFound || e.code == UniversalBleErrorCode.serviceNotFound) {
        throw const BleStaleBondException();
      }
      rethrow;
    }
  }

  @override
  Future<void> write(Uint8List bytes) =>
      UniversalBle.write(_id, kBleService, kBleToRadio, bytes, timeout: const Duration(seconds: 10));

  @override
  Future<void> get disconnected => UniversalBle.connectionStream(_id).firstWhere((up) => !up);

  @override
  Future<int> readRssi() => UniversalBle.readRssi(_id);

  @override
  Future<void> close() => UniversalBle.disconnect(_id);
}
