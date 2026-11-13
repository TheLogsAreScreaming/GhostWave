// Timeline: one feed built from saved history, newest first; each kind has a
// filter; signal changes are logged only past the threshold.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/data/node_journal.dart';
import 'package:ghostwave_app/src/data/timeline.dart';
import 'package:ghostwave_app/src/link/geo.dart';

const int ridge = 0x1A2B3C4D;
const int rover = 0x0C0FFEE0;
final DateTime t0 = DateTime(2026, 11, 13, 9);

String name(int id) => id == ridge
    ? 'Ridge'
    : id == rover
    ? 'Rover'
    : '$id';

List<TimelineEvent> sample() => buildTimeline(
  nameOf: name,
  messages: {
    ridge: [
      ChatMessage(peer: ridge, outgoing: false, text: 'hello  there', at: t0, rssiDbm: -97),
      ChatMessage(
        peer: ridge,
        outgoing: true,
        text: "[Check-in] I'm OK · 45.10000, -110.20000",
        at: t0.add(const Duration(minutes: 5)),
      ),
      ChatMessage(peer: ridge, outgoing: true, text: '[Coverage] 3', at: t0.add(const Duration(minutes: 6))),
    ],
  },
  channelMessages: {
    'crew': [
      ChannelMessage(
        channel: 'crew',
        outgoing: false,
        src: rover,
        text: 'on the trail',
        at: t0.add(const Duration(minutes: 1)),
      ),
    ],
  },
  journal: const NodeJournal().record(
    rover,
    t0.subtract(const Duration(hours: 1)),
    HeardVia.beacon,
    pos: const LatLon(45, -110),
  ),
  signalLog: [SignalShift(nodeId: rover, fromDbm: -110, toDbm: -95, at: t0.add(const Duration(minutes: 2)))],
  alerts: [
    SosAlertEntry(src: rover, seq: 1, receivedAt: t0.add(const Duration(minutes: 3)), text: 'ankle', batteryPct: 40),
  ],
  ownSos: OwnSos(
    text: 'need help',
    startedAt: t0.add(const Duration(minutes: 7)),
    acks: [SosAck(responder: ridge, seq: 1, at: t0.add(const Duration(minutes: 8)))],
  ),
);

void main() {
  test('builds every kind, newest first, and leaves coverage probes out', () {
    final all = sample();
    expect(
      [for (final e in all) e.title],
      [
        'Ridge answered your SOS',
        'You raised an SOS',
        'You shared your position with Ridge',
        'SOS from Rover',
        'Rover stronger by 15 dB',
        'Rover in #crew',
        'Ridge to you',
        'First heard Rover',
      ],
    );
    expect(all.any((e) => e.detail.contains('[Coverage]')), isFalse);
    final pos = all.firstWhere((e) => e.kind == TimelineKind.position);
    expect(pos.pos, const LatLon(45.1, -110.2));
    expect(pos.detail, "I'm OK · 45.10000, -110.20000");
    expect(all.firstWhere((e) => e.title == 'Ridge to you').detail, 'hello there · -97 dBm');
    expect(all.firstWhere((e) => e.kind == TimelineKind.alert && e.nodeId == rover).detail, 'ankle · battery 40%');
    expect(all.firstWhere((e) => e.kind == TimelineKind.node).detail, 'New node 0c0ffee0 (beacon)');
  });

  test('filters by kind and by words, node ID or channel', () {
    final all = sample();
    expect(filterTimeline(all, {TimelineKind.signal}, ''), hasLength(1));
    expect(filterTimeline(all, {TimelineKind.alert}, '').length, 3);
    expect(filterTimeline(all, {...TimelineKind.values}, 'CREW').single.channel, 'crew');
    expect(filterTimeline(all, {...TimelineKind.values}, '0c0ffee0').length, 4);
    expect(filterTimeline(all, {}, ''), isEmpty);
  });

  test('signal changes are logged at the threshold, not below it, and capped', () {
    var log = <SignalShift>[];
    log = recordSignal(log, rover, null, -90, t0);
    expect(log, isEmpty, reason: 'no earlier reading');
    log = recordSignal(log, rover, -90, -90 - kSignalShiftDb + 1, t0);
    expect(log, isEmpty);
    log = recordSignal(log, rover, -90, -90 - kSignalShiftDb, t0);
    expect(log.single.deltaDb, -kSignalShiftDb);
    for (var i = 0; i < kSignalLogMax + 5; i++) {
      log = recordSignal(log, rover, -80, -100, t0.add(Duration(seconds: i)));
    }
    expect(log, hasLength(kSignalLogMax));
    expect(log.last.at, t0.add(const Duration(seconds: kSignalLogMax + 4)));
  });

  test('the signal log survives a save, and bad entries are skipped', () {
    final s = SignalShift(nodeId: ridge, fromDbm: -100, toDbm: -88, at: t0);
    final stored = StoredMesh(signalLog: [s]);
    final back = StoredMesh.fromJson(stored.toJson());
    expect(back.signalLog, [s]);
    expect(
      signalLogFromJson([
        s.toJson(),
        'junk',
        [1, 2],
      ]),
      [s],
    );
    expect(const StoredMesh().toJson().containsKey('signal'), isFalse);
  });
}
