import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import '../app/preferences.dart';
import '../app/trip_controller.dart';
import '../data/models.dart';
import '../data/trip.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

const _reminderChoices = [0, 30, 60, 120, 240];
const _overdueChoices = [0, 60, 120, 240, 480, 720];

String _minutes(int m) => m == 0
    ? 'Off'
    : m < 60
    ? '$m min'
    : '${m ~/ 60} h';

/// A short summary of the trip for the SOS tab, opening [TripScreen].
class TripCard extends ConsumerWidget {
  /// Creates the card.
  const TripCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider);
    final mesh = ref.watch(meshProvider);
    final plan = trip.plan;
    final now = DateTime.now();
    final overdue = [
      for (final p in plan.contacts)
        if (isOverdue(plan, p, mesh.messages, now)) p,
    ];
    final scheme = Theme.of(context).colorScheme;
    final detail = plan.contacts.isEmpty
        ? 'Pick up to $kMaxTripContacts people to check in with: I\'m OK, At camp, Delayed, Heading back.'
        : [
            plan.active ? 'Trip on since ${clockTime(plan.startedAt!)}' : 'No trip on',
            '${plan.contacts.length} trip ${plan.contacts.length == 1 ? 'contact' : 'contacts'}',
            if (trip.lastSent case final s?) 'last check-in ${timeAgo(s.at)}',
          ].join(' · ');
    return Card(
      child: ListTile(
        leading: Icon(
          overdue.isEmpty ? Icons.hiking : Icons.warning_amber_rounded,
          color: overdue.isEmpty ? GwColors.spectralCyan : scheme.error,
          size: 32,
        ),
        title: Text(
          overdue.isEmpty
              ? 'Trip & check-ins'
              : '${overdue.map(mesh.nameOf).join(', ')} ${overdue.length == 1 ? 'is' : 'are'} overdue',
        ),
        subtitle: Text(detail),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TripScreen()))),
      ),
    );
  }
}

