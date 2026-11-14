// Radio and device settings from the app (protocol 1.11): read, change, the
// node's refusal surfaces, and older nodes are never asked.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../link/fake_node.dart';
import '../support/history_keys.dart';
import 'mesh_controller_test.dart' show settle;

/// A node holding settings that SetSettings changes, refusing power over 29.
FakeNode settingsNode({int minor = 11}) {
  final node = FakeNode()..protocolMinor = minor;
  final s = pb.Settings(
    region: 'us915',
    freqKhz: 914875,
    outputDbm: 20,
    minOutputDbm: -1,
    maxOutputDbm: 29,
    minFreqKhz: 902063,
    maxFreqKhz: 927938,
    channelKeyOn: false,
    ledsFitted: true,
    leds: true,
  );
  node.onRequest.listen((e) {
    final (c, r) = e;
    switch (r.whichRequest()) {
      case pb.ToRadio_Request.getSettings:
        c.send(pb.FromRadio(reqId: r.reqId, settings: s));
      case pb.ToRadio_Request.setSettings:
        final x = r.setSettings;
        if (x.hasOutputDbm() && x.outputDbm > 29) {
          c.send(
            pb.FromRadio(
              reqId: r.reqId,
              error: pb.Error(code: pb.Error_Code.BAD_ARGUMENT, detail: 'output_dbm: -1..29 on this board'),
            ),
          );
          return;
        }
        if (x.hasOutputDbm()) s.outputDbm = x.outputDbm;
        if (x.hasLeds()) s.leds = x.leds;
        if (x.channelKey.isNotEmpty) s.channelKeyOn = true;
        c.send(pb.FromRadio(reqId: r.reqId, ok: pb.Ok()));
      case pb.ToRadio_Request.listContacts:
        c.send(pb.FromRadio(reqId: r.reqId, contactsEnd: pb.ContactsEnd()));
      case pb.ToRadio_Request.listChannels:
        c.send(pb.FromRadio(reqId: r.reqId, channelsEnd: pb.ChannelsEnd()));
      case pb.ToRadio_Request.getPosition:
        c.send(pb.FromRadio(reqId: r.reqId, position: pb.OwnPosition()));
      case pb.ToRadio_Request.getStatus:
        c.send(pb.FromRadio(reqId: r.reqId, status: pb.Status()));
      default:
        break;
    }
  });
  return node;
}

void main() {
  late Directory dir;
  late ProviderContainer c;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-settings.');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
      ],
    );
    c.listen(meshProvider, (_, _) {});
  });
  tearDown(() async {
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('reads, changes only what was asked, and returns the new values', () async {
    final node = settingsNode();
    c.read(nodeLinkProvider).connect(node);
    await settle();
    final ctl = c.read(meshProvider.notifier);
    expect(ctl.nodeCanSettings, isTrue);
    final s = await ctl.readNodeSettings();
    expect([s.outputDbm, s.maxOutputDbm, s.region], [20, 29, 'us915']);
    final now = await ctl.changeNodeSettings(pb.Settings(outputDbm: 27, leds: false));
    expect([now.outputDbm, now.leds], [27, false]);
    final sent = node.requests.where((r) => r.hasSetSettings()).single.setSettings;
    expect(sent.hasOutputDbm() && sent.hasLeds(), isTrue);
    expect(sent.hasRegion() || sent.hasFreqKhz() || sent.hasBlePin(), isFalse, reason: 'only the changed fields');
  });

  test('a refusal comes back as the node said it', () async {
    c.read(nodeLinkProvider).connect(settingsNode());
    await settle();
    await expectLater(
      c.read(meshProvider.notifier).changeNodeSettings(pb.Settings(outputDbm: 30)),
      throwsA(isA<NodeError>().having((e) => e.code, 'code', pb.Error_Code.BAD_ARGUMENT)),
    );
  });

  test('an older node is never asked', () async {
    final node = settingsNode(minor: 10);
    c.read(nodeLinkProvider).connect(node);
    await settle();
    final ctl = c.read(meshProvider.notifier);
    expect(ctl.nodeCanSettings, isFalse);
    await expectLater(ctl.readNodeSettings(), throwsA(isA<StateError>()));
    expect(node.requests.where((r) => r.hasGetSettings() || r.hasSetSettings()), isEmpty);
  });
}
