/// Coverage walks: while you move, ping one node every so often from wherever
/// the phone's GPS says you are, and record whether each ping got through and
/// at what signal. Dots on the Map; CSV export.
///
/// A ping is an encrypted DM, `[Coverage] 7`, to the node you chose. Its fate
/// comes from the real delivery receipt (and the signal that receipt arrived
/// at, the last hop). A ping with no receipt after [kPingTimeout] counts as
/// failed; a receipt that arrives later still turns it delivered.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/coverage_sample.dart';
import '../data/models.dart';
import '../link/geo.dart';
import 'location_share.dart';
import 'mesh_controller.dart';
import 'providers.dart';

/// Ping text prefix. Receiving apps keep these out of notifications and unread.
const kCoveragePrefix = '[Coverage] ';

/// Without a receipt after this long, a ping counts as failed.
const Duration kPingTimeout = Duration(minutes: 3);

/// A fix older than this is not used: you may have moved since.
const Duration kFixMaxAge = Duration(seconds: 30);

/// Most pings kept in one walk.
const kMaxPings = 1000;

/// Most walks kept.
const kMaxWalks = 20;

/// Allowed ping intervals, seconds. 30 s at least, to respect airtime.
const kPingIntervals = [30, 60, 120];

/// One ping: where you were and which message carried it.
class CoveragePing {
  /// Creates a ping.
  const CoveragePing({required this.n, required this.clientMsgId, required this.pos, required this.at});

  /// From [toJson]; null if malformed.
  static CoveragePing? fromJson(Object? j) {
    if (j is! Map) return null;
    final n = j['n'], c = j['c'], lat = j['lat'], lon = j['lon'], at = j['at'];
    if (n is! int || c is! int || lat is! num || lon is! num || at is! int) return null;
    return CoveragePing(
      n: n,
      clientMsgId: c,
      pos: LatLon(lat.toDouble(), lon.toDouble()),
      at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
    );
  }

  /// Ping number in its walk, from 1.
  final int n;

  /// The DM's client message ID, to find its delivery state.
  final int clientMsgId;

  /// The phone's fix when it was sent.
  final LatLon pos;

  /// When it was sent, UTC.
  final DateTime at;

  /// JSON form.
  Map<String, Object> toJson() => {
    'n': n,
    'c': clientMsgId,
    'lat': pos.lat,
    'lon': pos.lon,
    'at': at.toUtc().millisecondsSinceEpoch,
  };
}

/// One walk toward one node.
class CoverageWalk {
  /// Creates a walk.
  const CoverageWalk({
    required this.id,
    required this.dest,
    required this.startedAt,
    required this.intervalS,
    this.endedAt,
    this.pings = const [],
    this.skippedNoFix = 0,
  });

  /// From [toJson]; null if malformed.
  static CoverageWalk? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], dest = j['dest'], start = j['start'], every = j['every'];
    if (id is! String || dest is! int || start is! int || every is! int) return null;
    return CoverageWalk(
      id: id,
      dest: dest,
      startedAt: DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
      intervalS: every,
      endedAt: j['end'] is int ? DateTime.fromMillisecondsSinceEpoch(j['end'] as int, isUtc: true) : null,
      pings: [for (final p in (j['pings'] as List<Object?>?) ?? const <Object?>[]) ?CoveragePing.fromJson(p)],
      skippedNoFix: (j['nofix'] as int?) ?? 0,
    );
  }

  /// Stable ID.
  final String id;

  /// The node pinged.
  final int dest;

  /// When the walk started, UTC.
  final DateTime startedAt;

  /// Seconds between pings.
  final int intervalS;

  /// When it was stopped; null while running.
  final DateTime? endedAt;

  /// Pings sent, oldest first.
  final List<CoveragePing> pings;

  /// Pings not sent because there was no fresh GPS fix.
  final int skippedNoFix;

  /// Whether the walk is running.
  bool get running => endedAt == null;

  /// A copy with changes.
  CoverageWalk copyWith({DateTime? endedAt, List<CoveragePing>? pings, int? skippedNoFix}) => CoverageWalk(
    id: id,
    dest: dest,
    startedAt: startedAt,
    intervalS: intervalS,
    endedAt: endedAt ?? this.endedAt,
    pings: pings ?? this.pings,
    skippedNoFix: skippedNoFix ?? this.skippedNoFix,
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'id': id,
    'dest': dest,
    'start': startedAt.millisecondsSinceEpoch,
    'every': intervalS,
    if (endedAt != null) 'end': endedAt!.millisecondsSinceEpoch,
    'pings': [for (final p in pings) p.toJson()],
    if (skippedNoFix > 0) 'nofix': skippedNoFix,
  };
}

