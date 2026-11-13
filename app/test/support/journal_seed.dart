// A mesh state with two journal entries, for journal widget tests and screenshots.
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/data/node_journal.dart';
import 'package:ghostwave_app/src/link/geo.dart';

/// A contact heard every hour from one place.
const int ridge = 0x1A2B3C4D;

/// A heard node whose position moves.
const int rover = 0x0C0FFEE0;

/// A controller that starts from [seed] instead of a node.
class SeededMesh extends MeshController {
  /// Creates the controller.
  SeededMesh(this.seed);

  /// The starting state.
  final MeshState seed;

  @override
  MeshState build() => seed;
}

/// Ridge (always-on relay, tagged, with a note) and Rover (roamer), as of [now].
MeshState journalSeedState(DateTime now) {
  var j = const NodeJournal();
  for (var h = 0; h < 30; h++) {
    j = j.record(ridge, now.subtract(Duration(hours: 29 - h)), HeardVia.beacon, pos: const LatLon(45, -110));
  }
  for (var i = 0; i < 3; i++) {
    j = j.record(
      rover,
      now.subtract(Duration(hours: 3 - i)),
      HeardVia.beacon,
      pos: LatLon(45 + i * 0.018, -110),
      rssiDbm: -104,
      name: 'Rover',
    );
  }
  j = j.withTags(ridge, ['lookout']).withNote(ridge, 'Solar repeater on the ridge.');
  return MeshState(
    nodeId: 0x11111111,
    journal: j,
    contacts: {ridge: const Contact(nodeId: ridge, name: 'Ridge', pinned: true)},
  );
}
