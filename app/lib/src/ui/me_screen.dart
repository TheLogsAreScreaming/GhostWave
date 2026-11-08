import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/providers.dart';
import '../link/contact_card.dart';
import 'widgets.dart';
import 'theme.dart';

/// The connected node's identity and its contact-card QR code.
class MeScreen extends ConsumerWidget {
  /// Creates the screen.
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(nodeInfoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Me'), actions: const [LinkChip()]),
      body: info == null
          ? const NotConnected(what: 'your node and contact card')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (info.legacy || info.ed25519Pub.length != 32)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.warning_amber),
                      title: Text('Legacy node: no Ed25519 identity'),
                      subtitle: Text('This node has no contact card. Others cannot add it by QR code.'),
                    ),
                  )
                else
                  _CardQr(
                    ContactCard(
                      nodeId: info.nodeId,
                      ed25519Pub: Uint8List.fromList(info.ed25519Pub),
                      name: truncateUtf8(decodeLenient(info.name), kMaxContactNameBytes),
                    ),
                  ),
                const SizedBox(height: 16),
                _Field('Name', decodeLenient(info.name)),
                _Field('Node ID', nodeIdHex(info.nodeId)),
                _Field('Ed25519 public key (identity)', hexEncode(info.ed25519Pub)),
                _Field('X25519 public key (DMs)', hexEncode(info.x25519Pub)),
                _Field('Firmware', info.firmware),
                _Field('Protocol', 'v${info.protocolVersion}, DM text up to ${info.maxTextBytes} bytes'),
              ],
            ),
    );
  }
}

class _CardQr extends StatelessWidget {
  const _CardQr(this.card);

  final ContactCard card;

  @override
  Widget build(BuildContext context) {
    final text = card.encode();
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: QrImageView(
            data: text,
            size: 240,
            backgroundColor: Colors.white,
            semanticsLabel: 'Contact card QR code',
          ),
        ),
        const SizedBox(height: 8),
        Text('Let another GhostWave user scan this to add you.', style: Theme.of(context).textTheme.bodySmall),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) showSnack(context, 'Contact card copied');
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy card text'),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: Theme.of(context).textTheme.labelMedium),
    subtitle: SelectableText(value.isEmpty ? '—' : value, style: GwText.mono),
  );
}
