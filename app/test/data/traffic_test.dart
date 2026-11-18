// Route building for the live traffic map: path → map points, hops without a
// position skipped, the words on the route card, and the animation queue.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/traffic.dart';
import 'package:ghostwave_app/src/link/geo.dart';

const _a = LatLon(46.0, -114.0);
const _b = LatLon(46.1, -114.1);
const _me = LatLon(46.2, -114.2);

final _at = DateTime.utc(2026, 11, 18, 12);

TrafficPacket _p(List<int> path, {TrafficKind kind = TrafficKind.trace, int? hops, int? lastHop, int? rssi}) =>
    TrafficPacket(kind: kind, path: path, at: _at, pathKnown: true, hops: hops, lastHop: lastHop, rssiDbm: rssi);

void main() {
  final positions = {1: _a, 2: _b, 9: _me};
  LatLon? posOf(int id) => positions[id];
  String nameOf(int id) => switch (id) {
    1 => 'Ridge',
    2 => 'Saddle',
    9 => 'You',
    _ => id.toRadixString(16).padLeft(8, '0'),
  };

  group('buildRoute', () {
    test('every hop with a position becomes a point, in order', () {
      final r = buildRoute(_p([1, 2, 9]), posOf);
      expect(r.points, const [RoutePoint(1, _a), RoutePoint(2, _b), RoutePoint(9, _me)]);
      expect(r.legs, 2);
      expect(r.drawable, isTrue);
      expect(r.offMap, isEmpty);
    });

    test('a hop with no position is skipped: the line jumps to the next known one', () {
      final r = buildRoute(_p([1, 0x77, 2, 0x88, 9]), posOf);
      expect([for (final p in r.points) p.node], [1, 2, 9]);
      expect(r.legs, 2);
      expect(r.offMap, [0x77, 0x88]);
    });

    test('a node listed twice in a row is drawn once; one off the map is counted once', () {
      final r = buildRoute(_p([1, 1, 0x77, 0x77, 9]), posOf);
      expect([for (final p in r.points) p.node], [1, 9]);
      expect(r.offMap, [0x77]);
    });

    test('two hops at the same spot do not make a zero-length leg', () {
      final r = buildRoute(_p([1, 2, 9]), (id) => id == 9 ? _me : _a);
      expect([for (final p in r.points) p.node], [1, 9]);
    });

    test('only one known hop: nothing to draw, but it is still a point', () {
      final r = buildRoute(_p([0x77, 9]), posOf);
      expect(r.points, const [RoutePoint(9, _me)]);
      expect(r.legs, 0);
      expect(r.drawable, isFalse);
      expect(r.offMap, [0x77]);
    });

    test('no known hop at all: no points', () {
      final r = buildRoute(_p([0x77, 0x88]), posOf);
      expect(r.points, isEmpty);
      expect(r.offMap, [0x77, 0x88]);
    });
  });

  group('card text', () {
    test('the route reads sender to us, with names where known', () {
      expect(routeText(_p([1, 0x77, 9]), nameOf), 'Ridge → 00000077 → You');
      expect(routeText(_p([1, 1, 9]), nameOf), 'Ridge → You');
    });

    test('heard from the last hop, with the signal', () {
      expect(heardText(_p([1, 2, 9], lastHop: 2, rssi: -97), nameOf), 'Heard from Saddle · -97 dBm');
      expect(heardText(_p([1, 9]), nameOf), 'Heard');
      expect(heardText(_p([1, 9], rssi: -60), nameOf), 'Heard · -60 dBm');
    });

    test('hops, signal, hops off the map and age; unknown hops say so', () {
      final r = buildRoute(_p([1, 0x77, 2, 9], hops: 3, rssi: -101), posOf);
      expect(detailText(r, _at.add(const Duration(seconds: 4))), '3 hops · -101 dBm · 1 not on map · 4s ago');
      final direct = buildRoute(_p([1, 9], hops: 1), posOf);
      expect(detailText(direct, _at), 'Direct · 1 hop · 0 not on map · 0s ago');
      final unknown = buildRoute(_p([1, 9]), posOf);
      expect(detailText(unknown, _at), startsWith('Hops unknown'));
    });
  });

  group('TrafficQueue', () {
    TrafficRoute route(int n) => buildRoute(_p([n, 9]), posOf);

    test('at most three animate; the rest wait their turn in order', () {
      final q = TrafficQueue();
      final rs = [for (var i = 0; i < 5; i++) route(i)];
      expect([for (final r in rs) q.add(r)], [true, true, true, false, false]);
      expect(q.active, rs.sublist(0, 3));
      expect(q.waiting, rs.sublist(3));
      expect(q.finish(rs[1]), rs[3]);
      expect(q.active, [rs[0], rs[2], rs[3]]);
      expect(q.waiting, [rs[4]]);
    });

    test('a long backlog drops the oldest waiting route', () {
      final q = TrafficQueue(maxActive: 1, maxWaiting: 2);
      final rs = [for (var i = 0; i < 5; i++) route(i)];
      rs.forEach(q.add);
      expect(q.active, [rs[0]]);
      expect(q.waiting, [rs[3], rs[4]]);
    });

    test('finishing a route that is not animating changes nothing', () {
      final q = TrafficQueue(maxActive: 1);
      final a = route(1), b = route(2);
      q
        ..add(a)
        ..add(b);
      expect(q.finish(b), isNull);
      expect(q.active, [a]);
      q.clear();
      expect(q.active, isEmpty);
      expect(q.waiting, isEmpty);
    });
  });
}
