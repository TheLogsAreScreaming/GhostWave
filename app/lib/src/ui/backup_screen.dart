import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/backup.dart';
import '../data/backup_codec.dart';
import 'widgets.dart';

/// Makes and restores the encrypted backup of what this phone holds.
class BackupScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  String? _busy;

  Future<void> _create() async {
    final passphrase = await showDialog<String>(
      context: context,
      builder: (_) => const _PassphraseDialog(creating: true),
    );
    if (passphrase == null || !mounted) return;
    setState(() => _busy = 'Encrypting. This can take a few seconds.');
    try {
      final saved = await ref.read(backupProvider).create(passphrase);
      if (mounted && saved) showSnack(context, 'Backup saved');
    } on Object catch (e) {
      if (mounted) showSnack(context, 'Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _restore() async {
    final backup = ref.read(backupProvider);
    final navigator = Navigator.of(context);
    try {
      final file = await ref.read(backupFilesProvider).pick();
      if (file == null || !mounted) return;
      final passphrase = await showDialog<String>(
        context: context,
        builder: (_) => const _PassphraseDialog(creating: false),
      );
      if (passphrase == null || !mounted) return;
      setState(() => _busy = 'Decrypting. This can take a few seconds.');
      final data = await backup.read(file, passphrase);
      if (!mounted) return;
      setState(() => _busy = null);
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Replace the data on this phone?'),
          content: const Text(
            'Chats, contacts, channels and saved PINs on this phone are replaced by the backup. '
            'Anything newer than the backup is lost.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Replace')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _busy = 'Restoring.');
      await backup.restore(data);
      if (!mounted) return;
      showSnack(context, 'Backup restored');
      navigator.popUntil((r) => r.isFirst);
    } on BackupException catch (e) {
      if (mounted) showSnack(context, e.message);
    } on Object catch (e) {
      if (mounted) showSnack(context, 'Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('What a backup holds', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Contacts and their pinned keys, channels and their keys, chat history, saved PINs and settings.',
            ),
            const SizedBox(height: 16),
            Text('It does not include your node\'s identity', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Your node\'s private key stays on the node and is not in this file. If you lose the board, its '
              'replacement has a new identity and a new node ID, and other people have to add you again.',
            ),
            const SizedBox(height: 16),
            Text('If you forget the passphrase, the backup is gone', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('The file is encrypted with your passphrase. Nobody can recover it without that passphrase.'),
            const SizedBox(height: 24),
            if (busy != null) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 12),
              Text(busy, textAlign: TextAlign.center),
            ] else ...[
              FilledButton(onPressed: () => unawaited(_create()), child: const Text('Create backup')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => unawaited(_restore()), child: const Text('Restore from a backup')),
            ],
          ],
        ),
      ),
    );
  }
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({required this.creating});

  final bool creating;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  String? get _problem {
    if (!widget.creating) return null;
    if (_first.text.characters.length < kMinBackupPassphrase) return 'At least $kMinBackupPassphrase characters';
    if (_first.text != _second.text) return 'The two entries don\'t match';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.creating;
    final ok = _problem == null && _first.text.isNotEmpty;
    return AlertDialog(
      title: Text(creating ? 'Choose a passphrase' : 'Backup passphrase'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('passphrase'),
              controller: _first,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passphrase'),
              onChanged: (_) => setState(() {}),
            ),
            if (creating) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('passphrase2'),
                controller: _second,
                obscureText: true,
                decoration: InputDecoration(labelText: 'Type it again', helperText: _problem, helperMaxLines: 2),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              const Text('Write it down. It can\'t be reset or recovered.'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: ok ? () => Navigator.pop(context, _first.text) : null,
          child: Text(creating ? 'Create' : 'Continue'),
        ),
      ],
    );
  }
}
