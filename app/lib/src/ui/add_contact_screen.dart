import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app/mesh_controller.dart';
import '../link/contact_card.dart';
import '../link/session.dart';
import 'widgets.dart';
import 'theme.dart';

/// Add a contact, or join a group channel, by scanning a QR code or pasting
/// the card text. Contact cards and channel cards are both accepted.
class AddContactScreen extends ConsumerStatefulWidget {
  /// Creates the screen. [channelsFirst] words it for joining a channel.
  const AddContactScreen({this.channelsFirst = false, super.key});

  /// Opened from "Join a channel".
  final bool channelsFirst;

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final TextEditingController _paste = TextEditingController();
  bool _scanning = false;
  bool _busy = false;
  String? _pasteError;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _confirm(ContactCard card) async {
    if (_busy) return;
    setState(() => _busy = true);
    final nameCtl = TextEditingController(text: card.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add contact?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Node ${nodeIdHex(card.nodeId)}'),
            const SizedBox(height: 4),
            Text('Key ${hexEncode(card.ed25519Pub).substring(0, 16)}…', style: GwText.mono),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              inputFormatters: [_Utf8LimitFormatter(kMaxContactNameBytes)],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    final name = nameCtl.text.trim();
    nameCtl.dispose();
    if (ok != true) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      await ref
          .read(meshProvider.notifier)
          .addContact(ContactCard(nodeId: card.nodeId, ed25519Pub: card.ed25519Pub, name: name));
      if (!mounted) return;
      showSnack(context, 'Added ${name.isEmpty ? nodeIdHex(card.nodeId) : name}');
      Navigator.of(context).pop();
    } on NodeError catch (e) {
      if (mounted) showSnack(context, e.message);
    } on Object catch (e) {
      if (mounted) showSnack(context, 'Could not add: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmChannel(ChannelCard card) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Join #${card.name}?'),
        content: const Text(
          'Your node joins this group channel: you will see its messages and can write to it. '
          'Join only channels from people you trust.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Join')),
        ],
      ),
    );
    if (ok != true) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      await ref.read(meshProvider.notifier).joinChannel(card);
      if (!mounted) return;
      showSnack(context, 'Joined #${card.name}');
      Navigator.of(context).pop();
    } on NodeError catch (e) {
      if (mounted) showSnack(context, e.message);
    } on Object catch (e) {
      if (mounted) showSnack(context, 'Could not join: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A contact card or a channel card; false if [text] is neither.
  bool _handle(String text) {
    final card = ContactCard.tryParse(text);
    if (card != null) {
      unawaited(_confirm(card));
      return true;
    }
    final ch = ChannelCard.tryParse(text);
    if (ch != null) {
      unawaited(_confirmChannel(ch));
      return true;
    }
    return false;
  }

  void _onPasteSubmit() {
    if (!_handle(_paste.text)) {
      setState(() => _pasteError = 'Not a GhostWave card (ghostwave:<id>:<key>[:name] or ghostwave-ch:<name>:<key>)');
      return;
    }
    setState(() => _pasteError = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.channelsFirst ? 'Join a channel' : 'Add contact or channel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_scanning)
            SizedBox(
              height: 320,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  onDetect: (capture) {
                    for (final b in capture.barcodes) {
                      final raw = b.rawValue ?? '';
                      if (ContactCard.tryParse(raw) != null || ChannelCard.tryParse(raw) != null) {
                        setState(() => _scanning = false);
                        _handle(raw);
                        return;
                      }
                    }
                  },
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Camera unavailable: ${error.errorCode.name}. Paste the card text below.'),
                    ),
                  ),
                ),
              ),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : () => setState(() => _scanning = true),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR code'),
            ),
          if (_scanning)
            TextButton(onPressed: () => setState(() => _scanning = false), child: const Text('Stop camera')),
          const SizedBox(height: 24),
          Text(widget.channelsFirst ? 'Or paste the channel card text:' : 'Or paste the card text:'),
          const SizedBox(height: 8),
          TextField(
            controller: _paste,
            minLines: 2,
            maxLines: 4,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: widget.channelsFirst ? 'ghostwave-ch:trail%20crew:…' : 'ghostwave:1a2b3c4d:…',
              errorText: _pasteError,
              errorMaxLines: 2,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) _paste.text = data!.text!;
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _busy ? null : _onPasteSubmit, child: const Text('Use this text')),
        ],
      ),
    );
  }
}

class _Utf8LimitFormatter extends TextInputFormatter {
  _Utf8LimitFormatter(this.maxBytes);

  final int maxBytes;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      utf8Length(newValue.text) <= maxBytes ? newValue : oldValue;
}
