/// Offline map regions: which tiles a region needs, downloading them from a
/// tile server that allows it, and finding them again.
///
/// The OpenStreetMap tile servers forbid this: their usage policy says
/// "offline use is not permitted" and bans fetching tiles the user is not
/// viewing (https://operations.osmfoundation.org/policies/tiles/). So regions
/// can only be downloaded from a tile URL the user configured, and
/// [isForbiddenBulkSource] refuses OSM's servers in code, not just in the UI.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// The default base map: online viewing only.
const String kOsmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Names the app to tile servers, as the OSM policy requires.
const String kTileUserAgent = 'GhostWave-app/0.1 (+https://github.com/TheLogsAreScreaming/GhostWave)';

/// Highest zoom a region may be downloaded at.
const int kMaxOfflineZoom = 16;

/// Most tiles in one region.
const int kMaxRegionTiles = 15000;

/// Most storage all regions may use, bytes.
const int kMaxOfflineBytes = 1024 * 1024 * 1024;

/// Average tile size used for estimates, bytes.
const int kEstimatedTileBytes = 25 * 1024;

/// Whether [template] is usable: http(s), with `{z}`, `{x}` and `{y}` and no
/// other placeholder.
bool validTileUrl(String template) {
  final t = template.trim();
  if (!t.contains('{z}') || !t.contains('{x}') || !t.contains('{y}')) return false;
  final plain = t.replaceAll('{z}', '0').replaceAll('{x}', '0').replaceAll('{y}', '0');
  if (plain.contains('{') || plain.contains('}')) return false;
  final u = Uri.tryParse(plain);
  return u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty;
}

/// Whether [template] points at servers whose policy forbids bulk download.
bool isForbiddenBulkSource(String template) {
  final plain = template.trim().replaceAll('{z}', '0').replaceAll('{x}', '0').replaceAll('{y}', '0');
  final host = (Uri.tryParse(plain)?.host ?? '').toLowerCase();
  return host == 'openstreetmap.org' ||
      host.endsWith('.openstreetmap.org') ||
      host == 'osm.org' ||
      host.endsWith('.osm.org');
}

/// A tile address.
class TileId {
  /// Creates an address.
  const TileId(this.z, this.x, this.y);

  /// Zoom.
  final int z;

  /// Column.
  final int x;

  /// Row.
  final int y;

  /// The URL of this tile under [template].
  Uri url(String template) =>
      Uri.parse(template.trim().replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y'));
}

/// A rectangle of the map and a zoom range.
class RegionBounds {
  /// Creates bounds, in degrees.
  const RegionBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.minZoom,
    required this.maxZoom,
  });

  /// South edge.
  final double south;

  /// West edge.
  final double west;

  /// North edge.
  final double north;

  /// East edge.
  final double east;

  /// Lowest zoom.
  final int minZoom;

  /// Highest zoom.
  final int maxZoom;

  static int _col(double lon, int z) {
    final n = 1 << z;
    return (((lon + 180) / 360) * n).floor().clamp(0, n - 1);
  }

  static int _row(double lat, int z) {
    final n = 1 << z;
    final r = lat.clamp(-85.05112878, 85.05112878) * math.pi / 180;
    return (((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2) * n).floor().clamp(0, n - 1);
  }

  /// How many tiles the region needs.
  int get tileCount {
    var total = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      total += (_col(east, z) - _col(west, z) + 1) * (_row(south, z) - _row(north, z) + 1);
    }
    return total;
  }

  /// Rough download size, bytes.
  int get estimatedBytes => tileCount * kEstimatedTileBytes;

  /// Every tile in the region, low zoom first.
  Iterable<TileId> get tiles sync* {
    for (var z = minZoom; z <= maxZoom; z++) {
      for (var x = _col(west, z); x <= _col(east, z); x++) {
        for (var y = _row(north, z); y <= _row(south, z); y++) {
          yield TileId(z, x, y);
        }
      }
    }
  }
}

/// A downloaded region.
class OfflineRegion {
  /// Creates a record.
  const OfflineRegion({
    required this.id,
    required this.name,
    required this.bounds,
    required this.urlTemplate,
    required this.tiles,
    required this.bytes,
    required this.failed,
  });

  /// From [toJson].
  factory OfflineRegion.fromJson(Map<String, Object?> j) => OfflineRegion(
    id: j['id']! as String,
    name: j['name']! as String,
    bounds: RegionBounds(
      south: (j['s']! as num).toDouble(),
      west: (j['w']! as num).toDouble(),
      north: (j['n']! as num).toDouble(),
      east: (j['e']! as num).toDouble(),
      minZoom: j['minz']! as int,
      maxZoom: j['maxz']! as int,
    ),
    urlTemplate: j['url']! as String,
    tiles: j['tiles']! as int,
    bytes: j['bytes']! as int,
    failed: (j['failed'] as int?) ?? 0,
  );

  /// Folder name.
  final String id;

  /// User's name for it.
  final String name;

  /// What it covers.
  final RegionBounds bounds;

  /// The tile source it came from.
  final String urlTemplate;

  /// Tiles saved.
  final int tiles;

  /// Bytes saved.
  final int bytes;

  /// Tiles that could not be fetched.
  final int failed;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    's': bounds.south,
    'w': bounds.west,
    'n': bounds.north,
    'e': bounds.east,
    'minz': bounds.minZoom,
    'maxz': bounds.maxZoom,
    'url': urlTemplate,
    'tiles': tiles,
    'bytes': bytes,
    if (failed != 0) 'failed': failed,
  };
}

/// A tile server said to stop (or refused access).
class TileServerRefused implements Exception {
  /// Creates the exception.
  const TileServerRefused(this.status);

