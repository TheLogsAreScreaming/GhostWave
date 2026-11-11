import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../app/providers.dart';
import '../data/message_split.dart';
import '../data/models.dart';
import '../link/contact_card.dart';
import '../link/session.dart';
import 'format.dart';
import 'message_bubble.dart';
import 'theme.dart';
import 'widgets.dart';

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
    final max = _max;
    if (t.isEmpty || splitMessage(t, max).length > kMaxMessageParts) return;
    _text.clear();
    await ref.read(meshProvider.notifier).sendMessage(widget.peer, t, max);
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
    final reportedMax = ref.watch(nodeInfoProvider.select((info) => info?.maxTextBytes ?? 0));
    final max = reportedMax == 0 ? kDefaultMaxTextBytes : reportedMax;
    final parts = bytes == 0 ? 1 : splitMessage(_text.text.trim(), max).length;
    final over = parts > kMaxMessageParts;
    final scheme = Theme.of(context).colorScheme;

    final ctl = ref.read(meshProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mesh.nameOf(widget.peer)),
            Text(
              [
                nodeIdHex(widget.peer),
                if (contact != null && !contact.verified) 'unverified',
                if (contact?.lastSeen != null) 'seen ${timeAgo(contact!.lastSeen!)}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (c) async {
              if (c == 'copyId') {
                await Clipboard.setData(ClipboardData(text: nodeIdHex(widget.peer)));
                if (context.mounted) showSnack(context, 'Node ID copied');
                return;
              }
              if (c != 'delete') return;
              final ok = await showDialog<bool>(
                context: context,
                builder: (dialog) => AlertDialog(
                  title: const Text('Delete conversation?'),
                  content: const Text('Deletes these messages on this phone. The contact stays.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok == true) ctl.deleteThread(widget.peer);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copyId', child: Text('Copy node ID')),
              PopupMenuItem(value: 'delete', child: Text('Delete conversation')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (contact?.keyChanged ?? false) _KeyChangeBanner(contact: contact!),
          if (!online)
            Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(8),
              child: const Text('Offline: messages are saved and sent when the node reconnects.'),
            ),
          if (contact == null)
            Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(8),
              child: const Text('No key for this node yet. Messages stay on this phone until it arrives.'),
            ),
          Expanded(
            child: msgs.isEmpty
                ? const Center(child: Text('No messages yet.'))
                : ListView.builder(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: GwSpace.lg, vertical: GwSpace.md),
                    itemCount: msgs.length,
                    itemBuilder: (context, i) {
                      final index = msgs.length - 1 - i;
                      final m = msgs[index];
                      final day = m.at.toLocal();
                      final previous = index == 0 ? null : msgs[index - 1].at.toLocal();
                      final bubble = MessageBubble(
                        outgoing: m.outgoing,
                        text: m.text,
                        at: m.at,
                        state: m.state,
                        replayed: m.replayed,
                        error: m.error,
                        onRetry: m.outgoing && m.state == MsgState.failed ? () => unawaited(ctl.retry(m)) : null,
                        onDelete: () => ctl.deleteMessage(m),
                      );
                      if (previous != null && DateUtils.isSameDay(day, previous)) return bubble;
                      final label = MaterialLocalizations.of(context).formatMediumDate(day);
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: GwSpace.sm),
                            child: Semantics(
                              header: true,
                              child: Text(label, style: Theme.of(context).textTheme.labelMedium),
                            ),
                          ),
                          bubble,
                        ],
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(GwSpace.md, GwSpace.sm, GwSpace.md, GwSpace.sm),
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
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(GwRadius.lg),
                          borderSide: const BorderSide(color: GwColors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(GwRadius.lg),
                          borderSide: const BorderSide(color: GwColors.spectralCyan, width: 1.5),
                        ),
                        counterText: parts > 1 ? '$bytes bytes · $parts messages' : '$bytes / $max bytes',
                        counterStyle: TextStyle(color: over ? scheme.error : null),
                        errorText: over ? 'Too long: at most $kMaxMessageParts messages' : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: IconButton.filled(
                      style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
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

/// The KeyChange warning: a signed IDENT for this node ID carried a different
/// key. The node keeps the old key; the contact is unverified until the user
/// decides.
class _KeyChangeBanner extends ConsumerWidget {
  const _KeyChangeBanner({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(meshProvider.notifier);
    final pending = contact.pendingKeyHex;
    return Container(
      width: double.infinity,
      color: GwColors.alertContainer,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gpp_maybe, color: GwColors.onAlertContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Key changed: this contact is unverified',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: GwColors.onAlertContainer, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Someone announced a different key for ${nodeIdHex(contact.nodeId)}. An honest node cannot do this '
            '(its ID is a hash of its key), so it may be an impersonation attempt. Your node still uses the '
            'old key. Accept the new key only if you checked it with the person, ideally by scanning their QR code.',
            style: const TextStyle(color: GwColors.onAlertContainer),
          ),
          if (pending != null) ...[
            const SizedBox(height: 6),
            Text('New key ${pending.substring(0, 16)}…', style: GwText.mono.copyWith(color: GwColors.onAlertContainer)),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => ctl.rejectKeyChange(contact.nodeId),
                child: const Text('Keep old key', style: TextStyle(color: GwColors.onAlertContainer)),
              ),
              if (pending != null)
                TextButton(
                  onPressed: () async {
                    try {
                      await ctl.acceptKeyChange(contact.nodeId);
                      if (context.mounted) showSnack(context, 'New key accepted');
                    } on NodeError catch (e) {
                      if (context.mounted) showSnack(context, e.message);
                    } on Object catch (e) {
                      if (context.mounted) showSnack(context, '$e');
                    }
                  },
                  child: const Text('Accept new key', style: TextStyle(color: GwColors.onAlertContainer)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
