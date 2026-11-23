// Live traffic: which node events count as packets heard, which colour kind
// each one maps to, the route a trace answer took, and the view's filter.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/traffic.dart';
import 'package:ghostwave_app/src/data/traffic.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/ui/traffic_map.dart';

const int me = 0x00000009;
const int ridge = 0xCAFE0003;
const int relayA = 0x0000A001;
const int relayB = 0x0000B002;

final DateTime now = DateTime.utc(2026, 11, 18, 12);

TrafficPacket? heard(pb.FromRadio e, {int? own = me}) => packetFromEvent(e, own: own, now: now);

void main() {
  group('packetFromEvent', () {
    test('a beacon is an advert heard straight from its sender', () {
      final p = heard(pb.FromRadio(neighbor: pb.Neighbor(nodeId: ridge, rssiDbm: -88)))!;
      expect(p.kind, TrafficKind.advert);
      expect(p.path, [ridge, me]);
      expect(p.hops, 1);
      expect(p.lastHop, ridge);
      expect(p.rssiDbm, -88);
      expect(p.at, now);
    });

    test('each packet kind maps onto one of the six colours', () {
      final cases = <pb.FromRadio, TrafficKind>{
        pb.FromRadio(peerIdent: pb.PeerIdent(nodeId: ridge)): TrafficKind.advert,
        pb.FromRadio(text: pb.TextMessage(src: ridge, rssiDbm: -90)): TrafficKind.direct,
        pb.FromRadio(channelMessage: pb.ChannelMessage(src: ridge)): TrafficKind.channel,
        pb.FromRadio(delivered: pb.Delivered(dest: ridge)): TrafficKind.ack,
        pb.FromRadio(sosAck: pb.SosAckReceived(responder: ridge)): TrafficKind.ack,
        pb.FromRadio(linkPingResult: pb.LinkPingResult(nodeId: ridge, answered: true)): TrafficKind.ack,
        pb.FromRadio(sos: pb.SosAlert(src: ridge)): TrafficKind.other,
        pb.FromRadio(sosCancelled: pb.SosCancelled(src: ridge)): TrafficKind.other,
      };
      cases.forEach((e, kind) {
        final p = heard(e);
        expect(p?.kind, kind, reason: '${e.whichEvent()}');
        expect(p?.path, [ridge, me], reason: 'sender, then us: relays are not reported');
        expect(p?.pathKnown, isFalse);
      });
    });

    test('a trace answer draws every relay of its way back, ending at us', () {
      final p = heard(
        pb.FromRadio(
          traceResult: pb.TraceResult(
            nodeId: ridge,
            answered: true,
            forwardNodes: [relayA, ridge],
            forwardRssiDbm: [-80, -95],
            backNodes: [relayB, relayA, me],
            backRssiDbm: [-99, -91, -84],
          ),
        ),
      )!;
      expect(p.kind, TrafficKind.trace);
      expect(p.path, [ridge, relayB, relayA, me]);
      expect(p.pathKnown, isTrue);
      expect(p.hops, 3);
      expect(p.lastHop, relayA);
      expect(p.rssiDbm, -84);
    });

    test('a trace answered straight from the target has it as the last hop', () {
      final p = heard(
        pb.FromRadio(
          traceResult: pb.TraceResult(nodeId: ridge, answered: true, backNodes: [me], backRssiDbm: [-70]),
        ),
      )!;
      expect(p.path, [ridge, me]);
      expect(p.lastHop, ridge);
      expect(p.hops, 1);
    });

    test('not packets: replays, unanswered checks, our own node, status', () {
      expect(heard(pb.FromRadio(replayed: true, text: pb.TextMessage(src: ridge))), isNull);
      expect(heard(pb.FromRadio(traceResult: pb.TraceResult(nodeId: ridge))), isNull);
      expect(heard(pb.FromRadio(linkPingResult: pb.LinkPingResult(nodeId: ridge))), isNull);
      expect(heard(pb.FromRadio(neighbor: pb.Neighbor(nodeId: me))), isNull);
      expect(heard(pb.FromRadio(text: pb.TextMessage(src: 0xFFFFFFFF))), isNull);
      expect(heard(pb.FromRadio(status: pb.Status())), isNull);
    });

    test('before our node ID is known the route is only the sender', () {
      expect(heard(pb.FromRadio(text: pb.TextMessage(src: ridge)), own: null)!.path, [ridge]);
    });
  });

  test('the six kinds have six different colours', () {
    final colours = {for (final k in TrafficKind.values) trafficColor(k)};
    expect(colours, hasLength(TrafficKind.values.length));
  });

  group('TrafficController', () {
    late ProviderContainer c;
    setUp(() {
      c = ProviderContainer();
      addTearDown(c.dispose);
    });

    TrafficPacket packet(TrafficKind k) => TrafficPacket(kind: k, path: const [ridge, me], at: now);

    test('keeps the newest packets first, only of the shown kinds', () {
      final ctl = c.read(trafficProvider.notifier)
        ..setOn(true)
        ..add(packet(TrafficKind.advert))
        ..add(packet(TrafficKind.direct));
      expect([for (final p in c.read(trafficProvider).recent) p.kind], [TrafficKind.direct, TrafficKind.advert]);
      expect(c.read(trafficProvider).serial, 2);

      ctl.setKind(TrafficKind.advert, false);
      expect([for (final p in c.read(trafficProvider).recent) p.kind], [TrafficKind.direct]);
      ctl.add(packet(TrafficKind.advert));
      expect(c.read(trafficProvider).recent, hasLength(1), reason: 'hidden kinds are not kept');
    });

    test('remembers at most $kTrafficKeep packets; off forgets them', () {
      final ctl = c.read(trafficProvider.notifier)..setOn(true);
      for (var i = 0; i < kTrafficKeep + 5; i++) {
        ctl.add(packet(TrafficKind.channel));
      }
      expect(c.read(trafficProvider).recent, hasLength(kTrafficKeep));
      ctl.setOn(false);
      expect(c.read(trafficProvider).recent, isEmpty);
      expect(c.read(trafficProvider).on, isFalse);
    });
  });
}
