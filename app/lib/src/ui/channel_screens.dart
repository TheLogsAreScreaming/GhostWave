import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/mesh_controller.dart';
import '../app/preferences.dart';
import '../app/providers.dart';
import '../data/models.dart';
import '../link/contact_card.dart';
import '../link/session.dart';
import 'format.dart';
import 'message_bubble.dart';
import 'theme.dart';
import 'widgets.dart';

/// Channel text limit if the node has not said (`NodeInfo.max_channel_text_bytes`).
const int kDefaultMaxChannelTextBytes = 86;

/// The Channels tab of Chats: joined group channels with their last message.
class ChannelsList extends ConsumerWidget {
  /// Creates the list.
  const ChannelsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesh = ref.watch(meshProvider);
    final info = ref.watch(nodeInfoProvider);
    final online = info != null;
    final supported = info == null || (info.protocolMinor >= 1 && info.maxChannelTextBytes > 0);
    DateTime last(String name) {
      final l = mesh.channelMessages[name];
      return l == null || l.isEmpty ? DateTime(2000) : l.last.at;
    }

    final names = mesh.channels.keys.toList()..sort((a, b) => last(b).compareTo(last(a)));
    if (!supported) {
      return const _Centered(
        'Group channels are not available on this node. Update its GhostWave software to use them.',
      );
    }
    if (names.isEmpty) {
      return _Centered(
        online
            ? 'No channels yet. A channel is a group chat for everyone who has its key. '
                  'Tap "Add" to make one and share its QR code, or to join one.'
            : 'Connect to a node to see its channels.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final name in names)
          Builder(
            builder: (context) {
              final msgs = mesh.channelMessages[name];
              final m = msgs == null || msgs.isEmpty ? null : msgs.last;
              final unread = mesh.channelUnread[name] ?? 0;
              final twoPane = ChatPaneScope.isTwoPane(context);
              final text = Theme.of(context).textTheme;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: GwSpace.sm),
                child: ListTile(
                  selected: twoPane && ref.watch(openChatProvider) == OpenChannel(name),
                  selectedTileColor: GwColors.surface2,
                  selectedColor: GwColors.mistWhite,
                  leading: ExcludeSemantics(
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: GwColors.phantomViolet.withValues(alpha: 0.22),
                      foregroundColor: GwColors.violetLight,
                      child: const Icon(Icons.tag),
                    ),
                  ),
                  title: Text('#$name'),
                  subtitle: Text(
                    m == null ? 'No messages yet' : '${m.outgoing ? 'You' : mesh.nameOf(m.src)}: ${m.text}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: unread > 0 ? text.bodyMedium?.copyWith(color: GwColors.mistWhite) : null,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (m != null) Text(clockTime(m.at), style: text.labelSmall?.copyWith(color: GwColors.mutedText)),
                      if (unread > 0) ...[
                        const SizedBox(height: GwSpace.xs),
                        Semantics(
                          label: '$unread unread',
                          excludeSemantics: true,
                          child: Badge(label: Text('$unread')),
                        ),
                      ],
                    ],
                  ),
                  onTap: () {
                    if (twoPane) {
                      ref.read(openChatProvider.notifier).open(OpenChannel(name));
                    } else {
                      unawaited(
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => ChannelChatScreen(channel: name))),
                      );
                    }
                  },
                ),
              );
            },
          ),
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

/// Asks for a name, makes a channel with a new random key, and shows its QR.
Future<void> showNewChannelDialog(BuildContext context) async {
  final ctl = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) {
        final t = ctl.text.trim();
        final ok = validChannelName(t);
        return AlertDialog(
          title: const Text('New channel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'trail crew',
                  counterText: '${utf8Length(t)} / $kMaxChannelNameBytes bytes',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => ok ? Navigator.pop(dialog, t) : null,
              ),
              const SizedBox(height: 8),
              const Text('A new secret key is made for it. Everyone you share the QR code with can read and write.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
            FilledButton(onPressed: ok ? () => Navigator.pop(dialog, t) : null, child: const Text('Create')),
          ],
        );
      },
    ),
  );
  // not disposed here: the dialog's closing animation still uses it
  if (name == null || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    final card = await container.read(meshProvider.notifier).createChannel(name);
    if (!context.mounted) return;
    await showChannelShare(context, card);
  } on NodeError catch (e) {
    if (context.mounted) showSnack(context, e.message);
  } on Object catch (e) {
    if (context.mounted) showSnack(context, '$e');
  }
}

