import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../data/path_trace.dart';
import '../link/session.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// A one-line summary of a trace, in words, never guessed.
String traceSummary(PathTrace t, String Function(int) nameOf) {
  final name = nameOf(t.target);
  if (!t.answered) return 'No answer from $name. The path is unknown.';
  String hops(int n) => n == 1 ? '1 hop' : '$n hops';
  final ways = t.hopsOut == t.hopsBack
      ? '${hops(t.hopsOut)} each way'
      : '${hops(t.hopsOut)} out, ${hops(t.hopsBack)} back';
  final weak = t.weakest;
  final weakest = weak == null ? '' : ' Weakest link: ${signalText(weak.rssiDbm)} at ${nameOf(weak.node)}.';
  return 'Reached $name: $ways.$weakest';
}

/// One line per hop: who received, and how strongly, starting from [from].
List<String> traceHopLines(List<TraceStep> steps, int from, String Function(int) nameOf) => [
  for (var i = 0; i < steps.length; i++)
    '${nameOf(i == 0 ? from : steps[i - 1].node)} → ${nameOf(steps[i].node)}: heard at ${signalText(steps[i].rssiDbm)}',
];

/// Opens the traceroute screen for [node].
Future<void> showTraceRoute(BuildContext context, int node) =>
    Navigator.push<void>(context, MaterialPageRoute(builder: (_) => TraceRouteScreen(node: node)));

/// Traces the path to a node through relays and back, and shows each hop with
/// the signal the receiving radio measured.
class TraceRouteScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const TraceRouteScreen({required this.node, super.key});

  /// The node to trace to.
  final int node;

  @override
  ConsumerState<TraceRouteScreen> createState() => _TraceRouteScreenState();
}

class _TraceRouteScreenState extends ConsumerState<TraceRouteScreen> {
  int _maxHops = 5;
  bool _running = false;
  PathTrace? _result;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final t = await ref.read(meshProvider.notifier).traceroute(widget.node, maxHops: _maxHops);
      if (mounted) setState(() => _result = t);
    } on NodeError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    final ctl = ref.read(meshProvider.notifier);
    String nameOf(int id) => id == mesh.nodeId ? 'You' : mesh.nameOf(id);
    final name = nameOf(widget.node);
    final canTrace = ctl.nodeCanTrace;
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text('Trace route to $name')),
      body: SafeArea(
        child: ReadableWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(GwSpace.lg, GwSpace.sm, GwSpace.lg, 96),
            children: [
              const Text(
                'Sends a probe that collects every relay it passes through, and an answer '
                'that does the same on the way back. Each reading is taken by the radio '
                'that received it. This transmits, and the probe spreads to nearby nodes.',
              ),
              const SizedBox(height: GwSpace.md),
              if (!canTrace)
                const Text('The connected radio needs newer firmware (client protocol 1.10) to trace a route.')
              else ...[
                Row(
                  children: [
                    const Expanded(child: Text('Up to this many hops each way')),
                    DropdownButton<int>(
                      value: _maxHops,
                      onChanged: _running ? null : (v) => setState(() => _maxHops = v ?? 5),
                      items: [for (var i = 1; i <= 8; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                    ),
                  ],
                ),
                const SizedBox(height: GwSpace.sm),
                FilledButton.icon(
                  onPressed: _running ? null : _run,
                  icon: const Icon(Icons.alt_route),
                  label: Text(_running ? 'Tracing… (up to 45 s)' : 'Trace route'),
                ),
              ],
              if (_running) ...[const SizedBox(height: GwSpace.md), const LinearProgressIndicator()],
              if (_error case final e?) ...[const SizedBox(height: GwSpace.md), Text('Not sent: $e')],
              if (r != null) ...[
                const SizedBox(height: GwSpace.md),
                Semantics(liveRegion: true, child: Text(traceSummary(r, nameOf))),
                if (!r.answered)
                  const Padding(
                    padding: EdgeInsets.only(top: GwSpace.xs),
                    child: Text(
                      'It may be out of reach, need more hops, or sit behind a relay on older firmware. '
                      'A lost probe or answer says nothing about where it was lost.',
                    ),
                  )
                else ...[
                  const SectionLabel('Out'),
                  _Hops(lines: traceHopLines(r.out, mesh.nodeId ?? 0, nameOf)),
                  const SectionLabel('Back'),
                  _Hops(lines: traceHopLines(r.back, r.target, nameOf)),
                  const SizedBox(height: GwSpace.sm),
                  Text(
                    r.sameWayBack
                        ? 'The answer came back through the same relays.'
                        : 'The answer came back a different way. Routes here are not fixed, '
                              'so the next trace may differ too.',
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Hops extends StatelessWidget {
  const _Hops({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        for (final (i, l) in lines.indexed)
          ListTile(
            dense: true,
            leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
            title: Text(l),
          ),
      ],
    ),
  );
}
