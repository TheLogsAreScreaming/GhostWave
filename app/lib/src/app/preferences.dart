/// App-side settings and small cross-screen signals.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../link/geo.dart';
import '../map/offline_maps.dart';
import 'providers.dart';

/// Distance units.
enum Units {
  /// Metres and kilometres.
  metric,

  /// Feet and miles.
  imperial,
}

/// The chosen units (saved).
class UnitsNotifier extends Notifier<Units> {
  static const _key = 'units';

  @override
  Units build() => ref.watch(sharedPrefsProvider).getString(_key) == 'imperial' ? Units.imperial : Units.metric;

  /// Chooses [u].
  void set(Units u) {
    state = u;
    unawaited(ref.read(sharedPrefsProvider).setString(_key, u.name));
  }
}

/// Distance units.
final unitsProvider = NotifierProvider<UnitsNotifier, Units>(UnitsNotifier.new);

/// Whether the first-run walkthrough has been finished (saved).
class WalkthroughNotifier extends Notifier<bool> {
  static const _key = 'walkthrough_done';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? false;

  /// Records that it was finished or skipped.
  void finish() {
    state = true;
    unawaited(ref.read(sharedPrefsProvider).setBool(_key, true));
  }
}

/// Whether the walkthrough is done.
final walkthroughDoneProvider = NotifierProvider<WalkthroughNotifier, bool>(WalkthroughNotifier.new);

/// Where map tiles come from.
class TileSource {
  /// Creates a source.
  const TileSource({this.urlTemplate = kOsmTileUrl, this.attribution = ''});

  /// `https://host/{z}/{x}/{y}.png`.
  final String urlTemplate;

  /// Attribution for a custom source (empty: the OSM line).
  final String attribution;

  /// Whether this is the default OpenStreetMap server.
  bool get isDefault => urlTemplate == kOsmTileUrl;

  /// The line always shown on the map.
  String get attributionText => attribution.isEmpty ? '© OpenStreetMap contributors' : attribution;
}

/// The tile source (saved).
class TileSourceNotifier extends Notifier<TileSource> {
  static const _urlKey = 'tile_url';
  static const _attrKey = 'tile_attribution';

  @override
  TileSource build() {
    final p = ref.watch(sharedPrefsProvider);
    final url = p.getString(_urlKey);
    return TileSource(
      urlTemplate: url != null && validTileUrl(url) ? url : kOsmTileUrl,
      attribution: p.getString(_attrKey) ?? '',
    );
  }

  /// Saves a custom source; false if [url] is not usable.
  bool set(String url, String attribution) {
    final u = url.trim();
    if (!validTileUrl(u)) return false;
    state = TileSource(urlTemplate: u, attribution: attribution.trim());
    final p = ref.read(sharedPrefsProvider);
    unawaited(p.setString(_urlKey, u));
    unawaited(p.setString(_attrKey, attribution.trim()));
    return true;
  }

  /// Back to OpenStreetMap.
  void reset() {
    state = const TileSource();
    final p = ref.read(sharedPrefsProvider);
    unawaited(p.remove(_urlKey));
    unawaited(p.remove(_attrKey));
  }
}

/// Where tiles come from.
final tileSourceProvider = NotifierProvider<TileSourceNotifier, TileSource>(TileSourceNotifier.new);

/// Where offline regions live; overridden in `main`.
final offlineStoreProvider = Provider<OfflineStore?>((ref) => null);

/// Fetches tiles; tests override it.
final tileFetcherProvider = Provider<TileFetcher>((ref) => httpTileFetcher);

/// Offline regions and any download in progress.
class OfflineMapsState {
  /// Creates a state.
  const OfflineMapsState({this.regions = const [], this.job, this.jobName = '', this.error});

  /// Saved regions.
  final List<OfflineRegion> regions;

  /// Current download, or null.
  final DownloadProgress? job;

  /// Current download's name.
  final String jobName;

  /// Why the last download stopped.
  final String? error;

  /// Bytes used by saved regions.
  int get usedBytes => regions.fold(0, (a, r) => a + r.bytes);
}

