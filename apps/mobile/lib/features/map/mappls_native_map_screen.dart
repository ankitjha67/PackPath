import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:mappls_gl/mappls_gl.dart';

import '../../shared/models/waypoint.dart';
import '../profile/me_repository.dart';
import '../trips/trips_repository.dart';
import '../trips/waypoints_repository.dart';
import 'live_trip_controller.dart';

/// Full-screen native Mappls (MapmyIndia) GL map. Mappls renders the official
/// Survey-of-India boundaries, which is a legal requirement for maps shown in
/// India — so this is the India-correct view of the live pack.
///
/// Authentication uses the app config files committed under android/app
/// (`<appId>.a.conf` / `.a.olf`), which are bound to the package name and the
/// signing certificate SHA-256 registered in the Mappls console.
class MapplsNativeMapScreen extends ConsumerStatefulWidget {
  const MapplsNativeMapScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<MapplsNativeMapScreen> createState() =>
      _MapplsNativeMapScreenState();
}

class _MapplsNativeMapScreenState extends ConsumerState<MapplsNativeMapScreen> {
  MapplsMapController? _ctrl;
  bool _styleReady = false;
  bool _framed = false;

  void _onMapCreated(MapplsMapController c) => _ctrl = c;

  void _onStyleLoaded() {
    _styleReady = true;
    _render();
  }

  /// Redraw all annotations from the latest live data.
  Future<void> _render() async {
    final c = _ctrl;
    if (c == null || !_styleReady) return;

    await c.clearCircles();
    await c.clearLines();

    final myId = ref.read(meProvider).valueOrNull?.id;
    final live = ref.read(liveTripProvider(widget.tripId));
    final colors = ref.read(tripDetailProvider(widget.tripId)).maybeWhen(
          data: (t) => {for (final m in t.members) m.userId: m.color},
          orElse: () => const <String, String>{},
        );
    final route = ref.read(tripRouteProvider(widget.tripId)).valueOrNull;
    final waypoints =
        ref.read(tripWaypointsProvider(widget.tripId)).valueOrNull ??
            const <WaypointDto>[];

    final pts = <LatLng>[];

    // Route polyline between waypoints.
    if (route != null && route.points.length >= 2) {
      await c.addLine(LineOptions(
        geometry:
            route.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
        lineColor: '#3F7E4E',
        lineWidth: 5.0,
        lineOpacity: 0.9,
      ));
    }

    // Waypoints as sienna markers.
    for (final w in waypoints) {
      final ll.LatLng g = w.latLng;
      pts.add(LatLng(g.latitude, g.longitude));
      await c.addCircle(CircleOptions(
        geometry: LatLng(g.latitude, g.longitude),
        circleRadius: 7.0,
        circleColor: '#C36B1D',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2.0,
      ));
    }

    // Each live member; mine drawn larger in the accent colour.
    for (final entry in live.members.entries) {
      final isMe = entry.key == myId;
      final p = entry.value.position;
      pts.add(LatLng(p.latitude, p.longitude));
      await c.addCircle(CircleOptions(
        geometry: LatLng(p.latitude, p.longitude),
        circleRadius: isMe ? 11.0 : 8.0,
        circleColor: isMe ? '#4E8F5C' : (colors[entry.key] ?? '#879D9A'),
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: isMe ? 3.0 : 2.0,
      ));
    }

    if (!_framed && pts.isNotEmpty) {
      _framed = true;
      await _frame(pts);
    }
  }

  Future<void> _frame(List<LatLng> pts) async {
    final c = _ctrl;
    if (c == null) return;
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
      left: 48,
      right: 48,
      top: 96,
      bottom: 96,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Redraw whenever the live positions change.
    ref.listen(liveTripProvider(widget.tripId), (_, __) => _render());
    ref.listen(tripWaypointsProvider(widget.tripId), (_, __) => _render());

    final live = ref.watch(liveTripProvider(widget.tripId));
    final myId = ref.watch(meProvider).valueOrNull?.id;
    final start = (myId != null ? live.members[myId]?.position : null) ??
        live.members.values.fold<ll.LatLng?>(null, (a, m) => a ?? m.position);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mappls · India map'),
        actions: [
          IconButton(
            tooltip: 'Frame everyone',
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () {
              _framed = false;
              _render();
            },
          ),
        ],
      ),
      body: MapplsMap(
        initialCameraPosition: CameraPosition(
          target: start != null
              ? LatLng(start.latitude, start.longitude)
              : const LatLng(22.9734, 78.6569), // geographic centre of India
          zoom: start != null ? 13 : 4,
        ),
        onMapCreated: _onMapCreated,
        onStyleLoadedCallback: _onStyleLoaded,
        myLocationEnabled: true,
      ),
    );
  }
}