/// Shows [card] as a QR code (and text) for others to join.
Future<void> showChannelShare(BuildContext context, ChannelCard card) => showDialog<void>(
  context: context,
  builder: (dialog) => AlertDialog(
    title: Text('Share #${card.name}'),
    content: SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: card.encode(),
              size: 240,
              backgroundColor: Colors.white,
              semanticsLabel: 'QR code for channel ${card.name}',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Anyone with this code can read and write the channel. Share it like a password, in person.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: card.encode()));
          if (dialog.mounted) showSnack(dialog, 'Channel card copied');
        },
        child: const Text('Copy as text'),
      ),
      FilledButton(onPressed: () => Navigator.pop(dialog), child: const Text('Done')),
    ],
  ),
);

/// A group channel's messages.
class ChannelChatScreen extends ConsumerStatefulWidget {
  /// Creates the screen for [channel].
  const ChannelChatScreen({required this.channel, super.key});

  /// Channel name.
  final String channel;

  @override
  ConsumerState<ChannelChatScreen> createState() => _ChannelChatScreenState();
}

class _ChannelChatScreenState extends ConsumerState<ChannelChatScreen> {
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(meshProvider.notifier).markChannelRead(widget.channel);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _max {
    final m = ref.read(nodeInfoProvider)?.maxChannelTextBytes ?? 0;
    return m == 0 ? kDefaultMaxChannelTextBytes : m;
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || utf8Length(t) > _max) return;
    _text.clear();
    await ref.read(meshProvider.notifier).sendChannelText(widget.channel, t);
  }

  Future<void> _menu(String choice) async {
    final ctl = ref.read(meshProvider.notifier);
    final ch = ref.read(meshProvider).channels[widget.channel];
    switch (choice) {
      case 'share':
        final psk = ch == null ? null : hexDecode(ch.pskHex);
        if (psk != null && psk.length == 32) await showChannelShare(context, ChannelCard(name: ch!.name, psk: psk));
      case 'clear':
        if (await _confirm('Clear history?', 'Deletes the messages on this phone. You stay in the channel.')) {
          ctl.clearChannelHistory(widget.channel);
        }
      case 'leave':
        if (!await _confirm(
          'Leave #${widget.channel}?',
          'Your node stops receiving it and the history on this phone is deleted. '
              'You can join again with its QR code.',
        )) {
          return;
        }
        try {
          await ctl.leaveChannel(widget.channel);
          if (mounted) closeChat(context, ref);
        } on NodeError catch (e) {
          if (mounted) showSnack(context, e.message);
        } on Object catch (e) {
          if (mounted) showSnack(context, '$e');
        }
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('OK')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    ref.listen(meshProvider.select((m) => m.channelUnread[widget.channel] ?? 0), (_, n) {
      if (n > 0) ref.read(meshProvider.notifier).markChannelRead(widget.channel);
    });
    final online = ref.watch(sessionProvider) != null;
    final msgs = mesh.channelMessages[widget.channel] ?? const <ChannelMessage>[];
    final joined = mesh.channels.containsKey(widget.channel);
    final bytes = utf8Length(_text.text.trim());
    final max = _max;
    final over = bytes > max;
    final scheme = Theme.of(context).colorScheme;
    final ctl = ref.read(meshProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('#${widget.channel}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (c) => unawaited(_menu(c)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'share', child: Text('Share (QR code)')),
              PopupMenuItem(value: 'clear', child: Text('Clear history')),
              PopupMenuItem(value: 'leave', child: Text('Leave channel')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerHigh,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Text(
              online
                  ? 'Group channel: reaches members within a few hops. No delivery receipts.'
                  : 'Offline: messages are saved and sent when the node reconnects.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: msgs.isEmpty
                ? const Center(child: Text('No messages yet.'))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: GwSpace.lg, vertical: GwSpace.md),
                    itemCount: msgs.length,
                    itemBuilder: (context, i) {
                      final m = msgs[msgs.length - 1 - i];
                      return MessageBubble(
                        outgoing: m.outgoing,
                        text: m.text,
                        at: m.at,
                        state: m.state,
                        sender: m.outgoing ? null : mesh.nameOf(m.src),
                        replayed: m.replayed,
                        error: m.error,
                        receipts: false,
                        rssiDbm: m.rssiDbm,
                        onRetry: m.outgoing && m.state == MsgState.failed ? () => unawaited(ctl.retryChannel(m)) : null,
                        onDelete: () => ctl.deleteChannelMessage(m),
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
                      enabled: joined,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => unawaited(_send()),
                      decoration: InputDecoration(
                        hintText: joined ? 'Message #${widget.channel}' : 'Not joined',
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(GwRadius.lg),
                          borderSide: const BorderSide(color: GwColors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(GwRadius.lg),
                          borderSide: const BorderSide(color: GwColors.spectralCyan, width: 1.5),
                        ),
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
                      style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                      tooltip: 'Send',
                      onPressed: !joined || bytes == 0 || over ? null : () => unawaited(_send()),
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
