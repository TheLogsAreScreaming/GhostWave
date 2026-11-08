import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../app/providers.dart';
import '../data/models.dart';
import '../link/contact_card.dart';
import 'format.dart';
import 'theme.dart';

/// Default DM limit if the node has not said (`NodeInfo.max_text_bytes`).
const int kDefaultMaxTextBytes = 73;

/// A DM thread with one contact.
class ChatScreen extends ConsumerStatefulWidget {
  /// Creates the screen for [peer].
  const ChatScreen({required this.peer, super.key});

  /// The other node.
  final int peer;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(meshProvider.notifier).markRead(widget.peer);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _max {
    final m = ref.read(nodeInfoProvider)?.maxTextBytes ?? 0;
    return m == 0 ? kDefaultMaxTextBytes : m;
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || utf8Length(t) > _max) return;
    _text.clear();
    await ref.read(meshProvider.notifier).sendText(widget.peer, t);
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    ref.listen(meshProvider.select((m) => m.unread[widget.peer] ?? 0), (_, n) {
      if (n > 0) ref.read(meshProvider.notifier).markRead(widget.peer);
    });
    final online = ref.watch(sessionProvider) != null;
    final contact = mesh.contacts[widget.peer];
    final msgs = mesh.messages[widget.peer] ?? const <ChatMessage>[];
    final bytes = utf8Length(_text.text.trim());
    final max = _max;
    final over = bytes > max;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mesh.nameOf(widget.peer)),
            Text(
              [
                nodeIdHex(widget.peer),
                if (contact?.lastSeen != null) 'seen ${timeAgo(contact!.lastSeen!)}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (contact?.keyChanged ?? false)
            MaterialBanner(
              backgroundColor: scheme.errorContainer,
              content: const Text(
                'This node announced a different key. Your node kept the old one. '
                'If you expect a new key, scan their QR code again.',
              ),
              actions: const [SizedBox.shrink()],
            ),
          if (!online)
            Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(8),
              child: const Text('Offline: messages are saved and sent when the node reconnects.'),
            ),
          Expanded(
            child: msgs.isEmpty
                ? const Center(child: Text('No messages yet.'))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: msgs.length,
                    itemBuilder: (context, i) => _Bubble(msgs[msgs.length - 1 - i]),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Message',
                        border: const OutlineInputBorder(),
                        counterText: '$bytes / $max bytes',
                        counterStyle: TextStyle(color: over ? scheme.error : null),
                        errorText: over ? 'Too long: ${bytes - max} bytes over' : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: IconButton.filled(
                      tooltip: 'Send',
                      onPressed: bytes == 0 || over ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble(this.m);

  final ChatMessage m;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, String label) = switch (m.state) {
      MsgState.pending => (Icons.schedule, 'queued'),
      MsgState.sent => (Icons.done, 'sent'),
      MsgState.delivered => (Icons.done_all, 'delivered'),
      MsgState.failed => (Icons.error_outline, 'failed'),
    };
    final meta = Theme.of(context).textTheme.labelSmall;
    return Align(
      alignment: m.outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: m.state == MsgState.failed ? () => ref.read(meshProvider.notifier).retry(m) : null,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: m.outgoing ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(alignment: Alignment.centerLeft, child: Text(m.text)),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.replayed) Text('held · ', style: meta),
                  Text(clockTime(m.at), style: meta),
                  if (m.outgoing) ...[
                    const SizedBox(width: 6),
                    Icon(
                      icon,
                      size: 14,
                      color: m.state == MsgState.failed
                          ? scheme.error
                          : m.state == MsgState.delivered
                          ? GwColors.success
                          : null,
                      semanticLabel: label,
                    ),
                    const SizedBox(width: 2),
                    Text(label, style: meta),
                  ],
                ],
              ),
              if (m.state == MsgState.failed)
                Text('${m.error ?? 'Failed'} · tap to retry', style: meta?.copyWith(color: scheme.error)),
            ],
          ),
        ),
      ),
    );
  }
}
