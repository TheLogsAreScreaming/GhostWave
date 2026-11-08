// dev.5 messaging: group channels, channel cards, key-change decisions,
// deleting messages, renaming the node.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/contact_card.dart';
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../link/fake_node.dart';
import 'mesh_controller_test.dart' show answeringNode, bob, settle;

Uint8List key(int seed) => Uint8List.fromList(List<int>.generate(32, (i) => (seed + i * 7) & 0xFF));

/// A protocol 1.1 node: channels and SetName, on top of [answeringNode].
class ChannelNode {
  ChannelNode({bool v11 = true}) : node = answeringNode() {
    node.protocolMinor = v11 ? 1 : 0;
    node.onRequest.listen((e) {
      final (c, r) = e;
      final id = r.reqId;
      switch (r.whichRequest()) {
        case pb.ToRadio_Request.listChannels:
          for (final MapEntry(key: name, value: psk) in channels.entries) {
            c.send(
              pb.FromRadio(
                reqId: id,
                channel: pb.Channel(name: name, psk: psk),
              ),
            );
          }
          c.send(
            pb.FromRadio(
              reqId: id,
              channelsEnd: pb.ChannelsEnd(count: channels.length),
            ),
          );
        case pb.ToRadio_Request.addChannel:
          final a = r.addChannel;
          if (a.psk.length != 32) {
            c.send(
              pb.FromRadio(
                reqId: id,
                error: pb.Error(code: pb.Error_Code.BAD_ARGUMENT),
              ),
            );
          } else {
            channels[a.name] = a.psk;
            c.send(pb.FromRadio(reqId: id, ok: pb.Ok()));
          }
        case pb.ToRadio_Request.removeChannel:
          final had = channels.remove(r.removeChannel.name) != null;
          c.send(
            had
                ? pb.FromRadio(reqId: id, ok: pb.Ok())
                : pb.FromRadio(
                    reqId: id,
                    error: pb.Error(code: pb.Error_Code.NOT_FOUND),
                  ),
          );
        case pb.ToRadio_Request.sendChannelText:
          final s = r.sendChannelText;
          if (!channels.containsKey(s.channel)) {
            c.send(
              pb.FromRadio(
                reqId: id,
                error: pb.Error(code: pb.Error_Code.NOT_FOUND),
              ),
            );
          } else {
            c.send(
              pb.FromRadio(
                reqId: id,
                sendQueued: pb.SendQueued(
                  dest: 0xFFFFFFFF,
                  msgId: 0x7000 + s.clientMsgId % 1000,
                  clientMsgId: s.clientMsgId,
                ),
              ),
            );
          }
        case pb.ToRadio_Request.setName:
          node.name = r.setName.name;
          c.send(pb.FromRadio(reqId: id, ok: pb.Ok()));
        default:
          break;
      }
    });
  }

  final FakeNode node;
  final Map<String, List<int>> channels = {};

  List<pb.ToRadio> requests(pb.ToRadio_Request kind) => [
    for (final r in node.requests)
      if (r.whichRequest() == kind) r,
  ];
}

