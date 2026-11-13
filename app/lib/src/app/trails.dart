/// Records 24-hour trails while a trip is on: each trip contact's position
/// from its beacons and check-ins, and your own. Nobody else is recorded, and
/// nothing is recorded without a trip.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/trip.dart';
import 'mesh_controller.dart';
import 'trip_controller.dart';

/// Adds what [mesh] knows now to the trails of [trip]'s contacts and this
/// node. Positions carry the time they were true (beacon or check-in time);
/// repeats are ignored by the trail rules. Pure apart from [record].
void recordTrailsFrom(
  MeshState mesh,
  TripState trip,
  DateTime now,
  void Function(int id, double lat, double lon, DateTime at) record,
) {
  if (!trip.plan.active) return;
  for (final peer in trip.plan.contacts) {
    final n = mesh.neighbors[peer];
    if (n?.pos case final p?) record(peer, p.lat, p.lon, n!.lastSeen);
    if (lastCheckInFrom(peer, mesh.messages) case (final c, final at)) {
      if (c.pos case final p?) record(peer, p.lat, p.lon, at);
    }
  }
  final self = mesh.nodeId;
  if (self != null && mesh.ownPos != null) record(self, mesh.ownPos!.lat, mesh.ownPos!.lon, now);
}

/// Keeps recording while the app runs.
final trailsRecorderProvider = Provider<void>((ref) {
  void run() {
    final ctl = ref.read(meshProvider.notifier);
    recordTrailsFrom(
      ref.read(meshProvider),
      ref.read(tripProvider),
      ref.read(clockProvider)(),
      (id, lat, lon, at) => ctl.recordTrailAt(id, lat, lon, at),
    );
  }

  ref
    ..listen(meshProvider.select((m) => (m.neighbors, m.messages, m.ownPos)), (_, _) => run())
    ..listen(tripProvider, (_, _) => run());
});
