// The foreground service's rules, its explanation screen and the manifest.
// The service itself needs a real phone: see README "Background connection checks".
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/background_link.dart';
import 'package:ghostwave_app/src/app/mesh_alerts.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:ghostwave_app/src/ui/background_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../link/fake_node.dart';
import 'mesh_controller_test.dart' show answeringNode, bob, settle;
import 'phone_qol_test.dart' show RecordingAlerts;

class FakePlatform implements BackgroundPlatform {
  final List<String> calls = [];
  bool refuseStart = false;
  bool exempt = false;
  final StreamController<void> taps = StreamController<void>.broadcast();

  @override
  bool get supported => true;

  @override
  Future<bool> start(BackgroundNotice n) async {
    calls.add('start ${n.title}');
    return !refuseStart;
  }

  @override
  Future<void> update(BackgroundNotice n) async => calls.add('update ${n.title}');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<bool> batteryExempt() async => exempt;

  @override
  Future<void> requestBatteryExemption() async => calls.add('ask battery');

  @override
  Stream<void> get disconnectRequests => taps.stream;
}

void main() {
  late FakePlatform platform;
  late RecordingAlerts alerts;
  late ProviderContainer c;
  late NodeLink link;

  Future<void> makeContainer(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    platform = FakePlatform();
    alerts = RecordingAlerts();
    c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        backgroundPlatformProvider.overrideWithValue(platform),
        meshAlertsProvider.overrideWithValue(alerts),
      ],
    );
    addTearDown(c.dispose);
    link = c.read(nodeLinkProvider);
    c.read(backgroundLinkProvider);
  }

  Future<void> flush() async {
    await settle();
    await c.read(backgroundLinkProvider).idle;
  }

  Future<FakeNode> connect() async {
    final node = answeringNode();
    link.connect(node);
    await flush();
    return node;
  }

  group('backgroundNoticeFor', () {
    test('wording by state', () {
      expect(backgroundNoticeFor(const LinkConnecting('h:1', 1))?.title, 'GhostWave reconnecting');
      expect(
        backgroundNoticeFor(const LinkWaiting('h:1', 'gone', Duration(seconds: 1))),
        const BackgroundNotice('GhostWave reconnecting', 'h:1'),
      );
    });
    test('no service while waiting for the user or idle', () {
      expect(backgroundNoticeFor(const LinkIdle()), isNull);
      expect(backgroundNoticeFor(const LinkFailed('t', 'x')), isNull);
      expect(backgroundNoticeFor(const LinkNeedsPin('t')), isNull);
    });
  });

  group('service follows the link', () {
    test('never runs until the user turned it on', () async {
      await makeContainer({});
      expect(c.read(backgroundEnabledProvider), isNull);
      await connect();
      expect(platform.calls, isEmpty);
    });

    test('off stays off', () async {
      await makeContainer({'background_link': false});
      await connect();
      expect(platform.calls, isEmpty);
    });

    test('starts once and stops on disconnect', () async {
      await makeContainer({'background_link': true});
      await connect();
      expect(platform.calls, ['start GhostWave reconnecting', 'update GhostWave connected']);
      link.disconnect();
      await flush();
      expect(platform.calls.last, 'stop');
      expect(alerts.shown, isEmpty);
    });

    test('a dropped link keeps the service and says reconnecting', () async {
      await makeContainer({'background_link': true});
      final node = await connect();
      c.read(appForegroundProvider.notifier).set(foreground: false);
      await node.last.drop();
      await flush();
      expect(platform.calls, contains('update GhostWave reconnecting'));
      expect(platform.calls, isNot(contains('stop')));
      link.disconnect();
      await flush();
    });

    test('turning it off stops the service and leaves the link up', () async {
      await makeContainer({'background_link': true});
      await connect();
      c.read(backgroundEnabledProvider.notifier).set(enabled: false);
      await flush();
      expect(platform.calls.last, 'stop');
      expect(link.state, isA<LinkUp>());
      link.disconnect();
    });

    test('the notification button disconnects', () async {
      await makeContainer({'background_link': true});
      await connect();
      platform.taps.add(null);
      await flush();
      expect(link.state, isA<LinkIdle>());
      expect(platform.calls.last, 'stop');
    });

    test('a refused start is retried on return to the foreground', () async {
      await makeContainer({'background_link': true});
      platform.refuseStart = true;
      await connect();
      platform.refuseStart = false;
      c.read(appForegroundProvider.notifier).set(foreground: false);
      c.read(appForegroundProvider.notifier).set(foreground: true);
      await flush();
      expect(platform.calls.last, 'start GhostWave connected');
      link.disconnect();
      await flush();
      expect(platform.calls.last, 'stop');
    });

    test('never tries to start from the background', () async {
      await makeContainer({'background_link': true});
      c.read(appForegroundProvider.notifier).set(foreground: false);
      await connect();
      expect(platform.calls, isEmpty);
      link.disconnect();
    });

    test('tells the user when it ends in the background without them', () async {
      await makeContainer({'background_link': true});
      final node = await connect();
      c.read(appForegroundProvider.notifier).set(foreground: false);
      node.pin = '123456';
      await node.last.drop();
      await Future<void>.delayed(const Duration(seconds: 2));
      await flush();
      expect(link.state, isA<LinkNeedsPin>());
      expect(platform.calls.last, 'stop');
      expect(alerts.shown.single, startsWith('stopped:'));
    });
  });

  group('background delivery', () {
    test('a DM with no UI notifies and is kept', () async {
      await makeContainer({'background_link': true});
      c.read(meshProvider);
      final node = await connect();
      c.read(appForegroundProvider.notifier).set(foreground: false);
      node.last.send(
        pb.FromRadio(
          text: pb.TextMessage(src: bob, text: 'hi'.codeUnits, msgId: 9),
        ),
      );
      await flush();
      expect(alerts.shown, ['text ${c.read(meshProvider).nameOf(bob)}: hi']);
      expect(c.read(meshProvider).messages[bob]?.single.text, 'hi');
      link.disconnect();
    });
  });

  group('explanation screen', () {
    Future<void> pump(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: BackgroundSetupScreen()),
        ),
      );
    }

    testWidgets('says why, then asks for the exemption and turns it on', (t) async {
      await t.runAsync(() => makeContainer({}));
      await pump(t);
      expect(find.textContaining('uses more battery'), findsOneWidget);
      expect(c.read(backgroundEnabledProvider), isNull);
      await t.tap(find.text('Keep me connected'));
      await t.pump();
      await t.pump();
      expect(platform.calls, contains('ask battery'));
      expect(c.read(backgroundEnabledProvider), isTrue);
    });

    testWidgets('does not ask again when already exempt', (t) async {
      await t.runAsync(() => makeContainer({}));
      platform.exempt = true;
      await pump(t);
      await t.tap(find.text('Keep me connected'));
      await t.pump();
      await t.pump();
      expect(platform.calls, isNot(contains('ask battery')));
    });

    testWidgets('Not now records the decision and asks nothing', (t) async {
      await t.runAsync(() => makeContainer({}));
      await pump(t);
      await t.tap(find.text('Not now'));
      await t.pump();
      expect(c.read(backgroundEnabledProvider), isFalse);
      expect(platform.calls, isEmpty);
    });
  });

  group('Android manifest', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    test('service type and permissions for Android 14+', () {
      expect(manifest, contains('android:foregroundServiceType="connectedDevice"'));
      for (final p in [
        'FOREGROUND_SERVICE',
        'FOREGROUND_SERVICE_CONNECTED_DEVICE',
        'CHANGE_NETWORK_STATE',
        'WAKE_LOCK',
        'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        'POST_NOTIFICATIONS',
      ]) {
        expect(manifest, contains('android.permission.$p"'), reason: p);
      }
    });
    test('no background location', () {
      expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
    });
    test('service is private', () {
      expect(RegExp(r'LinkForegroundService"\s+android:exported="false"').hasMatch(manifest), isTrue);
    });
  });
}
