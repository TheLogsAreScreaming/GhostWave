/// Waypoint screens: the editor (drop or change a pin), the list, a details
/// sheet, and a navigate view with distance and bearing from the phone.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/location_share.dart';
import '../app/mesh_controller.dart';
import '../app/preferences.dart';
import '../app/waypoint_actions.dart';
import '../data/waypoints.dart';
import '../link/contact_card.dart';
import '../link/geo.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// The icon for each kind (always shown with its name or read out with it).
IconData waypointIcon(WaypointKind k) => switch (k) {
  WaypointKind.camp => Icons.cabin,
  WaypointKind.water => Icons.water_drop,
  WaypointKind.hazard => Icons.warning_amber,
  WaypointKind.parking => Icons.local_parking,
  WaypointKind.meet => Icons.groups,
  WaypointKind.other => Icons.push_pin,
};

/// Marker fill per kind: dark enough for a white icon (3:1 or better) on light
/// map tiles. The icon shape, not the colour, tells kinds apart.
Color waypointColor(WaypointKind k) => switch (k) {
  WaypointKind.camp => const Color(0xFF2E7D32),
  WaypointKind.water => const Color(0xFF1565C0),
  WaypointKind.hazard => const Color(0xFFB45309),
  WaypointKind.parking => const Color(0xFF283593),
  WaypointKind.meet => const Color(0xFF8E24AA),
  WaypointKind.other => const Color(0xFF455A64),
};

/// Who shared [w], in words.
String waypointOwner(Waypoint w, MeshState mesh) => w.mine ? 'You' : mesh.nameOf(w.owner!);

/// Where [w] went or came from, in words ("" when kept on this phone).
String waypointPlace(Waypoint w, MeshState mesh) {
  if (w.channel case final ch?) return '#$ch';
  if (w.peer case final p?) return mesh.nameOf(p);
  return '';
}

/// "1.2 km NE (bearing 47°)" from [from] to [to].
String distanceAndBearing(LatLon from, LatLon to, Units units) {
  final b = from.bearingTo(to);
  return '${formatDistance(from.distanceTo(to), units)} ${compassPoint(b)} (bearing ${b.round()}°)';
}

/// What a screen reader says for [w].
String waypointSpoken(Waypoint w, MeshState mesh, Units units) {
  final from = mesh.ownPos;
  return [
    'Waypoint, ${w.kind.label}: ${w.name}',
    if (w.mine) 'yours' else 'from ${waypointOwner(w, mesh)}',
    if (w.note.isNotEmpty) w.note,
    if (from != null) distanceAndBearing(from, w.pos, units),
    if (w.hidden) 'hidden from the map',
  ].join('. ');
}

/// A map marker for [w]: a round pin with the kind's icon.
class WaypointMarker extends ConsumerWidget {
  /// Creates the marker.
  const WaypointMarker({super.key, required this.waypoint});

