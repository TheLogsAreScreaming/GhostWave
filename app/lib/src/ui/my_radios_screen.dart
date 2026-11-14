/// "My radios": every radio this phone has connected to, which one is active,
/// and switching, renaming and forgetting them.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/radios.dart';
import '../link/node_link.dart';
import 'ble_scan_screen.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// The saved radios, with the active one marked.
class MyRadiosScreen extends ConsumerWidget {
  /// Creates the screen.
  const MyRadiosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radios = ref.watch(radiosProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My radios')),
      body: SafeArea(
        top: false,
        child: ReadableWidth(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: GwSpace.md),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: GwSpace.lg),
                child: Text(
                  'GhostWave talks to one radio at a time. Tap a radio to switch to it. Each radio keeps its own '
                  'chats, contacts and channels on this phone; they are never mixed.',
                ),
              ),
              const SizedBox(height: GwSpace.md),
              if (radios.isEmpty)
                const ListTile(
                  leading: Icon(Icons.settings_input_antenna),
                  title: Text('No radios yet'),
                  subtitle: Text('Radios appear here after they connect for the first time.'),
                ),
              for (final r in radios) RadioTile(radio: r),
              const SizedBox(height: GwSpace.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: GwSpace.lg),
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BleScanScreen())),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Add a Bluetooth radio'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The saved radios as a section of another screen (Connect), or nothing.
class MyRadiosSection extends ConsumerWidget {
  /// Creates the section.
  const MyRadiosSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radios = ref.watch(radiosProvider);
    if (radios.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('My radios'),
        for (final r in radios) RadioTile(radio: r, dense: true),
      ],
    );
  }
}

/// What the link to the active radio is doing, in a word.
String _activeWord(LinkState s) => switch (s) {
  LinkUp() => 'Connected',
  LinkConnecting() => 'Connecting',
  LinkWaiting() => 'Reconnecting',
  LinkNeedsPin() => 'Needs PIN',
  LinkFailed() => 'Stopped',
  LinkIdle() => 'Disconnected',
};

/// One saved radio: tap to switch to it; menu to rename or forget it.
class RadioTile extends ConsumerWidget {
  /// Creates the tile.
  const RadioTile({required this.radio, this.dense = false, super.key});

  /// The radio.
  final SavedRadio radio;

  /// Fewer details (inside another screen).
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAddress = ref.watch(nodeAddressProvider);
    final active = radio.address == activeAddress;
    final link = ref.watch(linkStateProvider).value ?? const LinkIdle();
    final scheme = Theme.of(context).colorScheme;
    final details = <String>[
      if (radio.nickname.isNotEmpty && radio.nodeName.isNotEmpty) 'Node name ${radio.nodeName}',
      [?radio.board, if (radio.idHex != null) 'ID ${radio.idHex}'].join(' · '),
      [
        if (radio.isBluetooth) 'Bluetooth' else 'Network ${radio.address}',
        if (radio.lastConnected != null) 'last connected ${timeAgo(radio.lastConnected!)}',
      ].join(' · '),
      if (!dense && radio.bluetoothId != null) 'Bluetooth address ${radio.bluetoothId}',
    ].where((l) => l.isNotEmpty).toList();
    final status = active ? _activeWord(link) : null;
    return ListTile(
      selected: active,
      leading: Icon(
        active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: active ? GwColors.success : null,
      ),
      title: Text.rich(
        TextSpan(
          text: radio.displayName,
          children: [
            if (status != null)
              TextSpan(
                text: ' · Active, $status',
                style: TextStyle(color: link is LinkUp ? GwColors.success : scheme.tertiary),
              ),
          ],
        ),
      ),
      subtitle: Text(details.join('\n'), style: GwText.mono.copyWith(fontSize: 12)),
      isThreeLine: details.length > 1,
      onTap: active && link is! LinkIdle && link is! LinkFailed ? null : () => unawaited(_switch(context, ref)),
      trailing: PopupMenuButton<_Action>(
        tooltip: 'Options for ${radio.displayName}',
        onSelected: (a) => unawaited(switch (a) {
          _Action.rename => _rename(context, ref),
          _Action.forget => _forget(context, ref),
        }),
        itemBuilder: (_) => const [
          PopupMenuItem(value: _Action.rename, child: Text('Rename')),
          PopupMenuItem(value: _Action.forget, child: Text('Forget')),
        ],
      ),
    );
  }

  Future<void> _switch(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text('Switching to ${radio.displayName}…')));
    await ref.read(radiosProvider.notifier).switchTo(radio.address);
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(context: context, builder: (_) => _RenameDialog(radio));
    if (name == null) return;
    ref.read(radiosProvider.notifier).rename(radio.address, name);
  }

  Future<void> _forget(BuildContext context, WidgetRef ref) async {
    final active = ref.read(nodeAddressProvider) == radio.address;
    var deleteHistory = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: Text('Forget ${radio.displayName}?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    'It leaves this list and its saved PIN is deleted.',
                    if (active) 'The app disconnects from it and stops reconnecting.',
                    'The radio keeps its own contacts and channels.',
                  ].join(' '),
                ),
                if (radio.nodeId != null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: deleteHistory,
                    onChanged: (v) => setState(() => deleteHistory = v ?? false),
                    title: const Text('Also delete its chats, contacts and channels on this phone'),
                    subtitle: const Text('Cannot be undone'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Forget')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await ref.read(radiosProvider.notifier).forget(radio.address, deleteHistory: deleteHistory);
  }
}

enum _Action { rename, forget }

class _RenameDialog extends StatefulWidget {
  const _RenameDialog(this.radio);

  final SavedRadio radio;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.radio.nickname);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radio = widget.radio;
    return AlertDialog(
      title: const Text('Rename radio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                'This name is only on this phone.',
                if (radio.nodeName.isNotEmpty) 'The radio still calls itself ${radio.nodeName} on the mesh.',
              ].join(' '),
            ),
            const SizedBox(height: GwSpace.md),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: kRadioNicknameMax,
              decoration: const InputDecoration(labelText: 'Name on this phone'),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (radio.nickname.isNotEmpty)
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Use radio\'s name')),
        FilledButton(onPressed: () => Navigator.pop(context, _name.text), child: const Text('Save')),
      ],
    );
  }
}

/// The active radio, for the top of the status screen: which radio the
/// numbers come from, and a way to the others.
class ActiveRadioCard extends ConsumerWidget {
  /// Creates the card.
  const ActiveRadioCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radio = ref.watch(activeRadioProvider);
    if (radio == null) return const SizedBox.shrink();
    final count = ref.watch(radiosProvider).length;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.settings_input_antenna),
        title: Text('Radio: ${radio.displayName}'),
        subtitle: Text([?radio.board, ?radio.idHex].join(' · ')),
        trailing: count > 1 ? const Icon(Icons.chevron_right) : null,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyRadiosScreen())),
      ),
    );
  }
}
