import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../map/offline_maps.dart';

/// Uses a tile from a saved offline region when there is one, and the network
/// otherwise.
class OfflineFirstTileProvider extends TileProvider {
  /// Creates a provider reading [regions] from [store].
  factory OfflineFirstTileProvider({required OfflineStore? store, required List<OfflineRegion> regions}) {
    final headers = <String, String>{'User-Agent': kTileUserAgent};
    return OfflineFirstTileProvider._(store, regions, headers, NetworkTileProvider(headers: headers));
  }

  OfflineFirstTileProvider._(this._store, this._regions, Map<String, String> headers, this._net)
    : super(headers: headers);

  final OfflineStore? _store;
  final List<OfflineRegion> _regions;
  final NetworkTileProvider _net;

  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    final store = _store;
    if (store != null) {
      for (final r in _regions) {
        final f = store.tileFile(r.id, TileId(coordinates.z, coordinates.x, coordinates.y));
        if (f.existsSync()) return FileImage(File(f.path));
      }
    }
    return _net.getImageWithCancelLoadingSupport(coordinates, options, cancelLoading);
  }

  @override
  void dispose() {
    _net.dispose();
    super.dispose();
  }
}
