import 'package:ghostwave_app/src/data/history_crypto.dart';

/// One key store for every test, so a new [MeshStore] over the same folder
/// can read what an earlier one wrote, as after an app restart.
final HistoryKeys testHistoryKeys = MemoryHistoryKeys();
