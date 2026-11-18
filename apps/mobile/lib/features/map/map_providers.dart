import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/env.dart';
import '../../core/api_client.dart';

/// One supported tile/routing provider.
enum MapProvider { mapbox, google, mappls, here, tomtom, osrm }

/// OpenStreetMap raster tiles — free, no API key. Used as the safe fallback
/// whenever a provider's own key is missing so the map is never blank.
const String _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Whether a real Mapbox token is configured (not the committed placeholder).
bool get hasMapboxToken =>
    Env.mapboxPublicToken.startsWith('pk.') &&
    Env.mapboxPublicToken != 'pk.REPLACE_ME';

/// Whether a Mappls (MapmyIndia) REST key is configured. Mappls renders the
/// official Survey-of-India boundaries, which is a legal requirement for maps
/// shown in India — so when a key is present we default to it.
bool get hasMapplsKey => Env.mapplsRestKey.trim().isNotEmpty;

extension MapProviderInfo on MapProvider {
  String get id {
    switch (this) {
      case MapProvider.mapbox:
        return 'mapbox';
      case MapProvider.google:
        return 'google';
      case MapProvider.mappls:
        return 'mappls';
      case MapProvider.here:
        return 'here';
      case MapProvider.tomtom:
        return 'tomtom';
      case MapProvider.osrm:
        return 'osrm';
    }
  }

  String get displayName {
    switch (this) {
      case MapProvider.mapbox:
        return 'Mapbox';
      case MapProvider.google:
        return 'Google Maps';
      case MapProvider.mappls:
        return 'Mappls (MapmyIndia)';
      case MapProvider.here:
        return 'HERE';
      case MapProvider.tomtom:
        return 'TomTom';
      case MapProvider.osrm:
        return 'OpenStreetMap (OSRM)';
    }
  }

  /// Raster tile URL template for this provider's default style.
  /// `{z}/{x}/{y}` placeholders. Tokens read from [Env].
  String get tileUrlTemplate {
    switch (this) {
      case MapProvider.mapbox:
        // Without a real token Mapbox returns 401 and the map goes blank —
        // fall back to free OSM tiles so the map always renders.
        if (!hasMapboxToken) return _osmTileUrl;
        return 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/'
            'tiles/256/{z}/{x}/{y}@2x'
            '?access_token=${Env.mapboxPublicToken}';
      case MapProvider.google:
        // Google's static tile URLs aren't generally allowed for raster
        // overlay; using their Tile API requires an extra session token.
        // For v1 we fall back to OSM raster when the user picks Google
        // for routing — they still get Google ETAs and polylines.
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapProvider.mappls:
        // Mappls XYZ raster tiles — official Indian boundaries. Falls back to
        // OSM only if the key is missing so the map never goes blank.
        if (!hasMapplsKey) return _osmTileUrl;
        return 'https://apis.mappls.com/advancedmaps/v1/'
            '${Env.mapplsRestKey}/map_tiles/{z}/{x}/{y}.png';
      case MapProvider.here:
        return 'https://maps.hereapi.com/v3/base/mc/'
            '{z}/{x}/{y}/png8'
            '?apiKey=${Env.hereApiKey}&style=explore.day&size=256';
      case MapProvider.tomtom:
        return 'https://api.tomtom.com/map/1/tile/basic/main/'
            '{z}/{x}/{y}.png?key=${Env.tomtomApiKey}';
      case MapProvider.osrm:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }

  String get attribution {
    switch (this) {
      case MapProvider.mapbox:
        return '© Mapbox · © OpenStreetMap';
      case MapProvider.google:
        return '© Google · © OpenStreetMap';
      case MapProvider.mappls:
        return '© Mappls · © MapmyIndia';
      case MapProvider.here:
        return '© HERE';
      case MapProvider.tomtom:
        return '© TomTom';
      case MapProvider.osrm:
        return '© OpenStreetMap contributors';
    }
  }

  static MapProvider fromId(String id) {
    return MapProvider.values.firstWhere(
      (p) => p.id == id,
      orElse: () => MapProvider.mapbox,
    );
  }
}

/// Persists the user's chosen tile provider in SharedPreferences and
/// exposes it as a Riverpod state. The trip map screen rebuilds the
/// `TileLayer` whenever this changes.
class MapProviderController extends StateNotifier<MapProvider> {
  MapProviderController(this._prefs) : super(_load(_prefs));

  static const _key = 'pp.map_provider';
  final SharedPreferences _prefs;

  static MapProvider _load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    // Default to OpenStreetMap when no Mapbox token is configured, so a fresh
    // install shows a real map instead of a blank Mapbox 401.
    if (raw == null) {
      // Prefer Mappls in India (correct Survey-of-India borders), then Mapbox,
      // else free OSM so a fresh install always shows a real map.
      if (hasMapplsKey) return MapProvider.mappls;
      return hasMapboxToken ? MapProvider.mapbox : MapProvider.osrm;
    }
    return MapProviderInfo.fromId(raw);
  }

  Future<void> set(MapProvider value) async {
    state = value;
    await _prefs.setString(_key, value.id);
  }
}

final mapProviderControllerProvider =
    StateNotifierProvider<MapProviderController, MapProvider>((ref) {
  // SharedPreferences is loaded synchronously by the bootstrap call in
  // main.dart, so this lookup never blocks.
  throw UnimplementedError(
    'mapProviderControllerProvider must be overridden in main.dart',
  );
});

/// Server-known providers — fetched from the backend so we can mark
/// each entry as "configured on the server" in the picker.
class ServerProviders {
  const ServerProviders({
    required this.defaultProvider,
    required this.configured,
  });

  final String defaultProvider;
  final Set<String> configured;
}

class MapsApi {
  MapsApi(this._dio);

  final Dio _dio;

  Future<ServerProviders> fetchProviders() async {
    final response = await _dio.get('/maps/providers');
    final data = response.data as Map<String, dynamic>;
    return ServerProviders(
      defaultProvider: data['default'] as String,
      configured: {
        for (final entry in (data['providers'] as List))
          if ((entry as Map<String, dynamic>)['configured'] == true)
            entry['name'] as String,
      },
    );
  }
}

final mapsApiProvider = FutureProvider<MapsApi>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return MapsApi(dio);
});

final serverProvidersProvider = FutureProvider<ServerProviders>((ref) async {
  try {
    final api = await ref.watch(mapsApiProvider.future);
    return await api.fetchProviders();
  } catch (_) {
    return const ServerProviders(
      defaultProvider: 'mapbox',
      configured: {'mapbox', 'osrm'},
    );
  }
});