  /// The pin.
  final Waypoint waypoint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesh = ref.watch(meshProvider);
    final units = ref.watch(unitsProvider);
    return Semantics(
      button: true,
      label: waypointSpoken(waypoint, mesh, units),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => unawaited(showWaypointDetails(context, waypoint.key)),
        child: Container(
          decoration: BoxDecoration(
            color: waypointColor(waypoint.kind),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
          ),
          alignment: Alignment.center,
          child: Icon(waypointIcon(waypoint.kind), color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// Opens the editor for a new waypoint at [pos] (or the node's position).
Future<void> openNewWaypoint(BuildContext context, {LatLon? pos}) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => WaypointEditorScreen(initialPos: pos)));

/// Drop a new waypoint, or change one of ours ([editKey]).
class WaypointEditorScreen extends ConsumerStatefulWidget {
  /// Creates the editor.
  const WaypointEditorScreen({super.key, this.initialPos, this.editKey});

  /// Where a new pin goes.
  final LatLon? initialPos;

  /// Our waypoint to change; null for a new one.
  final String? editKey;

  @override
  ConsumerState<WaypointEditorScreen> createState() => _WaypointEditorScreenState();
}

class _WaypointEditorScreenState extends ConsumerState<WaypointEditorScreen> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  WaypointKind _kind = WaypointKind.other;
  WaypointTarget _to = const KeepLocal();
  Waypoint? _editing;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final mesh = ref.read(meshProvider);
    final key = widget.editKey;
    final w = key == null ? null : mesh.waypoints.byKey[key];
    _editing = w;
    if (w != null) {
      _kind = w.kind;
      _name.text = w.name;
      _note.text = w.note;
      _to = targetOf(w);
    }
    final p = w?.pos ?? widget.initialPos ?? mesh.ownPos;
    if (p != null) _setPos(p);
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  void _setPos(LatLon p) {
    _lat.text = p.lat.toStringAsFixed(5);
    _lon.text = p.lon.toStringAsFixed(5);
  }

  LatLon? get _pos {
    final lat = double.tryParse(_lat.text.trim());
    final lon = double.tryParse(_lon.text.trim());
    if (lat == null || lon == null || !lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) return null;
    return LatLon(lat, lon);
  }

  Waypoint? _draft() {
    final pos = _pos;
    if (pos == null) return null;
    final name = cleanWaypointText(_name.text, kWaypointNameMax);
    return Waypoint(
      id: _editing?.id ?? '0000',
      kind: _kind,
      name: name.isEmpty ? _kind.label : name,
      pos: pos,
      at: DateTime.now(),
      note: cleanWaypointText(_note.text, kWaypointNoteMax),
    );
  }

  /// What the radio will carry, and whether the note had to be cut.
  ({int bytes, int max, bool cut, bool fits})? _budget(Waypoint d) {
    if (_to is KeepLocal) return null;
    final actions = ref.read(waypointActionsProvider);
    final max = actions.maxBytesFor(_to);
    final text = waypointText(d.toWire(), max);
    if (text == null) return (bytes: 0, max: max, cut: true, fits: false);
    final back = parseWaypoint(text);
    final cut = back is! WaypointPut || back.note != d.note || back.name != d.name;
    return (bytes: utf8Length(text), max: max, cut: cut, fits: true);
  }

  Future<void> _save() async {
    final d = _draft();
    if (d == null || _busy) return;
    setState(() => _busy = true);
    final actions = ref.read(waypointActionsProvider);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final editing = _editing;
      if (editing == null) {
        await actions.create(kind: d.kind, name: d.name, pos: d.pos, note: d.note, to: _to);
      } else {
        await actions.edit(editing.key, kind: d.kind, name: d.name, note: d.note, pos: d.pos);
      }
      if (!mounted) return;
      nav.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _to is KeepLocal
                ? 'Waypoint saved on this phone'
                : 'Waypoint ${editing == null ? 'sent' : 'update sent'} to ${_targetName(_to, ref.read(meshProvider))}',
          ),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, 'Waypoint not saved: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    final editing = _editing;
    final draft = _draft();
    final budget = draft == null ? null : _budget(draft);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(editing == null ? 'New waypoint' : 'Edit waypoint')),
      body: ReadableWidth(
        maxWidth: 640,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(GwSpace.lg, GwSpace.md, GwSpace.lg, GwSpace.xl),
          children: [
            Semantics(header: true, child: Text('What is here', style: text.titleSmall)),
            const SizedBox(height: GwSpace.xs),
            Wrap(
              spacing: GwSpace.xs,
              runSpacing: GwSpace.xs,
              children: [
                for (final k in WaypointKind.values)
                  ChoiceChip(
                    avatar: Icon(waypointIcon(k), size: 18),
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: GwSpace.md),
            TextField(
              controller: _name,
              maxLength: kWaypointNameMax,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: 'Name', hintText: 'For example: ${_kind.label} by the creek'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _note,
              maxLength: kWaypointNoteMax,
              minLines: 1,
              maxLines: 4,
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\r\n]'), replacementString: ' ')],
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: GwSpace.sm),
            Semantics(header: true, child: Text('Where', style: text.titleSmall)),
            const SizedBox(height: GwSpace.xs),
            Wrap(
              spacing: GwSpace.md,
              runSpacing: GwSpace.xs,
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: const InputDecoration(labelText: 'Latitude'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _lon,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: const InputDecoration(labelText: 'Longitude'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (_pos == null)
              Padding(
                padding: const EdgeInsets.only(top: GwSpace.xs),
                child: Text(
                  'Enter a latitude (-90 to 90) and longitude (-180 to 180), or use your position.',
                  style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (mesh.ownPos case final own?)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  icon: const Icon(Icons.my_location),
                  label: const Text('Use my position'),
                  onPressed: () => setState(() => _setPos(own)),
                ),
              ),
            const SizedBox(height: GwSpace.sm),
            Semantics(header: true, child: Text('Share', style: text.titleSmall)),
            const SizedBox(height: GwSpace.xs),
            if (editing == null)
              _TargetPicker(value: _to, mesh: mesh, onChanged: (t) => setState(() => _to = t))
            else
              Text(
                _to is KeepLocal
                    ? 'Kept on this phone. Share it from the waypoint list.'
                    : 'Changes are sent to ${_targetName(_to, mesh)}, so it updates on their maps too.',
              ),
            if (budget != null) ...[
              const SizedBox(height: GwSpace.xs),
              Text(
                !budget.fits
                    ? 'Too long for one ${budget.max}-byte radio message. Shorten the name.'
                    : budget.cut
                    ? 'Shortened to fit one radio message (${budget.bytes} of ${budget.max} bytes). '
                          'Shorten the note to send all of it.'
                    : 'Fits one radio message (${budget.bytes} of ${budget.max} bytes).',
                style: text.bodySmall,
              ),
            ],
            const SizedBox(height: GwSpace.lg),
            FilledButton.icon(
              icon: Icon(_to is KeepLocal ? Icons.save_outlined : Icons.send),
              label: Text(_to is KeepLocal ? 'Save waypoint' : (editing == null ? 'Save and send' : 'Save and update')),
              onPressed: draft == null || _busy || (budget != null && !budget.fits) ? null : () => unawaited(_save()),
            ),
          ],
        ),
      ),
    );
  }
}

String _targetName(WaypointTarget t, MeshState mesh) => switch (t) {
  KeepLocal() => 'this phone only',
  ToContact(:final peer) => mesh.nameOf(peer),
  ToChannel(:final channel) => '#$channel',
};

/// Choose: this phone only, a channel, or a contact.
class _TargetPicker extends StatelessWidget {
  const _TargetPicker({required this.value, required this.mesh, required this.onChanged});