/// [ping]'s result now, from the DM's delivery state in [messages]. Pending
/// until [kPingTimeout], then failed; a late receipt still makes it delivered.
CoverageSample sampleOf(CoverageWalk walk, CoveragePing ping, Map<int, List<ChatMessage>> messages, DateTime now) {
  ChatMessage? msg;
  for (final m in (messages[walk.dest] ?? const <ChatMessage>[]).reversed) {
    if (m.outgoing && m.clientMsgId == ping.clientMsgId) {
      msg = m;
      break;
    }
  }
  final outcome = switch (msg?.state) {
    MsgState.delivered => CoverageOutcome.delivered,
    MsgState.failed => CoverageOutcome.failed,
    _ => now.difference(ping.at) > kPingTimeout ? CoverageOutcome.failed : CoverageOutcome.pending,
  };
  return CoverageSample(
    sessionId: walk.id,
    clientMessageId: ping.clientMsgId,
    destinationNodeId: walk.dest,
    latitude: ping.pos.lat,
    longitude: ping.pos.lon,
    recordedAt: ping.at,
    outcome: outcome,
    rssiDbm: outcome == CoverageOutcome.delivered ? msg?.rssiDbm : null, // never invented
  );
}

/// Saved walks on disk: one JSON file, written then renamed.
class CoverageStore {
  /// Uses [dir], the app's private support folder.
  CoverageStore(this.dir);

  /// Where the file lives.
  final Directory dir;

  File get _file => File('${dir.path}/coverage_walks.json');

  /// Saved walks; a damaged file is set aside and nothing is returned.
  Future<List<CoverageWalk>> load() async {
    final f = _file;
    if (!f.existsSync()) return const [];
    try {
      final j = jsonDecode(await f.readAsString());
      if (j is! List) throw const FormatException('not a list');
      return [for (final w in j) ?CoverageWalk.fromJson(w)];
    } on FormatException {
      await f.rename('${f.path}.bad').catchError((Object _) => f);
      return const [];
    }
  }

  Future<void> _queue = Future<void>.value();

  /// Saves [walks] after any save already under way.
  Future<void> save(List<CoverageWalk> walks) {
    final next = _queue.catchError((Object _) {}).then((_) async {
      await dir.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode([for (final w in walks) w.toJson()]), flush: true);
      await tmp.rename(_file.path);
    });
    _queue = next;
    return next;
  }

  /// Completes when pending saves are done.
  Future<void> get idle => _queue.catchError((Object _) {});
}

/// The store; `main` installs one. Null keeps walks in memory (tests).
final coverageStoreProvider = Provider<CoverageStore?>((ref) => null);

/// Saved walks (newest first) and whether location is usable.
class CoverageState {
  /// Creates the state.
  const CoverageState({this.walks = const [], this.access, this.error});

  /// Walks, newest first.
  final List<CoverageWalk> walks;

  /// The last location access check; null before one.
  final LocationAccess? access;

  /// The last problem starting or pinging, if any.
  final String? error;

  /// The running walk, if any.
  CoverageWalk? get running => walks.where((w) => w.running).firstOrNull;
}

/// Starts, runs and stops walks.
class CoverageController extends Notifier<CoverageState> {
  Timer? _timer;
  StreamSubscription<LatLon>? _gps;
  LatLon? _fix;
  DateTime? _fixAt;