void main() {
  late Directory dir;
  late ProviderContainer c;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-msg.');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    c = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs), meshStoreProvider.overrideWithValue(MeshStore(dir))],
    );
    c.listen(meshProvider, (_, _) {});
  });
  tearDown(() async {
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  MeshController ctl() => c.read(meshProvider.notifier);
  MeshState mesh() => c.read(meshProvider);

  group('channel cards', () {
    test('round trip, with spaces and colons in the name', () {
      final card = ChannelCard(name: 'trail: crew 2', psk: key(3));
      final text = card.encode();
      expect(text, startsWith('ghostwave-ch:trail%3A%20crew%202:'));
      final back = ChannelCard.tryParse('  $text\n')!;
      expect(back.name, 'trail: crew 2');
      expect(back.psk, key(3));
    });

    test('rejects malformed cards', () {
      final hex = hexEncode(key(1));
      for (final bad in [
        'ghostwave-ch:',
        'ghostwave-ch:name',
        'ghostwave-ch::$hex',
        'ghostwave-ch:name:${hex.substring(2)}',
        'ghostwave-ch:${'x' * 17}:$hex', // name over 16 bytes
        'ghostwave:1a2b3c4d:$hex', // a contact card
        'ghostwave-ch:a%ZZb:$hex',
      ]) {
        expect(ChannelCard.tryParse(bad), isNull, reason: bad);
      }
      // and a contact card parser does not take channel cards
      expect(ContactCard.tryParse('ghostwave-ch:name:$hex'), isNull);
    });
  });

  group('channels', () {
    test('a 1.1 node: channels load on connect, messages arrive, unread counts', () async {
      final n = ChannelNode()..channels['crew'] = key(5);
      c.read(nodeLinkProvider).connect(n.node);
      await settle();
      expect(ctl().nodeSupportsChannels, isTrue);
      expect(mesh().channels.keys, ['crew']);
      expect(mesh().channels['crew']!.pskHex, hexEncode(key(5)));

      final m = pb.ChannelMessage(channel: 'crew', src: bob, msgId: 9, text: utf8.encode('camp at 5'));
      n.node.last.send(pb.FromRadio(channelMessage: m));
      n.node.last.send(pb.FromRadio(channelMessage: m)); // repeat: dropped
      await settle();
      final got = mesh().channelMessages['crew']!;
      expect(got, hasLength(1));
      expect(got.single.text, 'camp at 5');
      expect(got.single.src, bob);
      expect(mesh().channelUnread['crew'], 1);
      expect(mesh().totalUnread, 1);
      ctl().markChannelRead('crew');
      expect(mesh().totalUnread, 0);
    });

    test('send: queued -> sent; offline messages go out on reconnect', () async {
      final n = ChannelNode()..channels['crew'] = key(5);
      c.read(nodeLinkProvider).connect(n.node);
      await settle();
      await ctl().sendChannelText('crew', 'on my way');
      await settle();
      final sent = n.requests(pb.ToRadio_Request.sendChannelText).single.sendChannelText;
      expect(sent.channel, 'crew');
      expect(utf8.decode(sent.text), 'on my way');
      expect(mesh().channelMessages['crew']!.single.state, MsgState.sent);

      c.read(nodeLinkProvider).disconnect();
      await settle();
      await ctl().sendChannelText('crew', 'written offline');
      expect(mesh().channelMessages['crew']!.last.state, MsgState.pending);
      c.read(nodeLinkProvider).connect(n.node);
      await settle();
      expect(n.requests(pb.ToRadio_Request.sendChannelText), hasLength(2));
      expect(mesh().channelMessages['crew']!.last.state, MsgState.sent);
    });

    test('an unknown channel fails, and can be retried', () async {
      final n = ChannelNode();
      c.read(nodeLinkProvider).connect(n.node);
      await settle();
      await ctl().sendChannelText('gone', 'hello?');
      final m = mesh().channelMessages['gone']!.single;
      expect(m.state, MsgState.failed);
      n.channels['gone'] = key(1);
      await ctl().retryChannel(m);
      expect(mesh().channelMessages['gone']!.single.state, MsgState.sent);
    });

    test('create, join and leave', () async {
      final n = ChannelNode();
      c.read(nodeLinkProvider).connect(n.node);
      await settle();
      final card = await ctl().createChannel('new one');
      await settle();
      expect(card.psk, hasLength(32));
      expect(n.channels['new one'], card.psk);
      expect(mesh().channels.keys, contains('new one'));

      await ctl().joinChannel(ChannelCard(name: 'theirs', psk: key(9)));
      await settle();
      expect(n.channels['theirs'], key(9));
      n.node.last.send(
        pb.FromRadio(
          channelMessage: pb.ChannelMessage(channel: 'theirs', src: bob, msgId: 1, text: [104, 105]),
        ),
      );
      await settle();
      await ctl().leaveChannel('theirs');
      await settle();
      expect(n.channels.containsKey('theirs'), isFalse);
      expect(mesh().channels.containsKey('theirs'), isFalse);
      expect(mesh().channelMessages.containsKey('theirs'), isFalse, reason: 'history goes too');
    });

    test('a 1.0 node: no channel requests, joining explains why not', () async {
      final n = ChannelNode(v11: false);
      c.read(nodeLinkProvider).connect(n.node);
      await settle();
      expect(ctl().nodeSupportsChannels, isFalse);
      expect(n.requests(pb.ToRadio_Request.listChannels), isEmpty);
      await expectLater(ctl().joinChannel(ChannelCard(name: 'x', psk: key(1))), throwsStateError);
    });

    test('channels and their messages are saved per node', () async {
      final n = ChannelNode()..channels['crew'] = key(5);
      c.read(nodeLinkProvider).connect(n.node);
      await settle();
      n.node.last.send(
        pb.FromRadio(
          channelMessage: pb.ChannelMessage(channel: 'crew', src: bob, msgId: 3, text: [111, 107]),
        ),
      );
      await settle();
      ctl().flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final saved = await MeshStore(dir).load(n.node.nodeId);
      expect(saved.channels.keys, ['crew']);
      expect(saved.channelMessages['crew']!.single.text, 'ok');
    });
  });

  group('deleting', () {
    test('a message, a conversation, a channel message, a channel history', () async {
      final n = ChannelNode()..channels['crew'] = key(5);
      c.read(nodeLinkProvider).connect(n.node);
      await settle();
      for (var i = 1; i <= 2; i++) {
        n.node.last.send(
          pb.FromRadio(
            text: pb.TextMessage(src: bob, msgId: i, text: utf8.encode('dm $i')),
          ),
        );
        n.node.last.send(
          pb.FromRadio(
            channelMessage: pb.ChannelMessage(channel: 'crew', src: bob, msgId: i, text: utf8.encode('ch $i')),
          ),
        );
      }
      await settle();
      ctl().deleteMessage(mesh().messages[bob]!.first);
      expect(mesh().messages[bob]!.map((m) => m.text), ['dm 2']);
      ctl().deleteThread(bob);
      expect(mesh().messages.containsKey(bob), isFalse);
      expect(mesh().unread.containsKey(bob), isFalse);
      ctl().deleteChannelMessage(mesh().channelMessages['crew']!.last);
      expect(mesh().channelMessages['crew']!.map((m) => m.text), ['ch 1']);
      ctl().clearChannelHistory('crew');
      expect(mesh().channelMessages.containsKey('crew'), isFalse);
      expect(mesh().channels.containsKey('crew'), isTrue, reason: 'still joined');
    });
  });

  group('key change', () {
    test('marks the contact unverified; accepting pins the new key', () async {
      final n = ChannelNode();
      c.read(nodeLinkProvider).connect(n.node);
      await settle();
      await ctl().addContact(ContactCard(nodeId: bob, ed25519Pub: key(1), name: 'bob'));
      expect(mesh().contacts[bob]!.verified, isTrue);
      n.node.last.send(
        pb.FromRadio(
          keyChange: pb.KeyChange(nodeId: bob, ed25519Pub: key(2), name: 'bob'.codeUnits),
        ),
      );
      await settle();
      final ct = mesh().contacts[bob]!;
      expect(ct.keyChanged, isTrue);
      expect(ct.verified, isFalse);
      expect(ct.pendingKeyHex, hexEncode(key(2)));

      await ctl().acceptKeyChange(bob);
      await settle();
      final add = n.requests(pb.ToRadio_Request.addContact).last.addContact;
      expect(add.nodeId, bob);
      expect(add.ed25519Pub, key(2));
      final after = mesh().contacts[bob]!;
      expect(after.keyChanged, isFalse);
      expect(after.verified, isTrue);
      expect(after.ed25519Hex, hexEncode(key(2)));
      expect(after.pendingKeyHex, isNull);
    });

    test('keeping the old key hides the warning but leaves it unverified', () async {
      final n = ChannelNode();
      c.read(nodeLinkProvider).connect(n.node);
      await settle();
      await ctl().addContact(ContactCard(nodeId: bob, ed25519Pub: key(1), name: 'bob'));
      n.node.last.send(
        pb.FromRadio(
          keyChange: pb.KeyChange(nodeId: bob, ed25519Pub: key(2)),
        ),
      );
      await settle();
      ctl().rejectKeyChange(bob);
      final ct = mesh().contacts[bob]!;
      expect(ct.keyChanged, isFalse);
      expect(ct.verified, isFalse);
      expect(ct.pendingKeyHex, isNull);
      expect(n.requests(pb.ToRadio_Request.addContact), hasLength(1), reason: 'nothing sent to the node');
    });
  });

  group('node name', () {
    test('SetName, then the new name shows in NodeInfo', () async {
      final n = ChannelNode();
      c.listen(nodeInfoProvider, (_, _) {});
      c.read(nodeLinkProvider).connect(n.node);
      await settle();
      await ctl().setNodeName('Ridge1');
      await settle();
      expect(n.requests(pb.ToRadio_Request.setName).single.setName.name, 'Ridge1');
      final info = (c.read(nodeLinkProvider).state as LinkUp).info;
      expect(utf8.decode(info.name), 'Ridge1');
      expect(utf8.decode(c.read(nodeInfoProvider)!.name), 'Ridge1');
    });
  });
}
