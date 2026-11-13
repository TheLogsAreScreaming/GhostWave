// Node journal: what is logged, what is kept, and how behaviour labels are
// read from it (with a confidence and the evidence behind each).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/node_journal.dart';
import 'package:ghostwave_app/src/link/geo.dart';

const int peak = 0x5EA4C0DE;
final DateTime t0 = DateTime.utc(2026, 11, 1, 12);

NodeJournal _roundTrip(NodeJournal j) => NodeJournal.fromJson(jsonDecode(jsonEncode(j.toJson())));

void main() {
  group('recording', () {
    test('first and last heard, count, hour, day and how it was heard', () {
      var j = const NodeJournal();
      j = j.record(peak, t0, HeardVia.beacon, rssiDbm: -101, pos: const LatLon(45, -110));
      j = j.record(peak, t0.add(const Duration(minutes: 30)), HeardVia.direct, rssiDbm: -95, name: 'Peak');
      j = j.record(peak, t0.add(const Duration(hours: 2)), HeardVia.beacon, rssiDbm: -110);
      final e = j.entries[peak]!;
      expect(e.firstHeard, t0);
      expect(e.lastHeard, t0.add(const Duration(hours: 2)));
      expect(e.timesHeard, 3);
      expect(e.hours, [hourKey(t0), hourKey(t0) + 2], reason: 'one entry per hour');
      expect(e.days, [dayKey(t0)]);
      expect(e.via, {HeardVia.beacon: 2, HeardVia.direct: 1});
      expect(e.bestRssi, -95);
      expect(e.lastRssi, -110);
      expect(e.name, 'Peak', reason: 'a later message without a name keeps it');
      expect(e.lastPos, const LatLon(45, -110));
      expect(j.listened, [hourKey(t0), hourKey(t0) + 2]);
    });

    test('hour detail is kept for 7 days, day detail for 60', () {
      var j = const NodeJournal();
      for (var h = 0; h < 24 * 70; h += 1) {
        j = j.record(peak, t0.add(Duration(hours: h)), HeardVia.beacon);
      }
      final e = j.entries[peak]!;
      expect(e.hours.length, kJournalHourWindow);
      expect(e.days.length, kJournalDayWindow);
      expect(j.listened.length, kJournalHourWindow);
      expect(e.timesHeard, 24 * 70);
    });

    test('positions are thinned to 100 m apart and capped', () {
      var j = const NodeJournal();
      // 30 m steps: only every fourth one is far enough from the last kept
      for (var i = 0; i < 12; i++) {
        j = j.record(peak, t0, HeardVia.beacon, pos: LatLon(45 + i * 0.00027, -110));
      }
      expect(j.entries[peak]!.fixes.length, 3);
      for (var i = 0; i < 40; i++) {
        j = j.record(peak, t0, HeardVia.beacon, pos: LatLon(46 + i * 0.01, -110));
      }
      expect(j.entries[peak]!.fixes.length, kJournalMaxFixes);
      expect(j.entries[peak]!.fixes.last, const LatLon(46.39, -110));
    });

    test('a replayed message counts the node, but not an hour or day', () {
      final j = const NodeJournal().record(peak, t0, HeardVia.direct, timed: false);
      final e = j.entries[peak]!;
      expect(e.timesHeard, 1);
      expect(e.hours, isEmpty);
      expect(e.days, isEmpty);
      expect(j.listened, isEmpty);
    });

    test('listening hours are counted once per hour', () {
      final j = const NodeJournal().markListening(t0);
      expect(identical(j.markListening(t0.add(const Duration(minutes: 59))), j), isTrue);
      expect(j.markListening(t0.add(const Duration(hours: 1))).listened, [hourKey(t0), hourKey(t0) + 1]);
    });

    test('the journal keeps at most $kJournalMaxNodes nodes, dropping the longest unheard', () {
      var j = const NodeJournal();
      for (var i = 1; i <= kJournalMaxNodes + 1; i++) {
        j = j.record(i, t0.add(Duration(seconds: i)), HeardVia.beacon);
      }
      expect(j.entries.length, kJournalMaxNodes);
      expect(j.entries.containsKey(1), isFalse);
      expect(j.entries.containsKey(kJournalMaxNodes + 1), isTrue);
    });
  });

  group('tags and notes', () {
    test('tags are trimmed, de-duplicated ignoring case, clipped and capped', () {
      expect(cleanTags(['  home  base ', 'Home Base', '', 'x' * 40, 'ok']), ['home base', 'x' * 24, 'ok']);
      expect(cleanTags([for (var i = 0; i < 20; i++) 't$i']).length, kJournalMaxTags);
    });

    test('tags and notes only apply to logged nodes; forget removes the entry', () {
      var j = const NodeJournal().record(peak, t0, HeardVia.beacon);
      expect(identical(j.withTags(0x1, ['a']), j), isTrue);
      j = j.withTags(peak, ['repeater', 'ridge']).withNote(peak, '  On the fire lookout.  ');
      expect(j.entries[peak]!.tags, ['repeater', 'ridge']);
      expect(j.entries[peak]!.note, 'On the fire lookout.');
      expect(j.withNote(peak, 'é' * 2000).entries[peak]!.note.runes.length, kJournalMaxNoteLength);
      expect(j.forget(peak).entries, isEmpty);
    });
  });

  group('saving', () {
    test('JSON round trip keeps everything', () {
      var j = const NodeJournal();
      j = j.record(peak, t0, HeardVia.beacon, pos: const LatLon(45, -110), rssiDbm: -99, name: 'Peak');
      j = j.record(peak, t0.add(const Duration(days: 1)), HeardVia.sos, pos: const LatLon(45.1, -110));
      j = j.withTags(peak, ['lookout']).withNote(peak, 'note');
      final back = _roundTrip(j).entries[peak]!;
      final e = j.entries[peak]!;
      expect(back.toJson(), e.toJson());
      expect(back.via, {HeardVia.beacon: 1, HeardVia.sos: 1});
      expect(back.fixes.length, 2);
      expect(_roundTrip(j).listened, j.listened);
    });

    test('malformed entries are dropped, not fatal', () {
      final j = NodeJournal.fromJson({
        'nodes': [
          {'id': 'x'},
          42,
          {'id': 7, 'first': 0, 'last': 0, 'via': 'bad', 'fix': 'bad', 'tags': 3},
        ],
        'listened': ['a', 5],
      });
      expect(j.entries.keys, [7]);
      expect(j.entries[7]!.via, isEmpty);
      expect(j.listened, [5]);
      expect(NodeJournal.fromJson('nonsense').isEmpty, isTrue);
    });

    test('saved with the node history (and so in backups)', () {
      final j = const NodeJournal().record(peak, t0, HeardVia.beacon).withTags(peak, ['camp']);
      final back = StoredMesh.fromJson(jsonDecode(jsonEncode(StoredMesh(journal: j).toJson())) as Map<String, Object?>);
      expect(back.journal.entries[peak]!.tags, ['camp']);
      expect(const StoredMesh().toJson().containsKey('journal'), isFalse, reason: 'old files stay the same');
      expect(StoredMesh.fromJson({}).journal.isEmpty, isTrue, reason: 'files from before the journal load');
    });
  });

  group('behaviour labels', () {
    test('always-on relay: heard every hour the app listened, from one place', () {
      var j = const NodeJournal();
      for (var h = 0; h < 30; h++) {
        j = j.record(peak, t0.add(Duration(hours: h)), HeardVia.beacon, pos: const LatLon(45, -110));
      }
      final now = t0.add(const Duration(hours: 29, minutes: 30));
      final r = describeNode(j.entries[peak]!, j, now);
      expect(r.first.trait, NodeTrait.steadyRelay);
      expect(r.first.percent, 100);
      expect(r.first.strength, 'likely');
      expect(r.first.evidence, contains('Heard in 30 of the 30 hours this app was listening in the last 7 days'));
      expect(r.first.evidence, contains('It reported one position'));
      expect(r.first.evidence, contains('Heard on 2 different days'));
    });

    test('heard only some of the listened hours is not a relay', () {
      var j = const NodeJournal();
      for (var h = 0; h < 30; h++) {
        j = j.markListening(t0.add(Duration(hours: h)));
        if (h % 3 == 0) j = j.record(peak, t0.add(Duration(hours: h)), HeardVia.beacon);
      }
      final r = describeNode(j.entries[peak]!, j, t0.add(const Duration(hours: 30)));
      expect(r.map((x) => x.trait), isNot(contains(NodeTrait.steadyRelay)));
    });

    test('roamer: positions kilometres apart', () {
      var j = const NodeJournal();
      for (var i = 0; i < 3; i++) {
        j = j.record(peak, t0.add(Duration(hours: i)), HeardVia.beacon, pos: LatLon(45 + i * 0.018, -110));
      }
      final r = describeNode(j.entries[peak]!, j, t0.add(const Duration(hours: 3)));
      expect(r.first.trait, NodeTrait.roamer);
      expect(r.first.percent, 68);
      expect(r.first.evidence, ['Its reported positions span 4.0 km', '3 distinct positions logged']);
      // a moving node is never called an always-on relay
      expect(r.map((x) => x.trait), isNot(contains(NodeTrait.steadyRelay)));
    });

    test('regular: many days, not always on', () {
      var j = const NodeJournal();
      for (final d in [20, 15, 10, 5, 0]) {
        j = j.record(peak, t0.subtract(Duration(days: d)), HeardVia.beacon);
      }
      final r = describeNode(j.entries[peak]!, j, t0);
      expect(r.single.trait, NodeTrait.regular);
      expect(r.single.percent, 50);
      expect(r.single.evidence.first, 'Heard on 5 of the last 30 days');
    });

    test('rarely heard: once, weeks ago', () {
      final j = const NodeJournal().record(peak, t0, HeardVia.beacon);
      final r = describeNode(j.entries[peak]!, j, t0.add(const Duration(days: 20)));
      expect(r.single.trait, NodeTrait.rarelyHeard);
      expect(r.single.percent, 80);
      expect(r.single.evidence, ['Heard only 1 time since it was first logged 20 days ago', 'Last heard 20 days ago']);
    });

    test('new arrival: less sure while the app has listened little', () {
      final j = const NodeJournal().record(peak, t0, HeardVia.beacon);
      final r = describeNode(j.entries[peak]!, j, t0.add(const Duration(minutes: 20)));
      expect(r.single.trait, NodeTrait.newcomer);
      expect(r.single.percent, 41);
      expect(r.single.evidence, ['First logged 20 min ago', 'This app has only listened for 1 hour this week']);
    });

    test('talker: sends messages', () {
      var j = const NodeJournal();
      for (var i = 0; i < 4; i++) {
        j = j.record(peak, t0, HeardVia.direct);
      }
      j = j.record(peak, t0, HeardVia.channel);
      final r = describeNode(j.entries[peak]!, j, t0.add(const Duration(days: 4)));
      expect(r.single.trait, NodeTrait.talker);
      expect(r.single.percent, 50);
      expect(r.single.evidence, ['Sent you 4 direct messages', 'Posted 1 channel message you received']);
    });

    test('not enough to go on: no label at all', () {
      var j = const NodeJournal();
      for (var h = 0; h < 3; h++) {
        j = j.record(peak, t0.add(Duration(hours: h)), HeardVia.beacon);
      }
      expect(describeNode(j.entries[peak]!, j, t0.add(const Duration(days: 4))), isEmpty);
    });

    test('distance text uses the formatter it is given', () {
      var j = const NodeJournal();
      j = j.record(peak, t0, HeardVia.beacon, pos: const LatLon(45, -110));
      j = j.record(peak, t0, HeardVia.beacon, pos: const LatLon(45.02, -110));
      final r = describeNode(j.entries[peak]!, j, t0, distance: (m) => '${(m / 1609.344).toStringAsFixed(1)} mi');
      expect(r.firstWhere((x) => x.trait == NodeTrait.roamer).evidence.first, 'Its reported positions span 1.4 mi');
    });
  });
}
