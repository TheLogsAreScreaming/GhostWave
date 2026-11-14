import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../gen/ghostwave.pb.dart' as pb;
import '../link/contact_card.dart';
import '../link/session.dart';
import 'theme.dart';
import 'widgets.dart';

/// Above this the general limit ends; only boards with an amplifier go higher.
const int kGeneralMaxDbm = 22;

/// Screen timeout choices, in seconds (0 = never off).
const List<int> kScreenTimeouts = [30, 60, 300, 600, 1800, 3600, 0];

/// The words for a screen timeout of [s] seconds.
String screenTimeoutLabel(int s) => switch (s) {
  0 => 'Never (dims only)',
  < 60 => '$s seconds',
  60 => '1 minute',
  < 3600 => '${s ~/ 60} minutes',
  3600 => '1 hour',
  _ => '${s ~/ 3600} hours',
};

/// Output power in words: dBm and milliwatts.
String powerLabel(int dbm) {
  final mw = pow(10, dbm / 10).toDouble();
  final watts = mw >= 1000
      ? '${(mw / 1000).toStringAsFixed(1)} W'
      : '${mw < 10 ? mw.toStringAsFixed(1) : mw.round()} mW';
  return '$dbm dBm ($watts)';
}

/// Parses a 64-character hex channel key, or null.
Uint8List? parseKeyHex(String text) {
  final t = text.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(t)) return null;
  return Uint8List.fromList([for (var i = 0; i < 64; i += 2) int.parse(t.substring(i, i + 2), radix: 16)]);
}

/// A key as 64 hex characters.
String keyHex(List<int> key) => key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// The connected node's radio and device settings (protocol 1.11): name,
/// region, frequency, output power, channel key, encryption, SOS responder,
/// Bluetooth PIN, screen timeout, LEDs and the button.
class NodeSettingsScreen extends ConsumerStatefulWidget {
  /// Creates the screen. [initial] skips reading the node (tests).
  const NodeSettingsScreen({super.key, this.initial});

  /// Settings to show instead of reading them from the node.
  final pb.Settings? initial;

  @override
  ConsumerState<NodeSettingsScreen> createState() => _NodeSettingsScreenState();
}

