import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../config/env.dart';

/// Live group map. v1 placeholder: just renders Mapbox raster tiles.
/// Weekend 3 will add the WebSocket location stream and member markers.
class TripMapScreen extends ConsumerWidget {
  const TripMapScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('Trip $tripId')),
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(28.6139, 77.2090), // New Delhi
          initialZoom: 12,
        ),
        children: [
          TileLayer(
            urlTemplate:
                '${Env.mapboxStyleUrl}?access_token=${Env.mapboxPublicToken}',
            userAgentPackageName: 'app.packpath.mobile',
            maxZoom: 19,
          ),
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('© Mapbox'),
              TextSourceAttribution('© OpenStreetMap contributors'),
            ],
          ),
        ],
      ),
    );
  }
}
