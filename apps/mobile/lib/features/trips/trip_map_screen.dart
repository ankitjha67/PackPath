import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
import '../map/live_trip_controller.dart';
import '../map/map_providers.dart';
import '../map/tile_cache.dart';
import '../safety/crash_detector.dart';
import '../safety/safety_alert_sheet.dart';
import '../safety/sos_button.dart';
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
  final CrashDetector _crashDetector = CrashDetector();
  TileCache? _tileCache;
  CachedMapboxTileProvider? _tileProvider;
  bool _follow = true;
  String? _lastFollowedUser;
  double _downloadProgress = 0;
  bool _downloading = false;
  bool _ghost = false;
  String? _shownSafetyAlertId;

  @override
  void initState() {
    super.initState();
    _bootCache();
    _crashDetector.start((g) {
      // Auto-fire after a crash spike. The server treats it as a
      // warning-severity event and fans it out as a `safety` frame so
      // every member's app pops the alert sheet.
      ref.read(liveTripProvider(widget.tripId).notifier).sendSafety(
        kind: 'crash',
        details: {'g': g},
      );
    });
  }

  @override
  void dispose() {
    _crashDetector.stop();
    super.dispose();
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
    final mapProvider = ref.watch(mapProviderControllerProvider);

    final waypoints = waypointsAsync.maybeWhen(
      data: (w) => w,
      orElse: () => const [],
    );

    // Auto-follow my last published location if follow mode is on.
    _maybeFollow(live);

    // Pop a full-screen safety alert when one arrives. We dedupe on
    // the alert id so the same frame doesn't push twice.
    final activeAlert = live.activeSafetyAlert;
    if (activeAlert != null && activeAlert['alert_id'] != _shownSafetyAlertId) {
      _shownSafetyAlertId = activeAlert['alert_id'] as String?;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => SafetyAlertSheet(
              tripId: widget.tripId,
              alert: activeAlert,
            ),
          ),
        );
      });
    }

    final tokens = Theme.of(context).extension<KineticPathTokens>()!;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: tokens.glassmorphismDecoration(
                borderRadius: BorderRadius.zero,
              ),
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: tripAsync.maybeWhen(
                  data: (t) => Text(t.name),
                  orElse: () => const Text('Trip'),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Chat',
                    icon: const Icon(Icons.chat_bubble_outline),
                    onPressed: () =>
                        context.push('/trips/${widget.tripId}/chat'),
                  ),
                  IconButton(
                    tooltip: 'Invite',
                    icon: const Icon(Icons.qr_code_2),
                    onPressed: () =>
                        context.push('/trips/${widget.tripId}/share'),
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
                      } else if (value == 'mapstyle') {
                        await _pickMapProvider(context);
                      } else if (value == 'recap') {
                        context.push('/trips/${widget.tripId}/recap');
                      } else if (value == 'expenses') {
                        context.push('/trips/${widget.tripId}/expenses');
                      } else if (value == 'ghost') {
                        await _toggleGhost(context);
                      } else if (value == 'privacy') {
                        context.push('/privacy');
                      } else if (value == 'plans') {
                        context.push('/plans');
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'offline',
                        child: ListTile(
                          leading: Icon(Icons.cloud_download_outlined),
                          title: Text('Download offline tiles'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'recenter',
                        child: ListTile(
                          leading: Icon(Icons.center_focus_strong),
                          title: Text('Frame everyone'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'mapstyle',
                        child: ListTile(
                          leading: Icon(Icons.layers_outlined),
                          title: Text('Map style'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'recap',
                        child: ListTile(
                          leading: Icon(Icons.insights_outlined),
                          title: Text('Trip recap'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'expenses',
                        child: ListTile(
                          leading: Icon(Icons.currency_rupee),
                          title: Text('Expenses'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'ghost',
                        child: ListTile(
                          leading: Icon(
                            _ghost
                                ? Icons.visibility_off
                                : Icons.visibility_outlined,
                          ),
                          title:
                              Text(_ghost ? 'Leave ghost mode' : 'Ghost mode'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'privacy',
                        child: ListTile(
                          leading: Icon(Icons.shield_outlined),
                          title: Text('Privacy'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'plans',
                        child: ListTile(
                          leading: Icon(Icons.workspace_premium_outlined),
                          title: Text('Plans'),
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
                          color: live.connected
                              ? Colors.greenAccent
                              : Colors.redAccent,
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
            ),
          ),
        ),
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
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && _follow) {
                  setState(() => _follow = false);
                }
              },
            ),
            children: [
              TileLayer(
                // The cached provider only handles Mapbox URLs; for any
                // other provider we let flutter_map's network provider use
                // the template directly. Both paths still go through the
                // backend for routing — only the tiles change.
                urlTemplate: mapProvider.tileUrlTemplate,
                userAgentPackageName: 'app.packpath.mobile',
                maxZoom: 19,
                tileProvider: mapProvider == MapProvider.mapbox
                    ? (_tileProvider ?? NetworkTileProvider())
                    : NetworkTileProvider(),
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
                            color: Theme.of(context).colorScheme.primary,
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
              RichAttributionWidget(
                attributions: [TextSourceAttribution(mapProvider.attribution)],
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
                  backgroundColor: _follow ? Colors.blue : Colors.white,
                  foregroundColor: _follow ? Colors.white : Colors.black87,
                  onPressed: () {
                    setState(() => _follow = true);
                    _maybeFollow(live, force: true);
                  },
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 12),
                PttButton(tripId: widget.tripId),
                const SizedBox(height: 12),
                SosButton(tripId: widget.tripId),
              ],
            ),
          ),
          if (_ghost)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: IgnorePointer(
                child: Material(
                  color: Colors.deepPurple.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.visibility_off,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ghost mode — your location is hidden',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_downloading)
            Positioned(
              top: 56,
              left: 16,
              right: 16,
              child: ClipRRect(
                borderRadius: AppRadii.lg,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: tokens.glassmorphismDecoration(
                      borderRadius: AppRadii.lg,
                    ),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'CACHING TILES FOR OFFLINE',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ClipRRect(
                          borderRadius: AppRadii.xs,
                          child: LinearProgressIndicator(
                            value: _downloadProgress,
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: ClipRRect(
              borderRadius: AppRadii.lg,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  decoration: tokens.glassmorphismDecoration(
                    borderRadius: AppRadii.lg,
                  ),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: tripAsync.when(
                    loading: () => const SizedBox(
                      height: 36,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Text('Error: $e'),
                    data: (trip) {
                      final textTheme = Theme.of(context).textTheme;
                      return Row(
                        children: [
                          const Icon(Icons.group, size: 18),
                          const SizedBox(width: AppSpacing.sm),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'PACK',
                                style: textTheme.labelSmall,
                              ),
                              Text(
                                '${trip.members.length}',
                                style: textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(width: AppSpacing.base),
                          const Icon(Icons.flag_outlined, size: 18),
                          const SizedBox(width: AppSpacing.sm),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'STOPS',
                                style: textTheme.labelSmall,
                              ),
                              Text(
                                '${waypoints.length}',
                                style: textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const Spacer(),
                          if (_tileCache != null)
                            Text(
                              '${_tileCache!.tileCount} tiles',
                              style: textTheme.bodySmall,
                            ),
                          const SizedBox(width: AppSpacing.md),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'CODE',
                                style: textTheme.labelSmall,
                              ),
                              Text(
                                trip.joinCode,
                                style: textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ],
                      );
                    },
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
    final pick =
        _lastFollowedUser != null && live.members.containsKey(_lastFollowedUser)
            ? live.members[_lastFollowedUser!]!
            : live.members.values.first;
    _lastFollowedUser = pick.userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        _mapController.move(pick.position, _mapController.camera.zoom);
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
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
    );
    setState(() => _follow = false);
  }

  Future<void> _downloadOfflineTiles(
    BuildContext context,
    List waypoints,
  ) async {
    final cache = _tileCache;
    if (cache == null) return;
    final points = <LatLng>[for (final w in waypoints) w.latLng as LatLng];
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

  Future<void> _pickMapProvider(BuildContext context) async {
    final current = ref.read(mapProviderControllerProvider);
    final serverAsync = ref.read(serverProvidersProvider);
    final configured = serverAsync.maybeWhen(
      data: (s) => s.configured,
      orElse: () => <String>{'mapbox', 'osrm'},
    );
    final defaultProvider = serverAsync.maybeWhen(
      data: (s) => s.defaultProvider,
      orElse: () => 'mapbox',
    );
    final picked = await showModalBottomSheet<MapProvider>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Map style',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Tiles render from the provider you pick. Routing always '
                'goes through the backend, which is currently using '
                '"$defaultProvider".',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final p in MapProvider.values)
              ListTile(
                leading: Icon(
                  current == p
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(p.displayName),
                subtitle: Text(
                  configured.contains(p.id)
                      ? 'Configured on server'
                      : 'Not configured on server',
                ),
                onTap: () => Navigator.of(ctx).pop(p),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await ref.read(mapProviderControllerProvider.notifier).set(picked);
    }
  }

  Future<void> _toggleGhost(BuildContext context) async {
    final next = !_ghost;
    try {
      final repo = await ref.read(tripsRepositoryProvider.future);
      await repo.setGhostMode(tripId: widget.tripId, on: next);
      if (!mounted) return;
      setState(() => _ghost = next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'Ghost mode on — your location is hidden from the pack'
                : 'Ghost mode off — sharing again',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not toggle ghost mode: $e')),
      );
    }
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add waypoint: $e')));
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
          color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          strokeWidth: 5,
          pattern: StrokePattern.dashed(segments: const [10.0, 6.0]),
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, 4),
            blurRadius: 8,
            color: Colors.black.withOpacity(0.2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$index',
        style: TextStyle(
          color: scheme.onPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _MemberDot extends StatelessWidget {
  const _MemberDot({required this.color, this.battery, this.heading});

  final Color color;
  final int? battery;
  final double? heading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          // Battery arc drawn around the avatar (Safety Orange).
          if (battery != null)
            CustomPaint(
              size: const Size(54, 54),
              painter: _BatteryArcPainter(
                battery: battery!,
                color: scheme.primary,
                trackColor: scheme.primary.withOpacity(0.2),
              ),
            ),
          // 48dp avatar with 3dp colored ring.
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
              boxShadow: [
                BoxShadow(
                  offset: const Offset(0, 4),
                  blurRadius: 12,
                  color: Colors.black.withOpacity(0.15),
                ),
              ],
            ),
            child: Icon(
              Icons.person,
              color: color,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _BatteryArcPainter extends CustomPainter {
  _BatteryArcPainter({
    required this.battery,
    required this.color,
    required this.trackColor,
  });

  final int battery;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width,
      height: size.height,
    );
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    final progress = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final sweep = (battery.clamp(0, 100) / 100) * 2 * math.pi;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, progress);
  }

  @override
  bool shouldRepaint(covariant _BatteryArcPainter old) =>
      old.battery != battery ||
      old.color != color ||
      old.trackColor != trackColor;
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
    final path = ui.Path()
      ..moveTo(c.dx, c.dy - 26)
      ..lineTo(c.dx - 8, c.dy - 12)
      ..lineTo(c.dx + 8, c.dy - 12)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeadingArrowPainter old) => old.color != color;
}