  final WaypointTarget value;
  final MeshState mesh;
  final ValueChanged<WaypointTarget> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <WaypointTarget>[
      const KeepLocal(),
      for (final ch in mesh.channels.keys) ToChannel(ch),
      for (final c in mesh.contacts.values) ToContact(c.nodeId),
    ];
    return DropdownButtonFormField<WaypointTarget>(
      initialValue: options.contains(value) ? value : const KeepLocal(),
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Send to'),
      items: [
        for (final o in options)
          DropdownMenuItem(
            value: o,
            child: Text(switch (o) {
              KeepLocal() => 'Only this phone (not sent)',
              ToChannel(:final channel) => 'Channel #$channel',
              ToContact(:final peer) => 'Contact ${mesh.nameOf(peer)}',
            }),
          ),
      ],
      onChanged: (t) => onChanged(t ?? const KeepLocal()),
    );
  }
}

/// Every waypoint, ours and others', with a switch for hidden ones.
class WaypointsScreen extends ConsumerStatefulWidget {
  /// Creates the list. [center] is where "New waypoint" starts (the map's
  /// centre); the node's position otherwise.
  const WaypointsScreen({super.key, this.center});

  /// Starting point for a new waypoint.
  final LatLon? center;

  @override
  ConsumerState<WaypointsScreen> createState() => _WaypointsScreenState();
}

class _WaypointsScreenState extends ConsumerState<WaypointsScreen> {
  bool _showHidden = false;

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    final units = ref.watch(unitsProvider);
    final all = mesh.waypoints.all;
    final hiddenCount = all.where((w) => w.hidden).length;
    final shown = [
      for (final w in all)
        if (_showHidden || !w.hidden) w,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Waypoints')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('New waypoint'),
        onPressed: () => unawaited(openNewWaypoint(context, pos: widget.center ?? mesh.ownPos)),
      ),
      body: ReadableWidth(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(GwSpace.md, GwSpace.md, GwSpace.md, 96),
          children: [
            SignalPanel(
              icon: Icons.push_pin_outlined,
              title: all.isEmpty ? 'No waypoints yet' : '${all.length} waypoints',
              detail:
                  'Long-press the map, or tap New waypoint, to mark a camp, water, a hazard, parking or a '
                  'meeting point. Send it to a contact or a channel and it shows on their maps too. '
                  'It travels as one short message, so older apps show it as text.',
            ),
            if (hiddenCount > 0)
              SwitchListTile(
                title: Text('Show hidden ($hiddenCount)'),
                value: _showHidden,
                onChanged: (v) => setState(() => _showHidden = v),
              ),
            for (final w in shown) _WaypointTile(waypoint: w, mesh: mesh, units: units),
          ],
        ),
      ),
    );
  }
}

class _WaypointTile extends StatelessWidget {
  const _WaypointTile({required this.waypoint, required this.mesh, required this.units});

  final Waypoint waypoint;
  final MeshState mesh;
  final Units units;

