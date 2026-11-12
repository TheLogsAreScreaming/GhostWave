/// Live connection health and troubleshooting for the Connect screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../gen/ghostwave.pb.dart' as pb;
import '../link/node_link.dart';
import 'format.dart';
import 'theme.dart';

/// After this long with nothing from the node, the link looks like it is
/// dropping: one heartbeat interval plus the time a heartbeat may take.
const Duration kStaleAfter = Duration(seconds: 25);

/// The phone-to-radio Bluetooth signal in a word. Bluetooth is short range, so
/// its bands sit far above LoRa's (see [signalWord]).
String bluetoothWord(int dbm) => switch (dbm) {
  >= -60 => 'strong',
  >= -75 => 'good',
  >= -88 => 'fair',
  _ => 'weak',
};

/// "12 s", "3 min 05 s", "2 h 10 min".
String shortDuration(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '$s s';
  if (s < 3600) return '${s ~/ 60} min ${(s % 60).toString().padLeft(2, '0')} s';
  return '${s ~/ 3600} h ${((s % 3600) ~/ 60).toString().padLeft(2, '0')} min';
}

/// How fresh the link is, from the time since the node last answered.
enum Freshness {
  /// Nothing received yet on this session.
  waiting,

  /// Answered recently.
  live,

  /// Nothing for longer than [kStaleAfter]: likely dropping.
  stale,
}

/// [Freshness] for [since] (time since the last frame, null for none yet).
Freshness freshnessOf(Duration? since) => since == null
    ? Freshness.waiting
    : since > kStaleAfter
    ? Freshness.stale
    : Freshness.live;

/// One thing to try when the link is down.
class Tip {
  /// Creates a tip.
  const Tip(this.title, this.body);

  /// Short action.
  final String title;

  /// How, in a sentence or two.
  final String body;
}

/// What to try for [state], matched to the failure reason where possible.
/// Never includes a saved PIN.
List<Tip> troubleshootingFor(LinkState state, {required bool bluetooth}) {
  final reason = switch (state) {
    LinkWaiting(:final reason) || LinkFailed(:final reason) => reason.toLowerCase(),
    _ => null,
  };
  if (reason == null) return const [];
  final tips = <Tip>[];
  void add(String t, String b) => tips.add(Tip(t, b));
  if (reason.contains('old bluetooth pairing') || reason.contains('characteristic')) {
    add(
      'Forget the old pairing',
      'Open Android Settings → Bluetooth, tap the gear next to the node and choose Forget. Then connect here again and pair with 654321.',
    );
  }
  if (reason.contains('pairing failed') || reason.contains('passkey')) {
    add(
      'Check the pairing key',
      'GhostWave boards ship with 654321. A board with a screen also shows its key. If someone changed it, use theirs.',
    );
    add(
      'Forget and pair again',
      'If the node was reflashed or its pairings cleared, forget it in Android Bluetooth settings first.',
    );
  }
  if (reason.contains('permission')) {
    add(
      'Allow Nearby devices',
      'Open Android Settings → Apps → GhostWave → Permissions and allow Nearby devices (Bluetooth).',
    );
  }
  if (reason.contains('bluetooth is off')) {
    add('Turn Bluetooth on', 'GhostWave reconnects by itself once Bluetooth is back on.');
  }
  if (reason.contains('timed out') || reason.contains('timeout')) {
    add(
      'Move closer to the radio',
      'Bluetooth reaches only a few metres through a pack or a tent wall. The mesh range is not affected.',
    );
    add('Check the radio has power', 'A flat battery or a radio that restarted drops the link.');
  }
  if (reason.contains('protocol version')) {
    add(
      'Update the app or the firmware',
      'The app and the radio speak different protocol versions. Install the latest of both from meshmayhem.org/GhostWave.',
    );
  }
  if (!bluetooth && (reason.contains('refused') || reason.contains('host') || reason.contains('network'))) {
    add('Check the address', 'The node address and port must match what the node printed, on the same network.');
  }
  if (bluetooth) {
    add(
      'One phone at a time',
      'A radio talks to one phone over Bluetooth. Disconnect any other phone or tablet using it.',
    );
  }
  add('Still stuck?', 'Turn Bluetooth off and on, or restart the radio. Your settings and messages are kept.');
  return tips;
}

