// Waypoint text: round-trips through the formatter and parser, always fits one
// radio message, and hostile or malformed text stays ordinary text. The book
// applies edits and removals per sender, keeps the user's hidden flag, caps
// its size, and survives a JSON round trip with damaged entries dropped.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/timeline.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/data/waypoints.dart';
import 'package:ghostwave_app/src/link/geo.dart';

const int ann = 0xA0000001, ben = 0xB0000002;

WaypointPut put({
  String id = '3fa2',
  WaypointKind kind = WaypointKind.water,
  String name = 'Spring',
  LatLon pos = const LatLon(45.123456, -110.654321),
  String note = '',
}) => WaypointPut(id: id, kind: kind, name: name, pos: pos, note: note);

void main() {
  group('text form', () {
    test('every kind round-trips, with and without a note, in one 73-byte DM', () {
      for (final k in WaypointKind.values) {
        for (final note in ['', 'Filter it first']) {
          final t = waypointText(put(kind: k, note: note), 73)!;
          expect(utf8.encode(t).length, lessThanOrEqualTo(73));
          final back = parseWaypoint(t)! as WaypointPut;
          expect(back.id, '3fa2');
          expect(back.kind, k);
          expect(back.name, 'Spring');
          expect(back.note, note);
          expect(back.pos.lat, closeTo(45.12346, 1e-9));
          expect(back.pos.lon, closeTo(-110.65432, 1e-9));
        }
      }
      expect(
        waypointText(put(note: 'Filter it'), 200),
        '[WP 3fa2 water] Spring · 45.12346,-110.65432 · Filter it',
        reason: 'readable as plain text on apps without waypoints',
      );
    });

    test('a long note is cut first, then the name; never over the limit', () {
      final long = put(kind: WaypointKind.parking, name: 'N' * 32, note: 'x' * 120, pos: const LatLon(-89.5, -179.5));
      for (var max = 0; max < 220; max++) {
        final t = waypointText(long, max);
        if (t == null) {
          expect(max, lessThan(44), reason: 'only a tiny budget fails');
          continue;
        }
        expect(utf8.encode(t).length, lessThanOrEqualTo(max));
        expect(parseWaypoint(t), isA<WaypointPut>());
      }
      final t73 = parseWaypoint(waypointText(long, 73)!)! as WaypointPut;
      expect(t73.note, isEmpty);
      expect(t73.name, 'N' * 31);
    });

    test('multi-byte names are never split mid-character', () {
      final t = waypointText(put(name: 'Ñandú 🏕️ camp', note: '水' * 50), 73)!;
      expect(utf8.encode(t).length, lessThanOrEqualTo(73));
      final back = parseWaypoint(t)! as WaypointPut;
      expect(back.name, 'Ñandú 🏕️ camp');
      expect(back.note, '水水水', reason: 'whole characters only, no replacement marks');
    });

    test('an empty name becomes the kind; the separator in a name is replaced', () {
      expect((parseWaypoint(waypointText(put(name: '  '), 200)!)! as WaypointPut).name, 'Water');
      final t = waypointText(put(name: 'a · 1.0,2.0 · b'), 200)!;
      final back = parseWaypoint(t)! as WaypointPut;
      expect(back.name, 'a - 1.0,2.0 - b');
      expect(back.pos.lat, closeTo(45.12346, 1e-9));
    });

    test('removal text round-trips and fits', () {
      final t = waypointRemovalText('00af', 'Old camp', 73);
      expect(t, '[WP 00af removed] Old camp');
      final back = parseWaypoint(t)! as WaypointRemoval;
      expect(back.id, '00af');
      expect(back.name, 'Old camp');
      expect(waypointRemovalText('00af', 'x' * 32, 20), '[WP 00af removed] xx');
      expect(waypointRemovalText('00af', 'x' * 32, 18), '[WP 00af removed]');
      expect(parseWaypoint('[WP 00af removed]'), isA<WaypointRemoval>());
    });

    test('bad IDs are refused when sending', () {
      expect(() => waypointText(put(id: 'XYZ1'), 100), throwsArgumentError);
      expect(() => waypointRemovalText('12345', '', 100), throwsArgumentError);
    });
  });

  group('hostile and near-miss input stays plain text', () {
    for (final t in <String>[
      '',
      'hello',
      '[WP]',
      '[WP 3fa2 water]',
      '[WP 3fa2 water] Spring',
      '[WP 3fa2 water] Spring · 45.1',
      '[WP 3fa2 water] Spring · 95.00000,10.00000',
      '[WP 3fa2 water] Spring · 45.00000,181.00000',
      '[WP 3fa2 water] Spring · 45.00000,-110.0000000001',
      '[WP 3FA2 water] Spring · 45.00000,-110.00000',
      '[WP 3fa water] Spring · 45.00000,-110.00000',
      '[WP 3fa2 Water] Spring · 45.00000,-110.00000',
      '[WP 3fa2 water]  · 45.00000,-110.00000',
      '[WP 3fa2 water] \u202E\u0000 · 45.00000,-110.00000',
      '[WP 3fa2 removed] Spring · 45.00000,-110.00000 extra\nline',
      '[WP 3fa2 water] Spring · 45.00000,-110.00000\n[WP 3fa3 water] Two · 1.0,2.0',
      '[WP 3fa2 water] Spring · NaN,Infinity',
      ' [WP 3fa2 water] Spring · 45.00000,-110.00000',
      '[WP 3fa2 water] ${'x' * 1200} · 45.00000,-110.00000',
      '[Check-in] At camp · 45.00000, -110.00000',
    ]) {
      test(t.length > 40 ? '${t.substring(0, 40)}…' : t, () => expect(parseWaypoint(t), isNull));
    }

    test('control and direction characters in name and note are blanked', () {
      final w = parseWaypoint('[WP 0001 hazard] Rock\u202Efall\u0007 · 1.00000,2.00000 · Loose\u200F  scree\t!')!;
      w as WaypointPut;
      expect(w.name, 'Rock fall');
      expect(w.note, 'Loose scree !');
    });

    test('an unknown kind from a newer app is shown as Other', () {
      final w = parseWaypoint('[WP 0001 shelter] Hut · 1.00000,2.00000')! as WaypointPut;
      expect(w.kind, WaypointKind.other);
    });

    test('random garbage never throws', () {
      final rng = Random(7);
      const alphabet = '[WP ]0123456789abcdef·,.- removedwatercamp\n\u202E';
      for (var i = 0; i < 2000; i++) {
        final s = String.fromCharCodes(
          List.generate(rng.nextInt(80), (_) => alphabet.codeUnitAt(rng.nextInt(alphabet.length))),
        );
        parseWaypoint('[WP $s');
      }
    });
  });

  group('book', () {
    final t0 = DateTime(2026, 11, 14, 9);
    Waypoint mine(String id, {DateTime? at}) =>
        Waypoint(id: id, kind: WaypointKind.camp, name: 'Camp $id', pos: const LatLon(1, 2), at: at ?? t0);

    test('a sender edits and removes only its own pins', () {
      var b = const WaypointBook();
      b = b.receive(ann, put(), t0, peer: ann);
      b = b.receive(ben, put(), t0, channel: 'crew');
      expect(b.byKey.keys.toSet(), {'a0000001:3fa2', 'b0000002:3fa2'});
      b = b.receive(ann, put(name: 'Spring 2'), t0.add(const Duration(minutes: 1)), peer: ann);
      expect(b.byKey['a0000001:3fa2']!.name, 'Spring 2');
      expect(b.byKey['b0000002:3fa2']!.name, 'Spring');
      b = b.receive(ann, const WaypointRemoval(id: '3fa2'), t0);
      expect(b.byKey.keys, ['b0000002:3fa2']);
      expect(b.byKey['b0000002:3fa2']!.channel, 'crew');
    });

    test('hidden stays hidden through an edit; ours cannot be hidden', () {
      var b = const WaypointBook().receive(ann, put(), t0).put(mine('0001'));
      b = b.setHidden('a0000001:3fa2', true).setHidden('me:0001', true);
      expect(b.byKey['me:0001']!.hidden, isFalse);
      b = b.receive(ann, put(name: 'Moved'), t0);
      expect(b.byKey['a0000001:3fa2']!.hidden, isTrue);
      expect(b.byKey['a0000001:3fa2']!.name, 'Moved');
      expect(b.setHidden('a0000001:3fa2', false).byKey['a0000001:3fa2']!.hidden, isFalse);
    });

    test('capped: the oldest received go first, ours stay', () {
      var b = const WaypointBook().put(mine('0001', at: DateTime(2000)));
      for (var i = 0; i < kMaxWaypoints + 5; i++) {
        b = b.receive(ann + i, put(), t0.add(Duration(seconds: i)));
      }
      expect(b.byKey, hasLength(kMaxWaypoints));
      expect(b.byKey.containsKey('me:0001'), isTrue);
      expect(b.byKey.containsKey(waypointKey(ann, '3fa2')), isFalse);
      expect(b.byKey.containsKey(waypointKey(ann + kMaxWaypoints + 4, '3fa2')), isTrue);
    });

    test('JSON round trip; damaged entries are dropped', () {
      final b = const WaypointBook()
          .put(mine('0001').copyWith(note: 'by the lake', channel: 'crew'))
          .receive(ann, put(note: 'n'), t0, peer: ann)
          .setHidden('a0000001:3fa2', true);
      final json = jsonDecode(jsonEncode(b.toJson())) as List<Object?>;
      final back = WaypointBook.fromJson([
        ...json,
        'junk',
        {'id': 'zz', 'kind': 'camp', 'name': 'x', 'lat': 1, 'lon': 2, 'at': 0},
        {'id': '0002', 'kind': 'camp', 'name': 'x', 'lat': 100, 'lon': 2, 'at': 0},
        {'id': '0003', 'kind': 'camp', 'name': '', 'lat': 1, 'lon': 2, 'at': 0},
        {'id': '0004', 'kind': 'camp', 'name': 'x', 'lat': 1, 'lon': 2, 'at': 0, 'owner': 'evil'},
      ]);
      expect(back.byKey.keys.toSet(), {'me:0001', 'a0000001:3fa2'});
      final m = back.byKey['me:0001']!;
      expect((m.note, m.channel, m.mine, m.shared), ('by the lake', 'crew', true, true));
      final o = back.byKey['a0000001:3fa2']!;
      expect((o.owner, o.peer, o.hidden, o.note, o.kind), (ann, ann, true, 'n', WaypointKind.water));
      expect(WaypointBook.fromJson(null).isEmpty, isTrue);
      expect(WaypointBook.fromJson({'a': 1}).isEmpty, isTrue);
    });

    test('new IDs avoid ones in use', () {
      final taken = {for (var i = 0; i < 0xFFFF; i++) i.toRadixString(16).padLeft(4, '0')};
      expect(newWaypointId(Random(1), taken), 'ffff');
    });
  });

  test('timeline: waypoints get their own entries, in DMs and channels', () {
    final at = DateTime(2026, 11, 14, 10);
    final events = buildTimeline(
      nameOf: (id) => id == ann ? 'Ann' : 'node',
      messages: {
        ann: [
          ChatMessage(
            peer: ann,
            outgoing: false,
            text: waypointText(put(note: 'cold'), 200)!,
            at: at,
          ),
          ChatMessage(peer: ann, outgoing: true, text: waypointRemovalText('0001', 'Old', 73), at: at),
        ],
      },
      channelMessages: {
        'crew': [
          ChannelMessage(
            channel: 'crew',
            outgoing: false,
            src: ann,
            text: waypointText(put(kind: WaypointKind.hazard, name: 'Bees'), 86)!,
            at: at,
          ),
        ],
      },
    );
    final wps = events.where((e) => e.kind == TimelineKind.waypoint).toList();
    expect(wps, hasLength(3));
    expect(events.where((e) => e.kind == TimelineKind.message), isEmpty);
    final dm = wps.firstWhere((e) => e.title == 'Ann shared a waypoint');
    expect(dm.detail, 'Water · Spring · 45.12346, -110.65432 · cold');
    expect(dm.pos, isNotNull);
    expect(wps.any((e) => e.title == 'You removed a waypoint with Ann' && e.detail == 'Old'), isTrue);
    final ch = wps.firstWhere((e) => e.channel == 'crew');
    expect(ch.title, 'Ann shared a waypoint in #crew');
    expect(filterTimeline(events, {TimelineKind.waypoint}, 'bees'), [ch]);
  });
}