/// Plan a trip, check in with one tap, and see your trip contacts.
class TripScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const TripScreen({super.key});

  @override
  ConsumerState<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends ConsumerState<TripScreen> {
  bool _sending = false;

  Future<void> _checkIn(CheckInKind kind) async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await ref.read(tripProvider.notifier).checkIn(kind);
      messenger.showSnackBar(
        SnackBar(content: Text('"${kind.label}" sent to $n ${n == 1 ? 'person' : 'people'}. Delivery shows below.')),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Check-in not sent: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(tripProvider);
    final mesh = ref.watch(meshProvider);
    final ctl = ref.read(tripProvider.notifier);
    final plan = trip.plan;
    final noContacts = plan.contacts.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Trip & check-ins')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(GwSpace.lg, GwSpace.sm, GwSpace.lg, GwSpace.xl),
        children: [
          ReadableWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SignalPanel(
                  icon: Icons.hiking,
                  title: 'Check in with your people',
                  detail:
                      'One tap sends an encrypted message with your position to every trip contact. You see '
                      'who it reached. Check-ins are ordinary messages, so they also show in each chat.',
                ),
                const SizedBox(height: GwSpace.md),
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        leading: Icon(plan.active ? Icons.play_circle : Icons.pause_circle_outline),
                        title: Text(plan.active ? 'Trip on since ${clockTime(plan.startedAt!)}' : 'No trip on'),
                        subtitle: Text(
                          plan.active
                              ? 'Reminders: ${_minutes(plan.reminderMinutes)} · overdue after: ${_minutes(plan.overdueMinutes)}'
                              : 'Start a trip to turn on reminders and overdue warnings.',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(GwSpace.lg, 0, GwSpace.lg, GwSpace.md),
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: plan.active
                              ? OutlinedButton(onPressed: ctl.end, child: const Text('End trip'))
                              : FilledButton(onPressed: noContacts ? null : ctl.start, child: const Text('Start trip')),
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionLabel('Check in'),
                if (noContacts)
                  const Padding(
                    padding: EdgeInsets.only(bottom: GwSpace.sm),
                    child: Text('Pick trip contacts below first.'),
                  ),
                LayoutBuilder(
                  builder: (context, box) {
                    final w = box.maxWidth >= 520
                        ? (box.maxWidth - GwSpace.md * 3) / 4
                        : (box.maxWidth - GwSpace.md) / 2;
                    return Wrap(
                      spacing: GwSpace.md,
                      runSpacing: GwSpace.md,
                      children: [
                        for (final k in CheckInKind.values)
                          SizedBox(
                            width: w,
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                              onPressed: noContacts || _sending ? null : () => _checkIn(k),
                              icon: Icon(switch (k) {
                                CheckInKind.ok => Icons.check_circle_outline,
                                CheckInKind.camp => Icons.cabin_outlined,
                                CheckInKind.delayed => Icons.schedule,
                                CheckInKind.headingBack => Icons.u_turn_left,
                              }),
                              label: Text(k.label),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                if (trip.lastSent case final last?) ...[
                  SectionLabel('Your last check-in: ${last.kind.label}, ${timeAgo(last.at)}'),
                  for (final MapEntry(key: peer, value: st) in deliveryMap(last, mesh).entries)
                    ListTile(
                      dense: true,
                      title: Text(mesh.nameOf(peer)),
                      subtitle: Text(switch (st) {
                        MsgState.delivered => 'delivered',
                        MsgState.sent => 'accepted by your radio, not confirmed yet',
                        MsgState.pending => 'waiting on this phone',
                        MsgState.failed => 'failed',
                        null => 'message deleted from this phone',
                      }),
                      leading: Icon(switch (st) {
                        MsgState.delivered => Icons.done_all,
                        MsgState.failed => Icons.error_outline,
                        _ => Icons.schedule,
                      }, color: st == MsgState.delivered ? GwColors.success : null),
                      trailing: st == MsgState.delivered
                          ? null
                          : IconButton(
                              tooltip: 'Send again',
                              onPressed: () => unawaited(ctl.resend(last, peer)),
                              icon: const Icon(Icons.replay),
                            ),
                    ),
                ],
                SectionLabel('Trip contacts (${plan.contacts.length} of $kMaxTripContacts)'),
                for (final peer in plan.contacts) _TeamRow(peer: peer, plan: plan, mesh: mesh),
                if (mesh.contacts.isEmpty)
                  const Text('No contacts yet. Add people in Chats first.')
                else
                  Wrap(
                    spacing: GwSpace.xs,
                    runSpacing: GwSpace.xs,
                    children: [
                      for (final c in mesh.contacts.values)
                        FilterChip(
                          label: Text(mesh.nameOf(c.nodeId)),
                          selected: plan.contacts.contains(c.nodeId),
                          onSelected: (_) {
                            if (!ctl.toggleContact(c.nodeId)) {
                              showSnack(context, 'At most $kMaxTripContacts trip contacts');
                            }
                          },
                        ),
                    ],
                  ),
                const SectionLabel('Reminders'),
                _Choice(
                  label: 'Remind me to check in every',
                  value: plan.reminderMinutes,
                  choices: _reminderChoices,
                  onChanged: (v) => ctl.setPlan(plan.copyWith(reminderMinutes: v)),
                ),
                _Choice(
                  label: 'Warn me when a contact has not checked in for',
                  value: plan.overdueMinutes,
                  choices: _overdueChoices,
                  onChanged: (v) => ctl.setPlan(plan.copyWith(overdueMinutes: v)),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: GwSpace.sm),
                  child: Text(
                    'Reminders and warnings are notifications on this phone, while GhostWave is running. '
                    'Nothing extra is sent on the mesh.',
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

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.value, required this.choices, required this.onChanged});

  final String label;
  final int value;
  final List<int> choices;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: GwSpace.sm),
    child: DropdownButtonFormField<int>(
      initialValue: choices.contains(value) ? value : 0,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final c in choices) DropdownMenuItem(value: c, child: Text(_minutes(c)))],
      onChanged: (v) => onChanged(v ?? 0),
    ),
  );
}

/// One trip contact: last check-in, where, when last heard, overdue.
class _TeamRow extends ConsumerWidget {
  const _TeamRow({required this.peer, required this.plan, required this.mesh});

  final int peer;
  final TripPlan plan;
  final MeshState mesh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitsProvider);
    final scheme = Theme.of(context).colorScheme;
    final last = lastCheckInFrom(peer, mesh.messages);
    final overdue = isOverdue(plan, peer, mesh.messages, DateTime.now());
    final heard = mesh.neighbors[peer]?.lastSeen ?? mesh.contacts[peer]?.lastSeen;
    final own = mesh.ownPos;
    final where = last?.$1.pos;
    final lines = [
      if (last == null) 'No check-in yet' else '${last.$1.kind.label}, ${timeAgo(last.$2)}',
      if (own != null && where != null)
        '${formatDistance(own.distanceTo(where), units)} ${compassPoint(own.bearingTo(where))} at check-in',
      if (heard != null) 'heard ${timeAgo(heard)}',
    ];
    return Card(
      color: overdue ? GwColors.alertContainer : null,
      child: ListTile(
        leading: Icon(
          overdue ? Icons.warning_amber_rounded : Icons.person_pin_circle_outlined,
          color: overdue ? GwColors.onAlertContainer : null,
          semanticLabel: overdue ? 'overdue' : null,
        ),
        title: Text(
          overdue ? '${mesh.nameOf(peer)} · overdue' : mesh.nameOf(peer),
          style: overdue ? TextStyle(color: GwColors.onAlertContainer, fontWeight: FontWeight.w700) : null,
        ),
        subtitle: Text(
          lines.join(' · '),
          style: overdue
              ? const TextStyle(color: GwColors.onAlertContainer)
              : TextStyle(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