  /// HTTP status.
  final int status;

  @override
  String toString() => 'the tile server answered HTTP $status';
}

/// Fetches one tile; null if the server has none. Throws [TileServerRefused]
/// when the download should stop.
typedef TileFetcher = Future<Uint8List?> Function(Uri url);

/// [TileFetcher] over HTTP, naming the app.
Future<Uint8List?> httpTileFetcher(Uri url) async {
  final client = HttpClient()..userAgent = kTileUserAgent;
  try {
    final req = await client.getUrl(url).timeout(const Duration(seconds: 20));
    final res = await req.close().timeout(const Duration(seconds: 20));
    final body = await res.fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d));
    if (res.statusCode == 200) return body.takeBytes();
    if (res.statusCode == 404 || res.statusCode == 204) return null;
    if (res.statusCode == 401 || res.statusCode == 403 || res.statusCode == 429) {
      throw TileServerRefused(res.statusCode);
    }
    throw HttpException('HTTP ${res.statusCode}', uri: url);
  } finally {
    client.close();
  }
}

/// Offline regions on disk, under `<dir>/offline_maps`.
class OfflineStore {
  /// Creates a store in [dir].
  OfflineStore(Directory dir) : root = Directory('${dir.path}/offline_maps');

  /// Base folder.
  final Directory root;

  File get _manifest => File('${root.path}/regions.json');

  /// The saved regions; empty if none or unreadable.
  Future<List<OfflineRegion>> load() async {
    try {
      if (!_manifest.existsSync()) return const [];
      final j = jsonDecode(await _manifest.readAsString()) as List<Object?>;
      return [for (final r in j) OfflineRegion.fromJson((r! as Map<Object?, Object?>).cast<String, Object?>())];
    } on Object {
      return const [];
    }
  }

  /// Saves the region list atomically.
  Future<void> save(List<OfflineRegion> regions) async {
    await root.create(recursive: true);
    final tmp = File('${_manifest.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final r in regions) r.toJson()]), flush: true);
    await tmp.rename(_manifest.path);
  }

  /// Where tile [t] of region [id] lives.
  File tileFile(String id, TileId t) => File('${root.path}/$id/${t.z}/${t.x}/${t.y}.png');

  /// Stores one tile; a crash never leaves half of one.
  Future<void> putTile(String id, TileId t, Uint8List bytes) async {
    final f = tileFile(id, t);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes);
    await tmp.rename(f.path);
  }

  /// Deletes a region's tiles.
  Future<void> deleteTiles(String id) async {
    final d = Directory('${root.path}/$id');
    if (d.existsSync()) await d.delete(recursive: true);
  }

  /// Deletes everything (app data reset).
  Future<void> deleteAll() async {
    if (root.existsSync()) await root.delete(recursive: true);
  }
}

/// Download progress.
class DownloadProgress {
  /// Creates a report.
  const DownloadProgress(this.done, this.total, this.bytes);

  /// Tiles handled.
  final int done;

  /// Tiles in the region.
  final int total;

  /// Bytes saved so far.
  final int bytes;
}

/// Why a region cannot be downloaded; null if it can.
String? refuseDownload(RegionBounds b, String template, {int usedBytes = 0}) {
  if (!validTileUrl(template)) return 'Set a valid tile URL first.';
  if (isForbiddenBulkSource(template)) {
    return 'OpenStreetMap\'s tile servers do not allow downloads for offline use. '
        'Set a tile URL from a provider that does, or your own tile server.';
  }
  if (b.maxZoom > kMaxOfflineZoom) return 'Zoom is limited to $kMaxOfflineZoom.';
  if (b.tileCount > kMaxRegionTiles) {
    return 'That is ${b.tileCount} tiles; the limit is $kMaxRegionTiles. Zoom in, or lower the detail.';
  }
  if (usedBytes + b.estimatedBytes > kMaxOfflineBytes) {
    return 'That would pass the ${kMaxOfflineBytes ~/ (1024 * 1024)} MB limit. Delete a region first.';
  }
  return null;
}

/// Downloads [bounds] into region [id], two tiles at a time. Tiles already
/// saved are kept. Stops when [cancelled] says so; [TileServerRefused] ends it.
Future<OfflineRegion> downloadRegion({
  required OfflineStore store,
  required String id,
  required String name,
  required RegionBounds bounds,
  required String urlTemplate,
  required TileFetcher fetch,
  void Function(DownloadProgress)? onProgress,
  bool Function()? cancelled,
}) async {
  final why = refuseDownload(bounds, urlTemplate);
  if (why != null) throw StateError(why);
  final queue = bounds.tiles.iterator;
  final total = bounds.tileCount;
  var done = 0, saved = 0, bytes = 0, failed = 0;
  Object? stop;

  Future<void> worker() async {
    while (stop == null && !(cancelled?.call() ?? false) && queue.moveNext()) {
      final t = queue.current;
      try {
        final f = store.tileFile(id, t);
        if (f.existsSync()) {
          bytes += f.lengthSync();
          saved++;
        } else {
          final data = await fetch(t.url(urlTemplate));
          if (data != null) {
            await store.putTile(id, t, data);
            bytes += data.length;
            saved++;
          }
        }
      } on TileServerRefused catch (e) {
        stop = e;
      } on Object {
        failed++;
      }
      done++;
      onProgress?.call(DownloadProgress(done, total, bytes));
    }
  }

  await Future.wait([worker(), worker()]);
  if (stop != null) {
    await store.deleteTiles(id);
    throw stop!;
  }
  return OfflineRegion(
    id: id,
    name: name,
    bounds: bounds,
    urlTemplate: urlTemplate,
    tiles: saved,
    bytes: bytes,
    failed: failed + (total - done),
  );
}