/// Loads, downloads and deletes offline regions.
class OfflineMapsController extends Notifier<OfflineMapsState> {
  bool _cancel = false;

  OfflineStore? get _store => ref.read(offlineStoreProvider);

  @override
  OfflineMapsState build() {
    final store = ref.watch(offlineStoreProvider);
    if (store != null) {
      unawaited(
        store.load().then((r) {
          if (ref.mounted && state.regions.isEmpty) {
            state = OfflineMapsState(regions: r, job: state.job, jobName: state.jobName, error: state.error);
          }
        }),
      );
    }
    return const OfflineMapsState();
  }

  /// Why [b] cannot be downloaded right now, or null.
  String? refusal(RegionBounds b) => state.job != null
      ? 'A download is already running.'
      : refuseDownload(b, ref.read(tileSourceProvider).urlTemplate, usedBytes: state.usedBytes);

  /// Downloads a region; the outcome lands in the state.
  Future<void> download(String name, RegionBounds b) async {
    final store = _store;
    final why = refusal(b);
    if (store == null || why != null) {
      state = OfflineMapsState(regions: state.regions, error: why ?? 'Offline storage is not available.');
      return;
    }
    _cancel = false;
    final id = 'r${DateTime.now().microsecondsSinceEpoch}';
    state = OfflineMapsState(regions: state.regions, job: DownloadProgress(0, b.tileCount, 0), jobName: name);
    try {
      final region = await downloadRegion(
        store: store,
        id: id,
        name: name,
        bounds: b,
        urlTemplate: ref.read(tileSourceProvider).urlTemplate,
        fetch: ref.read(tileFetcherProvider),
        cancelled: () => _cancel,
        onProgress: (p) {
          if (ref.mounted) state = OfflineMapsState(regions: state.regions, job: p, jobName: name);
        },
      );
      if (!ref.mounted) return;
      if (_cancel) {
        await store.deleteTiles(id);
        if (ref.mounted) state = OfflineMapsState(regions: state.regions);
        return;
      }
      final regions = [...state.regions, region];
      await store.save(regions);
      if (ref.mounted) state = OfflineMapsState(regions: regions);
    } on Object catch (e) {
      if (ref.mounted) state = OfflineMapsState(regions: state.regions, error: 'Download stopped: $e');
    }
  }

  /// Stops the running download and discards it.
  void cancel() => _cancel = true;

  /// Deletes a region.
  Future<void> delete(OfflineRegion r) async {
    final regions = [
      for (final x in state.regions)
        if (x.id != r.id) x,
    ];
    state = OfflineMapsState(regions: regions, job: state.job, jobName: state.jobName);
    await _store?.deleteTiles(r.id);
    await _store?.save(regions);
  }

  /// Deletes everything (app data reset).
  Future<void> reset() async {
    _cancel = true;
    await _store?.deleteAll();
    if (ref.mounted) state = const OfflineMapsState();
  }
}

/// Offline regions.
final offlineMapsProvider = NotifierProvider<OfflineMapsController, OfflineMapsState>(OfflineMapsController.new);

/// A request to show a spot on the Map tab.
class MapFocus {
  /// Creates a request.
  const MapFocus(this.pos, this.title, this.serial);

  /// Where.
  final LatLon pos;

  /// What is there.
  final String title;

  /// Makes repeated requests for one spot distinct.
  final int serial;
}

/// Asks the Map tab to show a spot, and the shell to switch to it.
class MapFocusNotifier extends Notifier<MapFocus?> {
  int _serial = 0;

  @override
  MapFocus? build() => null;

  /// Shows [pos] on the map.
  void show(LatLon pos, String title) => state = MapFocus(pos, title, ++_serial);
}

/// The latest map focus request.
final mapFocusProvider = NotifierProvider<MapFocusNotifier, MapFocus?>(MapFocusNotifier.new);

/// The conversation open beside the chat list on wide windows; null = none.
class OpenChatNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  /// Opens the chat with [peer] in the side pane.
  void open(int peer) => state = peer;
}

/// The peer whose chat shows in the two-pane Chats layout.
final openChatProvider = NotifierProvider<OpenChatNotifier, int?>(OpenChatNotifier.new);
