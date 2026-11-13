// Link check results as a path: one hop today, any number of hops later.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/link_check.dart';
import 'package:ghostwave_app/src/link/geo.dart';

void main() {
  final at = DateTime(2026, 11, 13, 14, 5);
  const base = LinkCheckNode(nodeId: 0x11111111, name: 'Base', pos: LatLon(45, -110));
  const ridge = LinkCheckNode(nodeId: 0x1A2B3C4D, name: 'Ridge', pos: LatLon(45.01, -110));

  test('a link ping is one hop with both readings', () {
    final c = LinkCheck.linkPing(
      origin: base,
      target: ridge,
      at: at,
      answered: true,
      forwardDbm: -97,
      reverseDbm: -112,
      elapsed: const Duration(milliseconds: 1400),
    );
    expect(c.kind, 'Link ping');
    expect((c.origin.name, c.target.name, c.hops.length), ('Base', 'Ridge', 1));
    expect((c.hops.single.forwardDbm, c.hops.single.reverseDbm), (-97, -112));
    expect(c.totalDistanceM, closeTo(1112, 2));
  });

  test('unanswered: no readings and no time, even if given', () {
    final c = LinkCheck.linkPing(
      origin: base,
      target: ridge,
      at: at,
      answered: false,
      forwardDbm: -97,
      elapsed: const Duration(seconds: 3),
    );
    expect(c.hops.single.forwardDbm, isNull);
    expect(c.elapsed, isNull);
  });

  test('multi-hop: distance only when every node has a position', () {
    const mid = LinkCheckNode(nodeId: 3, name: 'Mid');
    final c = LinkCheck(
      kind: 'Route',
      nodes: const [base, mid, ridge],
      hops: const [LinkCheckHop(forwardDbm: -100), LinkCheckHop(reverseDbm: -90)],
      at: at,
      answered: true,
    );
    expect(c.hopDistanceM(0), isNull);
    expect(c.totalDistanceM, isNull);
    expect([for (final n in c.placed) n.name], ['Base', 'Ridge']);
  });
}
