import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart';

import '../../config/env.dart';

/// Hive-backed Mapbox tile cache.
///
/// We deliberately avoid `flutter_map_tile_caching` to keep the dependency
/// graph small. The cache stores raw PNG bytes keyed by `z/x/y` and is
/// shared across the whole app — one box, one disk file.
class TileCache {
  TileCache._(this._box);

  static const _boxName = 'pp.tile_cache';
  static TileCache? _instance;
  final Box<Uint8List> _box;

  static Future<TileCache> instance() async {
    if (_instance != null) return _instance!;
    final box = await Hive.openBox<Uint8List>(_boxName);
    _instance = TileCache._(box);
    return _instance!;
  }

  static String _key(int z, int x, int y) => '$z/$x/$y';

  Uint8List? get(int z, int x, int y) => _box.get(_key(z, x, y));

  Future<void> put(int z, int x, int y, Uint8List bytes) =>
      _box.put(_key(z, x, y), bytes);

  int get tileCount => _box.length;

  Future<void> clear() => _box.clear();

  /// Download every tile that intersects [bbox] for zoom levels in [zooms].
  /// Returns the number of *new* tiles fetched.
  Future<int> prefetchBbox({
    required LatLngBounds bbox,
    required Iterable<int> zooms,
    void Function(int done, int total)? onProgress,
    int concurrency = 4,
  }) async {
    final tiles = <_TileCoord>[];
    for (final z in zooms) {
      final tl = _latLngToTile(bbox.northWest, z);
      final br = _latLngToTile(bbox.southEast, z);
      final minX = math.min(tl.x, br.x);
      final maxX = math.max(tl.x, br.x);
      final minY = math.min(tl.y, br.y);
      final maxY = math.max(tl.y, br.y);
      for (var x = minX; x <= maxX; x++) {
        for (var y = minY; y <= maxY; y++) {
          if (_box.containsKey(_key(z, x, y))) continue;
          tiles.add(_TileCoord(z, x, y));
        }
      }
    }
    if (tiles.isEmpty) return 0;

    final dio = Dio(BaseOptions(responseType: ResponseType.bytes));
    var done = 0;
    var fetched = 0;
    final pool = _Pool(concurrency);

    await Future.wait([
      for (final t in tiles)
        pool.run(() async {
          try {
            final url = _urlFor(t);
            final r = await dio.get<List<int>>(url);
            if (r.statusCode == 200 && r.data != null) {
              await put(t.z, t.x, t.y, Uint8List.fromList(r.data!));
              fetched++;
            }
          } catch (_) {
            // Skip failed tiles; they'll fall back to network at view time.
          } finally {
            done++;
            onProgress?.call(done, tiles.length);
          }
        }),
    ]);
    return fetched;
  }

  static String _urlFor(_TileCoord t) {
    // Mapbox raster style endpoint, same as we use in MapTileLayer.
    return 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/'
        '${t.z}/${t.x}/${t.y}@2x?access_token=${Env.mapboxPublicToken}';
  }

  static _Tile _latLngToTile(LatLng p, int z) {
    final n = math.pow(2, z).toDouble();
    final x = ((p.longitude + 180) / 360 * n).floor();
    final latRad = p.latitude * math.pi / 180;
    final y =
        ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
                2 *
                n)
            .floor();
    return _Tile(x, y);
  }
}

class _Tile {
  const _Tile(this.x, this.y);
  final int x;
  final int y;
}

class _TileCoord {
  const _TileCoord(this.z, this.x, this.y);
  final int z;
  final int x;
  final int y;
}

/// Tiny semaphore — `dart:isolate` would be overkill here.
class _Pool {
  _Pool(this.size);
  final int size;
  int _running = 0;
  final _waiters = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= size) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
      if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
    }
  }
}

/// `flutter_map` provider that checks the Hive cache first, then falls
/// back to HTTP. Cache writes happen on miss too, so a session online
/// builds the cache for the next session offline.
class CachedMapboxTileProvider extends TileProvider {
  CachedMapboxTileProvider(this._cache);

  final TileCache _cache;
  final Dio _dio = Dio(BaseOptions(responseType: ResponseType.bytes));

  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options) {
    return _CachedTileImage(
      cache: _cache,
      dio: _dio,
      x: coords.x,
      y: coords.y,
      z: coords.z,
    );
  }
}

class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  _CachedTileImage({
    required this.cache,
    required this.dio,
    required this.x,
    required this.y,
    required this.z,
  });

  final TileCache cache;
  final Dio dio;
  final int x;
  final int y;
  final int z;

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) =>
      Future.value(this);

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0);
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final cached = cache.get(z, x, y);
    if (cached != null) {
      final buffer = await ui.ImmutableBuffer.fromUint8List(cached);
      return decode(buffer);
    }
    final url = TileCache._urlFor(_TileCoord(z, x, y));
    final r = await dio.get<List<int>>(url);
    final bytes = Uint8List.fromList(r.data ?? const []);
    if (bytes.isNotEmpty) {
      // Fire-and-forget cache write.
      unawaited(cache.put(z, x, y, bytes));
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is _CachedTileImage && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);
}
