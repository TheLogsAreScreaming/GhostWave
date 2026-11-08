import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../app/providers.dart';
import '../data/models.dart';
import '../link/contact_card.dart';
import '../link/session.dart';
import 'format.dart';
import 'widgets.dart';
import 'theme.dart';

/// How long the SOS button must be held.
const Duration kSosHold = Duration(seconds: 3);

/// Our SOS (hold to raise, acks, stop) and SOS alerts from others.
class SosScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const SosScreen({super.key});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  final TextEditingController _text = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on NodeError catch (e) {
      if (mounted) showSnack(context, e.message);
    } on Object catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop SOS?'),
        content: const Text('Your node stops repeating the SOS.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it on')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop SOS')),
        ],
      ),
    );
    if (ok == true) await _run(() => ref.read(meshProvider.notifier).stopSos());
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    final online = ref.watch(sessionProvider) != null;
    final own = mesh.ownSos;
    final scheme = Theme.of(context).colorScheme;
    final bytes = utf8Length(_text.text.trim());

    return Scaffold(
      appBar: AppBar(title: const Text('SOS'), actions: const [LinkChip()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (own.active) ...[
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sos, color: scheme.onErrorContainer, size: 36),
                        const SizedBox(width: 12),
                        Text(
                          'SOS active',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(color: scheme.onErrorContainer, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (own.text.isNotEmpty) Text('"${own.text}"'),
                    if (own.startedAt != null) Text('Raised ${timeAgo(own.startedAt!)} (${clockTime(own.startedAt!)})'),
                    const Text('Your node repeats it until you stop it.'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Acknowledged by (${own.acks.length})', style: Theme.of(context).textTheme.titleMedium),
            if (own.acks.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Text('No acks yet. Help may still be coming.'))
            else
              for (final a in own.acks.reversed)
                ListTile(
                  leading: const Icon(Icons.check_circle, color: GwColors.success),
                  title: Text(mesh.nameOf(a.responder)),
                  subtitle: Text('${timeAgo(a.at)} · seq ${a.seq}'),
                ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: online && !_busy ? _stop : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop SOS'),
            ),
          ] else ...[
            TextField(
              controller: _text,
              maxLength: 120, // characters; the byte limit below is what counts
              decoration: InputDecoration(
                labelText: 'What is wrong? (optional)',
                hintText: 'e.g. twisted ankle, need help',
                border: const OutlineInputBorder(),
                counterText: '$bytes / $kMaxSosTextBytes bytes${bytes > kMaxSosTextBytes ? ' (cut)' : ''}',
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: HoldToConfirmButton(
                enabled: online && !_busy,
                onConfirmed: () => _run(() => ref.read(meshProvider.notifier).startSos(_text.text)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                online ? 'Press and hold for 3 seconds to send an SOS' : 'Connect to a node to send an SOS',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const Divider(height: 40),
          Text('SOS alerts received (${mesh.alerts.length})', style: Theme.of(context).textTheme.titleMedium),
          if (mesh.alerts.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('None.')),
          for (final a in mesh.alerts) AlertTile(alert: a, online: online),
        ],
      ),
    );
  }
}

/// One received SOS alert with an Ack button.
class AlertTile extends ConsumerWidget {
  /// Creates the tile.
  const AlertTile({required this.alert, required this.online, super.key});

  /// The alert.
  final SosAlertEntry alert;

  /// Whether the link is up (Ack needs it).
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesh = ref.watch(meshProvider);
    final a = alert;
    final details = <String>[
      if (a.text.isNotEmpty) '"${a.text}"',
      [
        'received ${timeAgo(a.receivedAt)}',
        'seq ${a.seq}',
        if (a.replayed) 'held by node while no app was connected: may be old',
      ].join(' · '),
      if (a.pos != null) '${a.pos}${a.accuracyM != null ? ' ±${a.accuracyM} m' : ''}' else 'no position fix',
      if (a.batteryPct != null) 'battery ${a.batteryPct}%',
    ];
    return Card(
      child: ListTile(
        leading: Icon(Icons.sos, color: a.acked ? null : Theme.of(context).colorScheme.error),
        title: Text('${mesh.nameOf(a.src)} (${nodeIdHex(a.src)})'),
        subtitle: Text(details.join('\n')),
        isThreeLine: true,
        trailing: a.acked
            ? const Chip(label: Text('Acked'))
            : FilledButton(onPressed: online ? () => ackAlert(context, ref, a.src) : null, child: const Text('Ack')),
      ),
    );
  }
}

/// Sends an ack for [src]'s SOS, reporting errors in a snack bar.
Future<void> ackAlert(BuildContext context, WidgetRef ref, int src) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(meshProvider.notifier).ackSos(src);
    messenger.showSnackBar(const SnackBar(content: Text('Ack sent')));
  } on NodeError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

/// How far the finger may drift from where it pressed before a hold is
/// cancelled, logical pixels. Generous: a thumb wanders over 3 s.
const double kSosHoldSlop = 40;

/// A big round button that fires only after being held for [kSosHold].
///
/// The hold is tracked with raw pointer events, and the button claims the
/// gesture as soon as it is pressed, so a scrolling parent cannot steal it
/// when the thumb drifts. A tick is felt each second and a strong buzz when it
/// fires; letting go early shows "Keep holding". Screen-reader users get a
/// double-tap that opens a confirm dialog instead.
class HoldToConfirmButton extends StatefulWidget {
  /// Creates the button.
  const HoldToConfirmButton({required this.onConfirmed, this.enabled = true, super.key});

  /// Called once the hold completes (or the accessible confirm is accepted).
  final VoidCallback onConfirmed;

  /// Whether it reacts.
  final bool enabled;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: kSosHold)
    ..addListener(_tick)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        unawaited(HapticFeedback.heavyImpact());
        _pointer = null;
        widget.onConfirmed();
        _c.reset();
      }
    });

  int? _pointer;
  Offset _start = Offset.zero;
  int _secondsLeft = 0;
  String? _hint;
  Timer? _hintTimer;

  @override
  void dispose() {
    _hintTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _tick() {
    final left = (kSosHold.inMilliseconds * (1 - _c.value) / 1000).ceil();
    if (_c.status == AnimationStatus.forward && left != _secondsLeft && left > 0) {
      unawaited(HapticFeedback.selectionClick());
    }
    _secondsLeft = left;
  }

  void _showHint(String text) {
    _hintTimer?.cancel();
    setState(() => _hint = text);
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  void _down(PointerDownEvent e) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = e.pointer;
    _start = e.position;
    _secondsLeft = kSosHold.inSeconds;
    _hintTimer?.cancel();
    if (_hint != null) setState(() => _hint = null);
    unawaited(HapticFeedback.selectionClick());
    unawaited(_c.forward(from: 0));
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if ((e.position - _start).distance > kSosHoldSlop) _cancel('Moved too far. Press and hold again.');
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _cancel('Keep holding for ${kSosHold.inSeconds} seconds');
  }

  void _pointerCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _cancel(null);
  }

  void _cancel(String? hint) {
    _pointer = null;
    if (_c.isAnimating || _c.value > 0) {
      unawaited(_c.reverse());
      if (hint != null) _showHint(hint);
    }
  }

  Future<void> _accessibleConfirm() async {
    if (!widget.enabled) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send SOS?'),
        content: const Text('Your node broadcasts an emergency alert with your position to the mesh.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GwColors.alert, foregroundColor: GwColors.onAlert),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // SOS is alert red, never a brand colour; grey when it cannot be sent.
    final color = widget.enabled ? GwColors.alert : scheme.outline;
    final onColor = widget.enabled ? GwColors.onAlert : scheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          enabled: widget.enabled,
          label: 'SOS. Press and hold for 3 seconds to send, or double-tap to confirm.',
          onTap: widget.enabled ? () => unawaited(_accessibleConfirm()) : null,
          child: ExcludeSemantics(
            // claims the pointer at once, so a scrolling parent never wins it
            child: RawGestureDetector(
              gestures: <Type, GestureRecognizerFactory>{
                EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                  EagerGestureRecognizer.new,
                  (_) {},
                ),
              },
              child: Listener(
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _pointerCancel,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: _c.value,
                            strokeWidth: 10,
                            color: color,
                            backgroundColor: color.withValues(alpha: 0.15),
                          ),
                        ),
                        Container(
                          width: 168,
                          height: 168,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                          alignment: Alignment.center,
                          child: Text(
                            _c.value > 0 ? '${(kSosHold.inSeconds * (1 - _c.value)).ceil()}' : 'SOS',
                            style: TextStyle(color: onColor, fontSize: 48, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // fixed height so the hint does not move the layout
        SizedBox(
          height: 28,
          child: Center(
            child: AnimatedOpacity(
              opacity: _hint == null ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: Text(_hint ?? '', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.error)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Banner for SOS alerts that are not acked or dismissed. Shown above every tab.
class SosAlertBanner extends ConsumerWidget {
  /// Creates the banner.
  const SosAlertBanner({required this.onView, super.key});

  /// Opens the SOS tab.
  final VoidCallback onView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesh = ref.watch(meshProvider);
    final alerts = mesh.activeAlerts;
    if (alerts.isEmpty) return const SizedBox.shrink();
    final a = alerts.first;
    final online = ref.watch(sessionProvider) != null;
    return Material(
      color: GwColors.alert,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              const Icon(Icons.sos, color: GwColors.onAlert, size: 32),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: onView,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOS from ${mesh.nameOf(a.src)}${alerts.length > 1 ? ' (+${alerts.length - 1} more)' : ''}',
                        style: const TextStyle(color: GwColors.onAlert, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        [
                          if (a.text.isNotEmpty) a.text,
                          timeAgo(a.receivedAt),
                          if (a.replayed) 'held, may be old',
                        ].join(' · '),
                        style: const TextStyle(color: GwColors.onAlert),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: GwColors.onAlert, foregroundColor: GwColors.alert),
                onPressed: online ? () => ackAlert(context, ref, a.src) : null,
                child: const Text('Ack'),
              ),
              IconButton(
                tooltip: 'Hide banner',
                color: GwColors.onAlert,
                onPressed: () => ref.read(meshProvider.notifier).dismissAlert(a.src),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