class _NodeSettingsScreenState extends ConsumerState<NodeSettingsScreen> {
  pb.Settings? _s;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _s = widget.initial;
    if (_s == null) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(meshProvider.notifier).readNodeSettings();
      if (!mounted) return;
      setState(() {
        _s = s;
        _error = null;
      });
    } on NodeError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Sends [change]; on success shows [done] and the node's new values.
  Future<void> _apply(pb.Settings change, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final now = await ref.read(meshProvider.notifier).changeNodeSettings(change);
      if (!mounted) return;
      setState(() => _s = now);
      showSnack(context, done);
    } on NodeError catch (e) {
      if (mounted) showSnack(context, 'Not changed: ${e.message}');
    } on Object catch (e) {
      if (mounted) showSnack(context, 'Not changed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(action)),
          ],
        ),
      ) ==
      true;

  Future<T?> _pick<T>(String title, Map<T, String> options, T current) => showDialog<T>(
    context: context,
    builder: (d) => SimpleDialog(
      title: Text(title),
      children: [
        for (final e in options.entries)
          ListTile(
            leading: Icon(e.key == current ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            title: Text(e.value),
            onTap: () => Navigator.pop(d, e.key),
          ),
      ],
    ),
  );

  Future<String?> _ask(String title, String hint, String initial, {TextInputType? type, String? help}) =>
      showDialog<String>(
        context: context,
        builder: (_) => _TextDialog(title: title, hint: hint, initial: initial, type: type, help: help),
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Node settings')),
      body: ReadableWidth(
        child: _error != null
            ? ListView(
                children: [
                  ListTile(leading: const Icon(Icons.error_outline), title: Text('Could not read settings: $_error')),
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('Try again'),
                    onTap: () => unawaited(_load()),
                  ),
                ],
              )
            : s == null
            ? const Center(child: CircularProgressIndicator())
            : AbsorbPointer(absorbing: _busy, child: _list(s)),
      ),
    );
  }

  Widget _list(pb.Settings s) {
    final minDbm = s.hasMinOutputDbm() ? s.minOutputDbm : -9;
    final maxDbm = s.hasMaxOutputDbm() ? s.maxOutputDbm : kGeneralMaxDbm;
    final dbm = s.outputDbm.clamp(minDbm, maxDbm);
    return ListView(
      children: [
        if (s.restartNeeded)
          const _Banner(
            'Some saved changes apply after the node restarts: press its reset button or unplug it and plug it back in.',
          ),
        const _Section('Radio'),
        if (s.hasName())
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Node name'),
            subtitle: Text(decodeLenient(s.name).isEmpty ? '(none)' : decodeLenient(s.name)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await _ask('Node name', 'Up to 9 letters', decodeLenient(s.name));
              if (v != null) await _apply(pb.Settings(name: utf8.encode(v.trim())), 'Name saved');
            },
          ),
        ListTile(
          leading: const Icon(Icons.public),
          title: const Text('Region'),
          subtitle: Text(s.region.toUpperCase()),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final v = await _pick<String>('Region', {'us915': 'US915', 'eu868': 'EU868'}, s.region);
            if (v == null || v == s.region) return;
            if (await _confirm(
              'Change region to ${v.toUpperCase()}?',
              'Nodes on different regions or frequencies cannot hear each other. Only use a band that is '
                  'allowed where you are, with an antenna made for it. Applies after the node restarts.',
              'Change',
            )) {
              await _apply(pb.Settings(region: v), 'Region saved');
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.graphic_eq),
          title: const Text('Frequency'),
          subtitle: Text('${(s.freqKhz / 1000).toStringAsFixed(3)} MHz'),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final lo = s.minFreqKhz / 1000, hi = s.maxFreqKhz / 1000;
            final v = await _ask(
              'Frequency (MHz)',
              '${lo.toStringAsFixed(3)} – ${hi.toStringAsFixed(3)}',
              (s.freqKhz / 1000).toStringAsFixed(3),
              type: const TextInputType.numberWithOptions(decimal: true),
              help: 'Every node in your group must use the same frequency. Applies after the node restarts.',
            );
            final mhz = double.tryParse(v?.trim() ?? '');
            if (v == null) return;
            if (mhz == null || mhz < lo || mhz > hi) {
              if (mounted) {
                showSnack(context, 'Use a frequency from ${lo.toStringAsFixed(3)} to ${hi.toStringAsFixed(3)} MHz');
              }
              return;
            }
            await _apply(pb.Settings(freqKhz: (mhz * 1000).round()), 'Frequency saved');
          },
        ),
        _PowerTile(
          value: dbm,
          min: minDbm,
          max: maxDbm,
          onChanged: (v) async {
            if (v > kGeneralMaxDbm &&
                !await _confirm(
                  'Transmit at ${powerLabel(v)}?',
                  'This is above the 22 dBm most boards stop at. You are responsible for staying within the '
                      'limit where you are, including your antenna\'s gain. More power also drains the battery faster.',
                  'Set power',
                )) {
              return;
            }
            await _apply(pb.Settings(outputDbm: v), 'Power set to ${powerLabel(v)}');
          },
        ),
        const _Section('Security'),
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: const Text('Channel key'),
          subtitle: Text(
            s.channelKeyOn
                ? 'On: beacons and plain messages are protected with a shared key'
                : 'Off: no shared channel key',
          ),
          trailing: PopupMenuButton<String>(
            tooltip: 'Channel key options',
            onSelected: (a) => unawaited(_channelKey(a)),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new', child: Text('New random key')),
              const PopupMenuItem(value: 'enter', child: Text('Enter a key')),
              if (s.channelKeyOn) const PopupMenuItem(value: 'off', child: Text('Remove the key')),
            ],
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.lock_outline),
          title: const Text('Refuse unencrypted messages'),
          subtitle: const Text('Plain messages without the channel key are dropped. Applies after a restart.'),
          value: s.requireEncryption,
          onChanged: (v) => unawaited(_apply(pb.Settings(requireEncryption: v), 'Saved')),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.health_and_safety_outlined),
          title: const Text('SOS responder'),
          subtitle: const Text('This node acknowledges SOS calls it hears. Applies after a restart.'),
          value: s.responder,
          onChanged: (v) => unawaited(_apply(pb.Settings(responder: v), 'Saved')),
        ),
        if (s.hasBlePin())
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: const Text('Bluetooth pairing key'),
            subtitle: Text(s.blePin == '654321' ? '${s.blePin} (the default)' : s.blePin, style: GwText.mono),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await _ask(
                'Bluetooth pairing key',
                '6 digits',
                s.blePin,
                type: TextInputType.number,
                help: 'Used for new pairings after the node restarts. Phones already paired keep working.',
              );
              if (v == null) return;
              if (!RegExp(r'^\d{6}$').hasMatch(v.trim())) {
                if (mounted) showSnack(context, 'The key must be exactly 6 digits');
                return;
              }
              await _apply(pb.Settings(blePin: v.trim()), 'Pairing key saved');
            },
          ),
        if (s.screenFitted || s.ledsFitted || s.buttonFitted) const _Section('Device'),
        if (s.screenFitted)
          ListTile(
            leading: const Icon(Icons.screen_lock_portrait_outlined),
            title: const Text('Screen turns off after'),
            subtitle: Text(screenTimeoutLabel(s.screenOffS)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final v = await _pick<int>('Screen turns off after', {
                for (final t in kScreenTimeouts) t: screenTimeoutLabel(t),
              }, s.screenOffS);
              if (v != null && v != s.screenOffS) await _apply(pb.Settings(screenOffS: v), 'Screen timeout saved');
            },
          ),
        if (s.ledsFitted)
          SwitchListTile(
            secondary: const Icon(Icons.lightbulb_outline),
            title: const Text('Status lights'),
            subtitle: const Text('Blink while running, show a connected phone, flash during an SOS'),
            value: s.leds,
            onChanged: (v) => unawaited(_apply(pb.Settings(leds: v), v ? 'Lights on' : 'Lights off')),
          ),
        if (s.buttonFitted)
          SwitchListTile(
            secondary: const Icon(Icons.sos),
            title: const Text('Hold the button for SOS'),
            subtitle: Text(
              s.buttonSosAllowed
                  ? 'Hold 3 seconds to start an SOS, double-press to stop it. The button still turns screen pages.'
                  : 'Not on this board: its button shares a line with the USB serial chip, so a cable could '
                        'hold it down. Start an SOS from the app.',
            ),
            value: s.buttonSosAllowed && s.buttonSos,
            onChanged: s.buttonSosAllowed
                ? (v) => unawaited(_apply(pb.Settings(buttonSos: v), v ? 'Button SOS on' : 'Button SOS off'))
                : null,
          ),
        const SizedBox(height: GwSpace.lg),
      ],
    );
  }

  Future<void> _channelKey(String action) async {
    switch (action) {
      case 'new':
        final rnd = Random.secure();
        final key = Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('New channel key'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Every node in your group needs this same key. Copy it before saving.'),
                const SizedBox(height: GwSpace.sm),
                SelectableText(keyHex(key), style: GwText.mono),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: keyHex(key)))),
                child: const Text('Copy'),
              ),
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
            ],
          ),
        );
        if (ok == true) await _apply(pb.Settings(channelKey: key), 'Channel key on');
      case 'enter':
        final v = await _ask('Channel key', '64 hex characters', '', help: 'The same key as the rest of your group.');
        if (v == null) return;
        final key = parseKeyHex(v);
        if (key == null) {
          if (mounted) showSnack(context, 'A channel key is 64 hex characters (0-9, a-f)');
          return;
        }
        await _apply(pb.Settings(channelKey: key), 'Channel key on');
      case 'off':
        if (await _confirm(
          'Remove the channel key?',
          'Nodes that still use it will not hear this one. Applies after the node restarts.',
          'Remove',
        )) {
          await _apply(pb.Settings(channelKeyOn: false), 'Channel key removed');
        }
    }
  }
}