/// Live health of the current link: how long since the node answered, the
/// last heartbeat's round trip, the phone-to-radio Bluetooth signal, and the
/// radio's last LoRa frame. Refreshes every second while shown.
class ConnectionHealthCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const ConnectionHealthCard({super.key, this.tick = const Duration(seconds: 1)});

  /// Refresh interval (tests shorten it).
  final Duration tick;

  @override
  ConsumerState<ConnectionHealthCard> createState() => _ConnectionHealthCardState();
}

class _ConnectionHealthCardState extends ConsumerState<ConnectionHealthCard> {
  Timer? _timer;
  int _ticks = 0;
  int? _btDbm;
  Duration? _btAt;
  pb.Status? _status;
  StreamSubscription<pb.Status>? _beats;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.tick, (_) => _onTick());
    _beats = ref.read(nodeLinkProvider).heartbeats.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    unawaited(_readBluetooth());
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_beats?.cancel());
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    setState(() => _ticks++);
    if (_ticks % 5 == 0) unawaited(_readBluetooth());
  }

  Future<void> _readBluetooth() async {
    final s = ref.read(sessionProvider);
    if (s == null || !s.canReadLinkSignal) return;
    final dbm = await s.readLinkSignalDbm();
    if (!mounted || ref.read(sessionProvider) != s) return;
    setState(() {
      _btDbm = dbm;
      _btAt = dbm == null ? _btAt : s.age;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    if (s == null) return const SizedBox.shrink();
    final link = ref.read(nodeLinkProvider);
    final since = s.sinceLastReceived;
    final fresh = freshnessOf(since);
    final scheme = Theme.of(context).colorScheme;
    final rtt = link.lastRoundTrip;
    final status = _status;
    final rows = <(IconData, String, String)>[
      (Icons.timer_outlined, 'Connected for', shortDuration(s.age)),
      (
        fresh == Freshness.stale ? Icons.warning_amber_rounded : Icons.favorite_border,
        'Last answer from the radio',
        switch (fresh) {
          Freshness.waiting => 'waiting for the first answer',
          Freshness.live => '${shortDuration(since!)} ago',
          Freshness.stale => '${shortDuration(since!)} ago, the link may be dropping',
        },
      ),
      (Icons.swap_horiz, 'Round trip', rtt == null ? 'measured at the next check' : '${rtt.inMilliseconds} ms'),
      (
        Icons.bluetooth,
        'Phone to radio (Bluetooth)',
        !s.canReadLinkSignal
            ? 'not available on this connection'
            : _btDbm == null
            ? 'not reported by this phone yet'
            : '$_btDbm dBm, ${bluetoothWord(_btDbm!)}'
                  '${_btAt == null ? '' : ', ${shortDuration(s.age - _btAt!)} ago'}',
      ),
      (
        Icons.cell_tower,
        'Radio\'s last LoRa frame',
        status == null
            ? 'shown after the next check'
            : status.hasLastRssiDbm()
            ? '${signalText(status.lastRssiDbm)}${status.hasLastHeardS() ? ', ${secondsAgo(status.lastHeardS)}' : ''}'
            : 'not reported (firmware dev.9 or later)',
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GwSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(GwSpace.lg, GwSpace.sm, GwSpace.lg, 0),
              child: Text('Connection health', style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final (icon, label, value) in rows)
              ListTile(
                dense: true,
                leading: Icon(
                  icon,
                  color: icon == Icons.warning_amber_rounded ? scheme.error : null,
                  semanticLabel: icon == Icons.warning_amber_rounded ? 'warning' : null,
                ),
                title: Text(label),
                subtitle: Text(value, style: Theme.of(context).textTheme.titleSmall),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(GwSpace.lg, 0, GwSpace.lg, GwSpace.sm),
              child: Text(
                'Bluetooth is the short hop between this phone and your radio. LoRa is the radio\'s link to other '
                'nodes: a strong Bluetooth signal says nothing about mesh range.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Things to try while the link is down, matched to why it failed.
class TroubleshootCard extends StatelessWidget {
  /// Creates the card for [state].
  const TroubleshootCard({required this.state, required this.bluetooth, super.key});

  /// The current link state.
  final LinkState state;

  /// Whether the saved node is a Bluetooth one.
  final bool bluetooth;

  @override
  Widget build(BuildContext context) {
    final tips = troubleshootingFor(state, bluetooth: bluetooth);
    if (tips.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.build_outlined),
        title: const Text('What to try'),
        initiallyExpanded: state is LinkFailed,
        children: [
          for (final (i, t) in tips.indexed)
            ListTile(
              leading: CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
              title: Text(t.title),
              subtitle: Text(t.body),
            ),
        ],
      ),
    );
  }
}
