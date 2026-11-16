import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../../config/env.dart';

/// Everything a flutter_map [VectorTileLayer] needs to render Ola's vector
/// basemap: the parsed theme plus per-source tile providers whose URLs already
/// carry the api_key (Ola's TileJSON hands out keyless tile URLs, so we resolve
/// each source and bake the key into the template ourselves).
class OlaVectorStyle {
  OlaVectorStyle(
      {required this.theme, required this.providers, required this.maxZoom});
  final vtr.Theme theme;
  final TileProviders providers;
  final double maxZoom;
}

const _olaStyleUrl =
    'https://api.olamaps.io/tiles/vector/v1/styles/default-light-standard/style.json';

String _withKey(String url, String key) {
  if (key.isEmpty || !url.contains('olamaps.io') || url.contains('api_key=')) {
    return url;
  }
  return '$url${url.contains('?') ? '&' : '?'}api_key=$key';
}

/// Builds the Ola vector style once. Returns null when no key is configured
/// (callers then fall back to the raster basemap).
Future<OlaVectorStyle?> buildOlaVectorStyle() async {
  final key = Env.olaMapsApiKey;
  if (key.isEmpty) return null;

  final dio = Dio();
  final res = await dio.get<String>(
    _withKey(_olaStyleUrl, key),
    options: Options(responseType: ResponseType.plain),
  );
  final style = json.decode(res.data!) as Map<String, dynamic>;

  final providers = <String, VectorTileProvider>{};
  var maxZoom = 14.0;

  final sources = style['sources'];
  if (sources is Map) {
    for (final entry in sources.entries) {
      final name = entry.key as String;
      final src = entry.value;
      if (src is! Map || src['type'] != 'vector') continue;
      final url = src['url'];
      if (url is! String) continue;
      try {
        final tj = await dio.get<String>(
          _withKey(url, key),
          options: Options(responseType: ResponseType.plain),
        );
        final tjson = json.decode(tj.data!) as Map<String, dynamic>;
        final tiles = (tjson['tiles'] as List?)?.whereType<String>().toList();
        if (tiles == null || tiles.isEmpty) continue;
        final mz = (tjson['maxzoom'] as num?)?.toDouble() ?? 14.0;
        maxZoom = mz > maxZoom ? mz : maxZoom;
        providers[name] = NetworkVectorTileProvider(
          urlTemplate: _withKey(tiles.first, key),
          maximumZoom: mz.toInt(),
        );
      } catch (_) {
        // Skip a source we can't resolve; the rest still render.
      }
    }
  }

  if (providers.isEmpty) return null;

  final theme = vtr.ThemeReader().read(style);
  return OlaVectorStyle(
    theme: theme,
    providers: TileProviders(providers),
    maxZoom: maxZoom,
  );
}

/// Cached Ola vector style for the whole app. Null when no key is set.
final olaVectorStyleProvider = FutureProvider<OlaVectorStyle?>((ref) async {
  return buildOlaVectorStyle();
});
