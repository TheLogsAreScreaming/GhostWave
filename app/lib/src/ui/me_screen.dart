import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/background_link.dart';
import '../app/location_share.dart';
import '../app/providers.dart';
import '../link/contact_card.dart';
import 'format.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// The connected node's identity and its contact-card QR code.
class MeScreen extends ConsumerWidget {
  /// Creates the screen.
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(nodeInfoProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Me'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
            child: const Text('Settings'),
          ),
        ],
      ),
      body: info == null
          ? const NotConnected(what: 'your node and contact card')
          : ListView(
              padding: const EdgeInsets.fromLTRB(GwSpace.lg, GwSpace.sm, GwSpace.lg, GwSpace.xl),
              children: [
                ReadableWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      const SectionLabel('Location'),
                      const _LocationShareCard(),
                      const SectionLabel('This node'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: GwSpace.xs),
                          child: Column(
                            children: [
                              _Field('Name', decodeLenient(info.name)),
                              _Field('Node ID', nodeIdHex(info.nodeId), copy: true),
                              _Field('Ed25519 public key (identity)', hexEncode(info.ed25519Pub), copy: true),
                              _Field('X25519 public key (DMs)', hexEncode(info.x25519Pub), copy: true),
                              _Field('Firmware', info.firmware),
                              _Field('Protocol', 'v${info.protocolVersion}, DM text up to ${info.maxTextBytes} bytes'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
    final theme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(GwSpace.lg),
        child: Column(
          children: [
            Text(card.name.isEmpty ? nodeIdHex(card.nodeId) : card.name, style: theme.headlineSmall),
            const SizedBox(height: GwSpace.xs),
            Text(nodeIdHex(card.nodeId), style: GwText.mono.copyWith(color: GwColors.mutedText)),
            const SizedBox(height: GwSpace.lg),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(GwRadius.md)),
              padding: const EdgeInsets.all(GwSpace.md),
              child: QrImageView(
                data: text,
                size: 200,
                backgroundColor: Colors.white,
                semanticsLabel: 'Contact card QR code',
              ),
            ),
            const SizedBox(height: GwSpace.md),
            Text(
              'Let another GhostWave user scan this to add you.',
              textAlign: TextAlign.center,
              style: theme.bodyMedium?.copyWith(color: GwColors.mutedText),
            ),
            const SizedBox(height: GwSpace.sm),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) showSnack(context, 'Contact card copied');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy card text'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value, {this.copy = false});

  final String label;
  final String value;
  final bool copy;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: GwColors.mutedText)),
    subtitle: SelectableText(
      value.isEmpty ? '—' : value,
      style: GwText.mono.copyWith(color: GwColors.mistWhite, fontSize: 13),
    ),
    trailing: copy && value.isNotEmpty
        ? IconButton(
            tooltip: 'Copy $label',
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) showSnack(context, '$label copied');
            },
          )
        : null,
  );
}

/// Opt-in: send the phone's GPS position to the node as its own position.
class _LocationShareCard extends ConsumerWidget {
  const _LocationShareCard();

  Future<void> _confirmBackground(BuildContext context, LocationShareController ctl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Share location in the background?'),
        content: const Text(
          'GhostWave keeps reading this phone\'s GPS while it is connected, with the screen off or the app closed '
          'in the background.\n\n'
          'Your node uses that position in its radio beacons, so nodes in range can see where you are, depending on '
          'the node\'s position settings.\n\n'
          'It uses more battery. The notification says "sharing your location" while it is on, and you can '
          'turn it off here at any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Share in background')),
        ],
      ),
    );
    if (ok == true) await ctl.setBackground(enabled: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(locationShareProvider);
    final ctl = ref.read(locationShareProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final (String detail, bool problem) = switch (loc) {
      LocationShareState(enabled: false) => (
        'Off. When on, the node uses this phone\'s GPS as its position (beacons, map, SOS), '
            'while the app is open.',
        false,
      ),
      LocationShareState(access: LocationAccess.serviceOff) => ('Location is switched off on this phone.', true),
      LocationShareState(access: LocationAccess.deniedForever) => (
        'Location permission is blocked. Allow it in the app settings.',
        true,
      ),
      LocationShareState(access: LocationAccess.denied) => ('Location permission was not given.', true),
      LocationShareState(:final error?) => (error, true),
      LocationShareState(:final lastSent?, :final lastSentAt?) => (
        'Sent ${timeAgo(lastSentAt)}: $lastSent. Updates when you move, at most every 30 s.',
        false,
      ),
      LocationShareState(active: true) => ('Waiting for a GPS fix…', false),
      _ => (loc.background ? 'On. Shares while connected.' : 'On. Shares while the app is open and connected.', false),
    };
    final fixable =
        loc.enabled && (loc.access == LocationAccess.deniedForever || loc.access == LocationAccess.serviceOff);
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.my_location),
            title: const Text('Share phone location with node'),
            subtitle: Text(detail, style: problem ? TextStyle(color: scheme.error) : null),
            value: loc.enabled,
            onChanged: (on) => unawaited(ctl.setEnabled(enabled: on)),
          ),
          if (loc.enabled &&
              ref.watch(backgroundLinkProvider).supported &&
              ref.watch(backgroundEnabledProvider) == true)
            SwitchListTile(
              secondary: const Icon(Icons.share_location),
              title: const Text('Keep sharing in the background'),
              subtitle: const Text('Off by default. The notification says when it is on.'),
              value: loc.background,
              onChanged: (on) => unawaited(on ? _confirmBackground(context, ctl) : ctl.setBackground(enabled: false)),
            ),
          if (fixable)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
                child: TextButton(onPressed: () => unawaited(ctl.openSettings()), child: const Text('Open settings')),
              ),
            ),
        ],
      ),
    );
  }
}