class _PowerTile extends StatefulWidget {
  const _PowerTile({required this.value, required this.min, required this.max, required this.onChanged});

  final int value, min, max;
  final ValueChanged<int> onChanged;

  @override
  State<_PowerTile> createState() => _PowerTileState();
}

class _PowerTileState extends State<_PowerTile> {
  late double _v = widget.value.toDouble();

  @override
  void didUpdateWidget(_PowerTile old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _v = widget.value.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final v = _v.round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GwSpace.md, vertical: GwSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_outlined),
              const SizedBox(width: GwSpace.md),
              Expanded(child: Text('Output power: ${powerLabel(v)}', style: Theme.of(context).textTheme.bodyLarge)),
            ],
          ),
          Slider(
            value: _v.clamp(widget.min.toDouble(), widget.max.toDouble()),
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            divisions: widget.max > widget.min ? widget.max - widget.min : null,
            label: powerLabel(v),
            semanticFormatterCallback: (x) => powerLabel(x.round()),
            onChanged: widget.max > widget.min ? (x) => setState(() => _v = x) : null,
            onChangeEnd: (x) {
              if (x.round() != widget.value) widget.onChanged(x.round());
            },
          ),
          Text(
            'This board: ${widget.min} to ${widget.max} dBm at the antenna port.'
            '${widget.max > kGeneralMaxDbm ? ' Above $kGeneralMaxDbm dBm, check your local limits.' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.hint, required this.initial, this.type, this.help});

  final String title, hint, initial;
  final TextInputType? type;
  final String? help;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _c,
          autofocus: true,
          keyboardType: widget.type,
          decoration: InputDecoration(hintText: widget.hint),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        if (widget.help != null) ...[
          const SizedBox(height: GwSpace.sm),
          Text(widget.help!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Save')),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: GwSpace.md),
    child: SectionLabel(text),
  );
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.all(GwSpace.md),
    child: Padding(
      padding: const EdgeInsets.all(GwSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.restart_alt),
          const SizedBox(width: GwSpace.md),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}