  @override
  Widget build(BuildContext context) {
    final w = waypoint;
    final from = mesh.ownPos;
    final place = waypointPlace(w, mesh);
    final sub = [
      w.kind.label,
      if (w.mine)
        (place.isEmpty ? 'yours, on this phone only' : 'yours, sent to $place')
      else
        'from ${waypointOwner(w, mesh)}',
      if (from != null) distanceAndBearing(from, w.pos, units),
      timeAgo(w.at),
      if (w.hidden) 'hidden',
    ].join(' · ');
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${waypointSpoken(w, mesh, units)}. ${timeAgo(w.at)}',
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: waypointColor(w.kind),
          child: Icon(waypointIcon(w.kind), color: Colors.white),
        ),
        title: Text(w.name),
        subtitle: Text(w.note.isEmpty ? sub : '$sub\n${w.note}'),
        isThreeLine: w.note.isNotEmpty,
        onTap: () => unawaited(showWaypointDetails(context, w.key)),
      ),
    );
  }
}

/// Shows waypoint [key] in a sheet with what can be done with it.
Future<void> showWaypointDetails(BuildContext context, String key) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _WaypointSheet(waypointKey: key),
);

class _WaypointSheet extends ConsumerWidget {
  const _WaypointSheet({required this.waypointKey});

  final String waypointKey;

