import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../shared/models/waypoint.dart';
import '../profile/me_repository.dart';
import '../trips/trips_repository.dart';
import '../trips/waypoints_repository.dart';
import 'live_trip_controller.dart';

/// Full-screen native Google map. Google serves India its official
/// Survey-of-India boundaries, so this is the India-correct view of the live
/// pack. The Maps SDK key is supplied via android/local.properties
/// (`google.maps.key`); if it is missing the map renders blank but the app
/// never crashes.
class GoogleNativeMapScreen extends ConsumerStatefulWidget {
  const GoogleNativeMapScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<GoogleNativeMapScreen> createState() =>
      _GoogleNativeMapScreenState();
}

class _GoogleNativeMapScreenState extends ConsumerState<GoogleNativeMapScreen> {
  GoogleMapController? _ctrl;
  bool _framed = false;

  double _hue(String hex) {
    final h = hex.replaceAll('#', '');
    final v = int.tryParse(h, radix: 16) ?? 0x888888;
    return HSVColor.fromColor(Color(0xFF000000 | v)).hue;
  }

  Future<void> _frame(List<LatLng> pts) async {
    final c = _ctrl;
    if (c == null || pts.isEmpty) return;
    if (pts.length == 1) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 14));
      return;
    }
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    await c.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      64,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveTripProvider(widget.tripId));
    final myId = ref.watch(meProvider).valueOrNull?.id;
    final colors = ref.watch(tripDetailProvider(widget.tripId)).maybeWhen(
          data: (t) => {
            for (final m in t.members)
              m.userId: (
                color: m.color,
                name: m.displayName ?? 'Member ${m.userId.substring(0, 4)}',
              ),
          },
          orElse: () => const <String, ({String color, String name})>{},
        );
    final route = ref.watch(tripRouteProvider(widget.tripId)).valueOrNull;
    final waypoints =
        ref.watch(tripWaypointsProvider(widget.tripId)).valueOrNull ??
            const <WaypointDto>[];

    final markers = <Marker>{};
    final all = <LatLng>[];

    for (var i = 0; i < waypoints.length; i++) {
      final ll.LatLng g = waypoints[i].latLng;
      final pos = LatLng(g.latitude, g.longitude);
      all.add(pos);
      markers.add(Marker(
        markerId: MarkerId('wp_$i'),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(title: waypoints[i].name),
      ));
    }

    for (final e in live.members.entries) {
      final isMe = e.key == myId;
      final p = e.value.position;
      final pos = LatLng(p.latitude, p.longitude);
      all.add(pos);
      final meta = colors[e.key];
      markers.add(Marker(
        markerId: MarkerId('m_${e.key}'),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          isMe
              ? BitmapDescriptor.hueGreen
              : (meta != null ? _hue(meta.color) : BitmapDescriptor.hueAzure),
        ),
        infoWindow: InfoWindow(title: isMe ? 'You' : (meta?.name ?? 'Member')),
      ));
    }

    final polylines = <Polyline>{};
    if (route != null && route.points.length >= 2) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points:
            route.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
        color: const Color(0xFF3F7E4E),
        width: 5,
      ));
    }

    // Frame everyone once we have the controller and some points.
    if (!_framed && all.isNotEmpty && _ctrl != null) {
      _framed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _frame(all));
    }

    final start = all.isNotEmpty ? all.first : const LatLng(22.9734, 78.6569);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Google · India map'),
        actions: [
          IconButton(
            tooltip: 'Frame everyone',
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () => _frame(all),
          ),
        ],
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: start,
          zoom: all.isNotEmpty ? 13 : 4,
        ),
        markers: markers,
        polylines: polylines,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        onMapCreated: (c) {
          _ctrl = c;
          if (!_framed && all.isNotEmpty) {
            _framed = true;
            _frame(all);
          }
        },
      ),
    );
  }
}
