import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../link/session.dart';
import 'format.dart';
import 'theme.dart';

/// The result of a link ping, in words: both directions, never guessed.
List<String> linkPingLines(LinkPingOutcome o, String name) {
  if (!o.answered) {
    return [
      'No answer from $name within 10 seconds.',
      'It may be out of range, transmitting, or on firmware without link ping.',
    ];
  }
  return [
    if (o.forwardDbm case final f?) '$name heard you at ${signalText(f)}.',
    if (o.reverseDbm case final r?) 'Your radio heard $name at ${signalText(r)}.',
    'This is the direct link between the two radios (one hop).',
  ];
}

/// Pings [node] one hop and shows the result in a dialog.
Future<void> showLinkPing(BuildContext context, WidgetRef ref, int node) => showDialog<void>(
  context: context,
  builder: (_) => _LinkPingDialog(node: node),
);

class _LinkPingDialog extends ConsumerStatefulWidget {
  const _LinkPingDialog({required this.node});

  final int node;

  @override
  ConsumerState<_LinkPingDialog> createState() => _LinkPingDialogState();
}

class _LinkPingDialogState extends ConsumerState<_LinkPingDialog> {
  List<String>? _lines;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final name = ref.read(meshProvider).nameOf(widget.node);
    try {
      final o = await ref.read(meshProvider.notifier).linkPing(widget.node);
      if (mounted) setState(() => _lines = linkPingLines(o, name));
    } on NodeError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(meshProvider.select((m) => m.nameOf(widget.node)));
    final lines = _lines;
    return AlertDialog(
      icon: const Icon(Icons.compare_arrows),
      title: Text('Ping $name'),
      content: _error != null
          ? Text('Not sent: $_error')
          : lines == null
          ? const Row(
              children: [
                SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                SizedBox(width: GwSpace.md),
                Expanded(child: Text('Waiting for an answer…')),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: GwSpace.xs),
                    child: Text(l),
                  ),
              ],
            ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