  @override
  CoverageState build() {
    ref.onDispose(_stopTimers);
    final store = ref.watch(coverageStoreProvider);
    if (store != null) {
      store
          .load()
          .then((walks) {
            if (!ref.mounted) return;
            // a walk left running by a closed app is over
            final now = _now();
            state = CoverageState(walks: [for (final w in walks) w.running ? w.copyWith(endedAt: now) : w]);
          })
          .catchError((Object e) => debugPrint('coverage walks unreadable: $e'));
    }
    return const CoverageState();
  }

  DateTime _now() => ref.read(clockProvider)().toUtc();

  void _set(List<CoverageWalk> walks, {LocationAccess? access, String? error}) {
    state = CoverageState(walks: walks, access: access ?? state.access, error: error);
    unawaited(ref.read(coverageStoreProvider)?.save(walks).catchError((Object _) {}));
  }

  void _stopTimers() {
    _timer?.cancel();
    _timer = null;
    unawaited(_gps?.cancel());
    _gps = null;
  }

  /// A new GPS fix (also fed directly by tests).
  void noteFix(LatLon p, {DateTime? at}) {
    _fix = p;
    _fixAt = at ?? _now();
  }

  /// Starts pinging [dest] every [intervalS] seconds from the phone's GPS.
  /// False if location is not allowed or a walk is already running.
  Future<bool> start(int dest, int intervalS) async {
    if (state.running != null) return false;
    final source = ref.read(positionSourceProvider);
    final access = await source.ensureAccess();
    if (access != LocationAccess.granted) {
      state = CoverageState(walks: state.walks, access: access, error: 'Location is needed to map coverage.');
      return false;
    }
    final every = kPingIntervals.contains(intervalS) ? intervalS : kPingIntervals.first;
    final rnd = Random.secure();
    final id = List.generate(6, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final walk = CoverageWalk(id: id, dest: dest, startedAt: _now(), intervalS: every);
    final walks = [walk, ...state.walks].take(kMaxWalks).toList();
    _set(walks, access: access);
    _gps = source.watch(distanceFilterM: 0).listen(noteFix, onError: (Object _) {});
    _timer = Timer.periodic(Duration(seconds: every), (_) => unawaited(ping()));
    return true;
  }

  /// Sends one ping now if there is a fresh fix and a link. Runs on the timer;
  /// tests call it directly.
  Future<void> ping() async {
    final walk = state.running;
    if (walk == null || walk.pings.length >= kMaxPings) return;
    final now = _now();
    final fix = _fix;
    if (fix == null || _fixAt == null || now.difference(_fixAt!) > kFixMaxAge) {
      _replace(walk.copyWith(skippedNoFix: walk.skippedNoFix + 1));
      return;
    }
    if (ref.read(sessionProvider) == null) return; // not connected: try again next time
    final n = walk.pings.length + 1;
    final cmid = await ref.read(meshProvider.notifier).sendText(walk.dest, '$kCoveragePrefix$n');
    final latest = state.running;
    if (latest == null || latest.id != walk.id) return;
    _replace(
      latest.copyWith(
        pings: [
          ...latest.pings,
          CoveragePing(n: n, clientMsgId: cmid, pos: fix, at: now),
        ],
      ),
    );
  }

  void _replace(CoverageWalk w) => _set([for (final x in state.walks) x.id == w.id ? w : x]);

  /// Stops the running walk.
  void stop() {
    _stopTimers();
    final w = state.running;
    if (w != null) _replace(w.copyWith(endedAt: _now()));
  }

  /// Deletes walk [id].
  void delete(String id) {
    if (state.running?.id == id) _stopTimers();
    _set([
      for (final w in state.walks)
        if (w.id != id) w,
    ]);
  }
}

/// Coverage walks.
final coverageProvider = NotifierProvider<CoverageController, CoverageState>(CoverageController.new);