  Future<void> _share(BuildContext context, WidgetRef ref, Waypoint w) async {
    final mesh = ref.read(meshProvider);
    final to = await showDialog<WaypointTarget>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Send waypoint to'),
        children: [
          for (final ch in mesh.channels.keys)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ToChannel(ch)), child: Text('Channel #$ch')),
          for (final c in mesh.contacts.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ToContact(c.nodeId)),
              child: Text('Contact ${mesh.nameOf(c.nodeId)}'),
            ),
          if (mesh.channels.isEmpty && mesh.contacts.isEmpty)
            const Padding(padding: EdgeInsets.all(GwSpace.lg), child: Text('No contacts or channels yet.')),
        ],
      ),
    );
    if (to == null || !context.mounted) return;
    try {
      await ref.read(waypointActionsProvider).share(w.key, to);
      if (context.mounted) showSnack(context, 'Waypoint sent to ${_targetName(to, ref.read(meshProvider))}');
    } on Object catch (e) {
      if (context.mounted) showSnack(context, 'Waypoint not sent: $e');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Waypoint w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${w.name}?'),
        content: Text(
          w.shared
              ? 'It goes from your map, and a short message takes it off the maps of '
                    '${waypointPlace(w, ref.read(meshProvider))} too.'
              : 'It goes from this phone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final actions = ref.read(waypointActionsProvider);
    Navigator.of(context).pop();
    await actions.delete(w.key);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesh = ref.watch(meshProvider);
    final units = ref.watch(unitsProvider);
    final w = mesh.waypoints.byKey[waypointKey];
    final text = Theme.of(context).textTheme;
    if (w == null) {
      return const Padding(padding: EdgeInsets.all(GwSpace.xl), child: Text('This waypoint was removed.'));
    }
    final actions = ref.read(waypointActionsProvider);
    final from = mesh.ownPos;
    final place = waypointPlace(w, mesh);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(GwSpace.lg, 0, GwSpace.lg, GwSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: CircleAvatar(
                    backgroundColor: waypointColor(w.kind),
                    child: Icon(waypointIcon(w.kind), color: Colors.white),
                  ),
                ),
                const SizedBox(width: GwSpace.md),
                Expanded(
                  child: Semantics(header: true, child: Text(w.name, style: text.titleLarge)),
                ),
              ],
            ),
            const SizedBox(height: GwSpace.sm),
            Text(w.kind.label, style: text.titleSmall),
            if (w.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: GwSpace.xs),
                child: Text(w.note),
              ),
            const SizedBox(height: GwSpace.sm),
            Text(
              w.mine
                  ? (place.isEmpty ? 'Yours, kept on this phone.' : 'Yours, sent to $place.')
                  : 'From ${waypointOwner(w, mesh)}${place.isEmpty || w.channel == null ? '' : ' in $place'}, ${timeAgo(w.at)}.',
            ),
            SelectableText('${w.pos.lat.toStringAsFixed(5)}, ${w.pos.lon.toStringAsFixed(5)}', style: GwText.mono),
            Text(
              from == null
                  ? 'Your position is not known yet, so no distance.'
                  : '${distanceAndBearing(from, w.pos, units)} from you',
            ),
            const SizedBox(height: GwSpace.md),
            Wrap(
              spacing: GwSpace.sm,
              runSpacing: GwSpace.sm,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Navigate'),
                  onPressed: () => unawaited(
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => WaypointNavigateScreen(waypointKey: w.key))),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Show on map'),
                  onPressed: () {
                    ref.read(mapFocusProvider.notifier).show(w.pos, '${w.kind.label}: ${w.name}');
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                ),
                if (w.mine) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                    onPressed: () {
                      final nav = Navigator.of(context)..pop();
                      unawaited(
                        nav.push(
                          MaterialPageRoute<void>(
                            fullscreenDialog: true,
                            builder: (_) => WaypointEditorScreen(editKey: w.key),
                          ),
                        ),
                      );
                    },
                  ),
                  if (!w.shared)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Share'),
                      onPressed: () => unawaited(_share(context, ref, w)),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    onPressed: () => unawaited(_delete(context, ref, w)),
                  ),
                ] else ...[
                  OutlinedButton.icon(
                    icon: Icon(w.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    label: Text(w.hidden ? 'Show on my map' : 'Hide from my map'),
                    onPressed: () => actions.setHidden(w.key, !w.hidden),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove from this phone'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      actions.forget(w.key);
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Distance and bearing to a waypoint, live from the phone's GPS (or the
/// node's position when the phone's is not available).
class WaypointNavigateScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const WaypointNavigateScreen({super.key, required this.waypointKey});

  /// The waypoint.
  final String waypointKey;

  @override
  ConsumerState<WaypointNavigateScreen> createState() => _WaypointNavigateScreenState();
}

class _WaypointNavigateScreenState extends ConsumerState<WaypointNavigateScreen> {
  StreamSubscription<LatLon>? _sub;
  LatLon? _phone;
  LocationAccess? _access;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final source = ref.read(positionSourceProvider);
    try {
      final access = await source.ensureAccess();
      if (!mounted) return;
      setState(() => _access = access);
      if (access != LocationAccess.granted) return;
      _sub = source
          .watch(distanceFilterM: 2)
          .listen(
            (p) {
              if (mounted) setState(() => _phone = p);
            },
            onError: (Object _) {
              // keep the last fix; the node's position is the fallback
            },
          );
    } on Object {
      if (mounted) setState(() => _access = LocationAccess.denied);
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    final units = ref.watch(unitsProvider);
    final w = mesh.waypoints.byKey[widget.waypointKey];
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (w == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Navigate')),
        body: const Center(child: Text('This waypoint was removed.')),
      );
    }
    final from = _phone ?? mesh.ownPos;
    final source = _phone != null
        ? 'From your phone\'s GPS.'
        : from != null
        ? (_access == null || _access == LocationAccess.granted
              ? 'Waiting for the phone\'s GPS; using your node\'s position for now.'
              : 'Phone location is off for GhostWave, so this uses your node\'s position.')
        : (_access == null || _access == LocationAccess.granted
              ? 'Waiting for a position fix…'
              : 'No position: allow location for GhostWave, or let your node get a GPS fix.');
    final bearing = from?.bearingTo(w.pos);
    final distance = from?.distanceTo(w.pos);
    return Scaffold(
      appBar: AppBar(title: Text('To ${w.name}')),
      body: ReadableWidth(
        maxWidth: 640,
        child: ListView(
          padding: const EdgeInsets.all(GwSpace.lg),
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: CircleAvatar(
                    backgroundColor: waypointColor(w.kind),
                    child: Icon(waypointIcon(w.kind), color: Colors.white),
                  ),
                ),
                const SizedBox(width: GwSpace.md),
                Expanded(child: Text('${w.kind.label}: ${w.name}', style: text.titleMedium)),
              ],
            ),
            const SizedBox(height: GwSpace.xl),
            if (bearing != null && distance != null) ...[
              Semantics(
                liveRegion: true,
                label:
                    '${formatDistance(distance, units)} away, ${compassPoint(bearing)}, '
                    'bearing ${bearing.round()} degrees from north',
                excludeSemantics: true,
                child: Column(
                  children: [
                    Transform.rotate(
                      angle: bearing * 3.141592653589793 / 180,
                      child: Icon(Icons.navigation, size: 120, color: scheme.primary),
                    ),
                    const SizedBox(height: GwSpace.md),
                    Text(formatDistance(distance, units), style: text.displaySmall, textAlign: TextAlign.center),
                    Text(
                      '${compassPoint(bearing)} · bearing ${bearing.round()}°',
                      style: text.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GwSpace.md),
              Text(
                'The arrow points along the bearing with north at the top of the screen. '
                'Hold the phone with its top to the north (use a compass) to follow it.',
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: GwSpace.md),
            Text(source, style: text.bodyMedium, textAlign: TextAlign.center),
            if (_access == LocationAccess.deniedForever || _access == LocationAccess.serviceOff)
              Center(
                child: TextButton(
                  onPressed: () => unawaited(ref.read(positionSourceProvider).openSettings(_access!)),
                  child: const Text('Open settings'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
