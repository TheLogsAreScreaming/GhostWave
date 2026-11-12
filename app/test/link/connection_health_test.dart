// Connection health: the time since the node answered runs on a monotonic
// clock, goes stale after a missed heartbeat, and troubleshooting matches the
// real failure reasons without ever showing a saved PIN.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:ghostwave_app/src/link/session.dart';
import 'package:ghostwave_app/src/ui/connection_health.dart';

import 'fake_node.dart';

void main() {
  test('time since the last answer follows a fake monotonic clock', () async {
    var now = const Duration(seconds: 100);
    final node = FakeNode();
    final s = LinkSession(await node.open() as FakeConnection, clock: () => now);
    expect(s.sinceLastReceived, isNull, reason: 'nothing received yet');
    expect(freshnessOf(s.sinceLastReceived), Freshness.waiting);
    await s.hello('test');
    expect(s.sinceLastReceived, Duration.zero);
    now += const Duration(seconds: 20);
    expect(s.age, const Duration(seconds: 20));
    expect(freshnessOf(s.sinceLastReceived), Freshness.live);
    now += const Duration(seconds: 6);
    expect(freshnessOf(s.sinceLastReceived), Freshness.stale);
    expect(s.canReadLinkSignal, isFalse, reason: 'TCP and fakes cannot measure a radio link');
    expect(await s.readLinkSignalDbm(), isNull);
    await s.close();
  });

  test('short durations and Bluetooth words', () {
    expect(shortDuration(const Duration(seconds: 12)), '12 s');
    expect(shortDuration(const Duration(seconds: 185)), '3 min 05 s');
    expect(shortDuration(const Duration(minutes: 130)), '2 h 10 min');
    expect(bluetoothWord(-55), 'strong');
    expect(bluetoothWord(-70), 'good');
    expect(bluetoothWord(-85), 'fair');
    expect(bluetoothWord(-95), 'weak');
  });

  group('troubleshooting', () {
    List<String> titles(LinkState s, {bool bluetooth = true}) =>
        troubleshootingFor(s, bluetooth: bluetooth).map((t) => t.title).toList();

    test('a stale pairing says to forget it', () {
      final t = titles(
        const LinkFailed(
          'GhostWave-8904',
          'This phone is using an old Bluetooth pairing for this node, from earlier firmware.',
        ),
      );
      expect(t.first, 'Forget the old pairing');
      expect(t, contains('One phone at a time'));
      expect(t.last, 'Still stuck?');
    });

    test('a failed pairing points at the key', () {
      expect(
        titles(const LinkFailed('n', 'Bluetooth pairing failed. The passkey is 654321 unless it was changed')).first,
        'Check the pairing key',
      );
    });

    test('permission, Bluetooth off, timeouts and version mismatches', () {
      expect(
        titles(const LinkFailed('n', 'Bluetooth permission is off. Allow Nearby devices for GhostWave.')).first,
        'Allow Nearby devices',
      );
      expect(
        titles(const LinkWaiting('n', 'Bad state: Bluetooth is off', Duration(seconds: 5))).first,
        'Turn Bluetooth on',
      );
      expect(
        titles(const LinkWaiting('n', 'link timed out (no reply in 10 s)', Duration(seconds: 2))).first,
        'Move closer to the radio',
      );
      expect(titles(const LinkFailed('n', 'node speaks protocol version 2')).first, 'Update the app or the firmware');
    });

    test('a network node gets address advice, not Bluetooth advice', () {
      final t = titles(
        const LinkWaiting('10.0.0.5:4403', 'Connection refused', Duration(seconds: 1)),
        bluetooth: false,
      );
      expect(t, contains('Check the address'));
      expect(t, isNot(contains('One phone at a time')));
    });

    test('nothing to try while connected, connecting or asking for a PIN; never a saved PIN', () {
      expect(troubleshootingFor(const LinkIdle(), bluetooth: true), isEmpty);
      expect(troubleshootingFor(const LinkConnecting('n', 1), bluetooth: true), isEmpty);
      expect(troubleshootingFor(const LinkNeedsPin('n'), bluetooth: true), isEmpty);
      final all = troubleshootingFor(const LinkFailed('n', 'pairing failed, timed out, permission'), bluetooth: true);
      expect(all.every((t) => !t.body.contains('PIN')), isTrue);
    });
  });

  test('Status signal fields exist for the health card', () {
    final s = pb.Status(lastRssiDbm: -98, lastHeardS: 4);
    expect(s.hasLastRssiDbm() && s.hasLastHeardS(), isTrue);
  });
}
