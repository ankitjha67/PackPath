import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../config/env.dart';
import '../map/live_trip_controller.dart';
import '../map/tile_cache.dart';
import '../voice/ptt_button.dart';
import 'eta_panel.dart';
import 'trips_repository.dart';
import 'waypoints_drawer.dart';
import 'waypoints_repository.dart';

/// Live group map for a single trip. Wires the WebSocket fan-out to
/// `flutter_map` markers, plus waypoint long-press to add, a polyline
/// fetched from the backend Mapbox Directions proxy, an offline tile
/// cache, follow-me / frame-all camera, and the LiveKit PTT button.
class TripMapScreen extends ConsumerStatefulWidget {
  const TripMapScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends ConsumerState<TripMapScreen> {
  final MapController _mapController = MapController();
  TileCache? _tileCache;
  CachedMapboxTileProvider? _tileProvider;
  bool _follow = true;
  String? _lastFollowedUser;
  double _downloadProgress = 0;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _bootCache();
  }

  Future<void> _bootCache() async {
    final cache = await TileCache.instance();
    if (!mounted) return;
    setState(() {
      _tileCache = cache;
      _tileProvider = CachedMapboxTileProvider(cache);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tripAsync = ref.watch(tripDetailProvider(widget.tripId));
    final live = ref.watch(liveTripProvider(widget.tripId));
    final waypointsAsync = ref.watch(tripWaypointsProvider(widget.tripId));
    final routeAsync = ref.watch(tripRouteProvider(widget.tripId));

    final waypoints = waypointsAsync.maybeWhen(
      data: (w) => w,
      orElse: () => const [],
    );

    // Auto-follow my last published location if follow mode is on.
    _maybeFollow(live);

    return Scaffold(
      appBar: AppBar(
        title: tripAsync.maybeWhen(
          data: (t) => Text(t.name),
          orElse: () => const Text('Trip'),
        ),
        actions: [
          IconButton(
            tooltip: 'Chat',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => context.push('/trips/${widget.tripId}/chat'),
          ),
          IconButton(
            tooltip: 'Invite',
            icon: const Icon(Icons.qr_code_2),
            onPressed: () => context.push('/trips/${widget.tripId}/share'),
          ),
          IconButton(
            tooltip: 'Waypoints',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => WaypointsDrawer(tripId: widget.tripId),
            ),
          ),
          IconButton(
            tooltip: 'ETA',
            icon: const Icon(Icons.access_time),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => EtaPanel(tripId: widget.tripId),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'offline') {
                await _downloadOfflineTiles(context, waypoints);
              } else if (value == 'recenter') {
                _frameAll(live, waypoints);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'offline',
                child: ListTile(
                  leading: Icon(Icons.cloud_download_outlined),
                  title: Text('Download offline tiles'),
                ),
              ),
              PopupMenuItem(
                value: 'recenter',
                child: ListTile(
                  leading: Icon(Icons.center_focus_strong),
                  title: Text('Frame everyone'),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  live.connected ? Icons.cloud_done : Icons.cloud_off,
                  color:
                      live.connected ? Colors.greenAccent : Colors.redAccent,
                ),
                if (live.queuedFrames > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${live.queuedFrames}',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(28.6139, 77.2090),
              initialZoom: 12,
              onLongPress: (_, point) =>
                  _onLongPress(context, point, waypoints.length),
              onPositionChanged: (cameraPosition, hasGesture) {
                if (hasGesture && _follow) {
                  setState(() => _follow = false);
                }
              },
            ),
            children: [
              TileLayer(
                // CachedMapboxTileProvider builds its own URL with the token,
                // but flutter_map still wants a template here (used for the
                // fallback NetworkTileProvider before the cache boots).
                urlTemplate:
                    'https://api.mapbox.com/styles/v1/mapbox/streets-v12/'
                    'tiles/256/{z}/{x}/{y}@2x'
                    '?access_token=${Env.mapboxPublicToken}',
                userAgentPackageName: 'app.packpath.mobile',
                maxZoom: 19,
                tileProvider: _tileProvider ?? NetworkTileProvider(),
              ),
              routeAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => _StraightLine(waypoints),
                data: (route) => route == null
                    ? _StraightLine(waypoints)
                    : PolylineLayer(
                        polylines: [
                          Polyline(
                            points: route.points,
                            color: Colors.blueAccent,
                            strokeWidth: 5,
                          ),
                        ],
                      ),
              ),
              MarkerLayer(
                markers: [
                  for (var i = 0; i < waypoints.length; i++)
                    Marker(
                      point: waypoints[i].latLng,
                      width: 36,
                      height: 36,
                      child: _WaypointPin(index: i + 1),
                    ),
                  for (final m in live.members.values)
                    Marker(
                      point: m.position,
                      width: 56,
                      height: 56,
                      child: _MemberDot(
                        color: _colorForUser(m.userId, tripAsync),
                        battery: m.battery,
                        heading: m.heading,
                      ),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© Mapbox'),
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          // Follow-me FAB and PTT button stack on the right.
          Positioned(
            right: 16,
            bottom: 100,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'follow',
                  backgroundColor:
                      _follow ? Colors.blue : Colors.white,
                  foregroundColor: _follow ? Colors.white : Colors.black87,
                  onPressed: () {
                    setState(() => _follow = true);
                    _maybeFollow(live, force: true);
                  },
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 12),
                PttButton(tripId: widget.tripId),
              ],
            ),
          ),
          if (_downloading)
            Positioned(
              top: 56,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Caching tiles for offline…'),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: _downloadProgress),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: tripAsync.when(
                  loading: () => const SizedBox(
                    height: 36,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Error: $e'),
                  data: (trip) => Row(
                    children: [
                      const Icon(Icons.group, size: 18),
                      const SizedBox(width: 8),
                      Text('${trip.members.length} in pack'),
                      const SizedBox(width: 16),
                      const Icon(Icons.flag_outlined, size: 18),
                      const SizedBox(width: 4),
                      Text('${waypoints.length}'),
                      const Spacer(),
                      if (_tileCache != null)
                        Text(
                          '${_tileCache!.tileCount} tiles cached',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(width: 12),
                      Text('Code ${trip.joinCode}'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _maybeFollow(LiveTripState live, {bool force = false}) {
    if (!_follow && !force) return;
    if (live.members.isEmpty) return;
    // Prefer the user we were already following so the camera doesn't snap
    // between members on every frame.
    final pick = _lastFollowedUser != null &&
            live.members.containsKey(_lastFollowedUser)
        ? live.members[_lastFollowedUser!]!
        : live.members.values.first;
    _lastFollowedUser = pick.userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapController.move(pick.position, _mapController.camera.zoom);
    });
  }

  void _frameAll(LiveTripState live, List waypoints) {
    final points = <LatLng>[
      ...live.members.values.map((m) => m.position),
      for (final w in waypoints) w.latLng as LatLng,
    ];
    if (points.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(60),
      ),
    );
    setState(() => _follow = false);
  }

  Future<void> _downloadOfflineTiles(
    BuildContext context,
    List waypoints,
  ) async {
    final cache = _tileCache;
    if (cache == null) return;
    final points = <LatLng>[
      for (final w in waypoints) w.latLng as LatLng,
    ];
    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add waypoints first to define a route.')),
      );
      return;
    }
    final bounds = _padBounds(LatLngBounds.fromPoints(points), 0.05);
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });
    final fetched = await cache.prefetchBbox(
      bbox: bounds,
      zooms: const [10, 11, 12, 13, 14],
      onProgress: (done, total) {
        if (mounted) {
          setState(() => _downloadProgress = total == 0 ? 0 : done / total);
        }
      },
    );
    if (!mounted) return;
    setState(() => _downloading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cached $fetched new tiles for offline.')),
    );
  }

  LatLngBounds _padBounds(LatLngBounds b, double pad) {
    return LatLngBounds(
      LatLng(b.south - pad, b.west - pad),
      LatLng(b.north + pad, b.east + pad),
    );
  }

  Future<void> _onLongPress(
    BuildContext context,
    LatLng point,
    int currentCount,
  ) async {
    final controller = TextEditingController(text: 'Stop ${currentCount + 1}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add waypoint'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final repo = await ref.read(waypointsRepositoryProvider.future);
      await repo.add(
        tripId: widget.tripId,
        name: name,
        lat: point.latitude,
        lng: point.longitude,
        position: currentCount,
      );
      ref.invalidate(tripWaypointsProvider(widget.tripId));
      ref.invalidate(tripRouteProvider(widget.tripId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add waypoint: $e')),
        );
      }
    }
  }

  Color _colorForUser(String userId, AsyncValue tripAsync) {
    return tripAsync.maybeWhen(
      data: (trip) {
        final m = (trip.members as List).cast<dynamic>().firstWhere(
              (e) => e.userId == userId,
              orElse: () => null,
            );
        if (m == null) return Colors.blue;
        return _hex(m.color as String);
      },
      orElse: () => Colors.blue,
    );
  }

  static Color _hex(String value) {
    final hex = value.replaceAll('#', '');
    final v = int.parse(hex, radix: 16);
    return Color(0xFF000000 | v);
  }
}

class _StraightLine extends StatelessWidget {
  const _StraightLine(this.waypoints);
  final List waypoints;

  @override
  Widget build(BuildContext context) {
    if (waypoints.length < 2) return const SizedBox.shrink();
    return PolylineLayer(
      polylines: [
        Polyline(
          points: [for (final w in waypoints) w.latLng as LatLng],
          color: Colors.blueAccent.withOpacity(0.5),
          strokeWidth: 4,
          pattern: const StrokePattern.dashed(segments: [10, 6]),
        ),
      ],
    );
  }
}

class _WaypointPin extends StatelessWidget {
  const _WaypointPin({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.deepOrange,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '$index',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MemberDot extends StatelessWidget {
  const _MemberDot({
    required this.color,
    this.battery,
    this.heading,
  });

  final Color color;
  final int? battery;
  final double? heading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Heading arrow rotates around the marker center.
          if (heading != null)
            Transform.rotate(
              angle: heading! * math.pi / 180,
              child: CustomPaint(
                size: const Size(56, 56),
                painter: _HeadingArrowPainter(color: color),
              ),
            ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(blurRadius: 4, color: Colors.black26),
              ],
            ),
          ),
          if (battery != null)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$battery%',
                  style: const TextStyle(color: Colors.white, fontSize: 9),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeadingArrowPainter extends CustomPainter {
  _HeadingArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.85)
      ..style = PaintingStyle.fill;
    final c = Offset(size.width / 2, size.height / 2);
    final path = Path()
      ..moveTo(c.dx, c.dy - 26)
      ..lineTo(c.dx - 8, c.dy - 12)
      ..lineTo(c.dx + 8, c.dy - 12)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeadingArrowPainter old) =>
      old.color != color;
}
