import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
import '../../shared/models/member_location.dart';
import '../../shared/models/message.dart';
import '../../shared/models/trip.dart';
import '../chat/chat_repository.dart';
import '../contacts/member_profile_screen.dart';
import '../../shared/models/waypoint.dart';
import '../../shared/widgets/user_avatar.dart';
import '../hazards/hazard_banner.dart';
import '../hazards/hazard_layer.dart';
import '../hazards/hazard_model.dart';
import '../hazards/hazards_repository.dart';
import '../map/live_trip_controller.dart';
import '../map/map_providers.dart';
import '../map/tile_cache.dart';
import '../profile/me_repository.dart';
import '../safety/crash_detector.dart';
import '../safety/safety_alert_sheet.dart';
import '../safety/sos_button.dart';
import '../voice/ptt_button.dart';
import 'checkpoints_sheet.dart';
import 'eta_panel.dart';
import 'pack_cohesion.dart';
import 'ready_check_panel.dart';
import 'trip_gallery_screen.dart';
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
  // Current camera zoom, tracked so member markers re-cluster as you zoom.
  double _zoom = 12;
  bool _downloading = false;
  bool _ghost = false;
  // Whether we've seeded _ghost from the server's per-member ghost_mode yet.
  // Prevents the local toggle from resetting to false on every screen entry.
  bool _ghostInitialized = false;
  String? _shownSafetyAlertId;
  String? _shownNudgeId;

  @override
  void initState() {
    super.initState();
    _bootCache();
    _crashDetector.start((g) {
      // A g-force spike is often a false alarm (phone dropped on a seat). Show
      // a local cancel-countdown BEFORE alerting the whole group.
      if (!mounted || _crashPromptOpen) return;
      _promptCrash(g);
    });
  }

  bool _crashPromptOpen = false;

  Future<void> _promptCrash(double g) async {
    _crashPromptOpen = true;
    final send = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CrashCountdownDialog(seconds: 10),
    );
    _crashPromptOpen = false;
    if (send == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final sent = await ref
          .read(liveTripProvider(widget.tripId).notifier)
          .sendSafety(kind: 'crash', details: {'g': g});
      if (!mounted) return;
      if (!sent) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Offline — crash alert queued, will send when reconnected.',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _crashDetector.stop();
    _mapController.dispose();
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

    final List<WaypointDto> waypoints = waypointsAsync.maybeWhen(
      data: (w) => w,
      orElse: () => const <WaypointDto>[],
    );

    final hazardsAsync = ref.watch(tripHazardsProvider(widget.tripId));
    final List<HazardDto> hazards = hazardsAsync.maybeWhen(
      data: (h) => h,
      orElse: () => const <HazardDto>[],
    );

    // The pack marshall (trip owner) can broadcast pinned announcements.
    final myId = ref.watch(meProvider).valueOrNull?.id;
    final isMarshall = tripAsync.valueOrNull?.ownerId == myId && myId != null;

    // How tightly the pack is travelling together (for the straggler HUD).
    final cohesion = computeCohesion(live.members);

    // Pack members whose phones are about to die (lost tracking is a safety
    // risk). Purely from the battery carried on each live location frame.
    final lowBatteryCount = live.members.values
        .where((m) => m.battery != null && m.battery! <= _lowBatteryThreshold)
        .length;

    // The active marshall broadcast (newest of REST + live); if it carries a
    // location it's a rally point we pin on the map.
    final latestAnnounce = pickLatestAnnouncement(
      ref.watch(latestAnnouncementProvider(widget.tripId)).valueOrNull,
      live.latestAnnouncement,
    );
    final LatLng? rallyPoint = rallyPointOf(latestAnnounce);

    // Auto-follow my last published location if follow mode is on.
    _maybeFollow(live);

    // Seed the ghost-mode toggle from the server's per-member state (once),
    // so re-entering the map reflects reality instead of defaulting to "off".
    if (!_ghostInitialized) {
      final myId = ref.watch(meProvider).valueOrNull?.id;
      final trip = tripAsync.valueOrNull;
      if (myId != null && trip != null) {
        bool? serverGhost;
        for (final m in trip.members) {
          if (m.userId == myId) {
            serverGhost = m.ghostMode;
            break;
          }
        }
        if (serverGhost != null) {
          _ghostInitialized = true;
          final g = serverGhost;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _ghost != g) setState(() => _ghost = g);
          });
        }
      }
    }

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

    // A nudge aimed at me — buzz + show a prominent catch-up prompt once.
    final nudge = live.lastNudge;
    if (nudge != null && nudge['nudge_id'] != _shownNudgeId) {
      _shownNudgeId = nudge['nudge_id'] as String?;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 6),
              backgroundColor: const Color(0xFF7C3AED),
              content: Row(
                children: [
                  const Icon(Icons.bolt, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${nudge['from_name']} is asking you to catch up',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
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
                  if (isMarshall)
                    PopupMenuButton<String>(
                      tooltip: 'Marshall tools',
                      icon: const Icon(Icons.campaign_outlined),
                      onSelected: (v) async {
                        if (v == 'broadcast') {
                          await _composeAnnouncement(context);
                        } else if (v == 'regroup') {
                          await _regroupHere(context);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'broadcast',
                          child: ListTile(
                            leading: Icon(Icons.campaign_outlined),
                            title: Text('Broadcast message'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'regroup',
                          child: ListTile(
                            leading: Icon(Icons.group_work_outlined),
                            title: Text('Regroup here (rally)'),
                          ),
                        ),
                      ],
                    ),
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
                      useSafeArea: true,
                      builder: (_) => EtaPanel(tripId: widget.tripId),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Trip settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () =>
                        context.push('/trips/${widget.tripId}/settings'),
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
                      } else if (value == 'gallery') {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                TripGalleryScreen(tripId: widget.tripId),
                          ),
                        );
                      } else if (value == 'checkpoints') {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) =>
                              CheckpointsSheet(tripId: widget.tripId),
                        );
                      } else if (value == 'expenses') {
                        context.push('/trips/${widget.tripId}/expenses');
                      } else if (value == 'ghost') {
                        await _toggleGhost(context);
                      } else if (value == 'ready') {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) =>
                              ReadyCheckPanel(tripId: widget.tripId),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'ready',
                        child: ListTile(
                          leading: Icon(Icons.how_to_reg_outlined),
                          title: Text('Ready check'),
                        ),
                      ),
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
                        value: 'gallery',
                        child: ListTile(
                          leading: Icon(Icons.photo_library_outlined),
                          title: Text('Trip gallery'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'checkpoints',
                        child: ListTile(
                          leading: Icon(Icons.flag_circle_outlined),
                          title: Text('Checkpoints'),
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
                              ? Theme.of(context).colorScheme.tertiary
                              : Theme.of(context).colorScheme.error,
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
                                color: Theme.of(context).colorScheme.secondary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${live.queuedFrames}',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSecondary,
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
              onPositionChanged: (camera, hasGesture) {
                final zoomChanged = (camera.zoom - _zoom).abs() > 0.01;
                if ((hasGesture && _follow) || zoomChanged) {
                  setState(() {
                    if (hasGesture && _follow) _follow = false;
                    _zoom = camera.zoom;
                  });
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
              // Render order (low z → high z):
              //   1. member markers
              //   2. hazard pins (above members, below waypoints)
              //   3. waypoint pins (on top — user-placed, most important)
              MarkerLayer(
                markers: _buildMemberMarkers(
                  live,
                  tripAsync,
                  cohesion.stragglerIds,
                  live.memberStatus,
                ),
              ),
              HazardLayer(hazards: hazards),
              MarkerLayer(
                markers: [
                  for (var i = 0; i < waypoints.length; i++)
                    Marker(
                      point: waypoints[i].latLng,
                      width: 36,
                      height: 36,
                      child: _WaypointPin(index: i + 1),
                    ),
                ],
              ),
              if (rallyPoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: rallyPoint,
                      width: 44,
                      height: 52,
                      alignment: Alignment.topCenter,
                      child: const _RallyPin(),
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
                Builder(builder: (_) {
                  final meta =
                      statusMeta(myId == null ? null : live.memberStatus[myId]);
                  return FloatingActionButton.small(
                    heroTag: 'status',
                    backgroundColor: meta?.color ?? Colors.white,
                    foregroundColor: meta == null ? Colors.black87 : Colors.white,
                    tooltip: meta?.label ?? 'Set status',
                    onPressed: () => _pickStatus(context, myId, live),
                    child: Icon(meta?.icon ?? Icons.flag_outlined),
                  );
                }),
                const SizedBox(height: 12),
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
                  color: Colors.deepPurple.withValues(alpha: 0.85),
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
          Positioned(
            top: kToolbarHeight +
                MediaQuery.of(context).padding.top +
                AppSpacing.sm,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cohesion.memberCount >= 2)
                  _PackStatusChip(
                    cohesion: cohesion,
                    onTap: () =>
                        _showStragglerSheet(context, cohesion, tripAsync),
                  ),
                if (lowBatteryCount > 0)
                  _LowBatteryChip(
                    count: lowBatteryCount,
                    onTap: () => _showBatterySheet(context, tripAsync),
                  ),
                AnnouncementBanner(tripId: widget.tripId),
                HazardBanner(tripId: widget.tripId),
              ],
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
      if (mounted) {
        _mapController.move(pick.position, _mapController.camera.zoom);
      }
    });
  }

  void _frameAll(LiveTripState live, List<WaypointDto> waypoints) {
    final points = <LatLng>[
      ...live.members.values.map((m) => m.position),
      for (final w in waypoints) w.latLng,
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
    List<WaypointDto> waypoints,
  ) async {
    final cache = _tileCache;
    if (cache == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final points = <LatLng>[for (final w in waypoints) w.latLng];
    if (points.isEmpty) {
      messenger.showSnackBar(
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
    messenger.showSnackBar(
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
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        // The provider list is taller than the sheet's default max height on
        // shorter screens, so make it scrollable instead of overflowing.
        child: SingleChildScrollView(
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
      ),
    );
    if (picked != null) {
      await ref.read(mapProviderControllerProvider.notifier).set(picked);
    }
  }

  Future<void> _toggleGhost(BuildContext context) async {
    final next = !_ghost;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(tripsRepositoryProvider.future);
      await repo.setGhostMode(tripId: widget.tripId, on: next);
      if (!mounted) return;
      setState(() => _ghost = next);
      // Refresh the member list so the server's ghost_mode stays in sync (and
      // other derived UI sees the change).
      ref.invalidate(tripDetailProvider(widget.tripId));
      messenger.showSnackBar(
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
      messenger.showSnackBar(
        SnackBar(content: Text('Could not toggle ghost mode: $e')),
      );
    }
  }

  /// Marshall-only: compose and broadcast a pinned announcement to the pack.
  Future<void> _composeAnnouncement(BuildContext context) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Broadcast to pack'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 2000,
          maxLines: 4,
          minLines: 1,
          decoration: const InputDecoration(
            hintText: 'e.g. Fuel stop in 10 min — regroup at the dhaba',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            icon: const Icon(Icons.campaign),
            label: const Text('Broadcast'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      await repo.sendAnnouncement(widget.tripId, text);
      if (!mounted) return;
      ref.invalidate(latestAnnouncementProvider(widget.tripId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Broadcast sent to the pack')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not broadcast: $e')),
      );
    }
  }

  /// Marshall-only: drop a rally point at the marshall's current location and
  /// pin a "Regroup here" broadcast for the whole pack.
  Future<void> _regroupHere(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: 'Regroup here');
        return AlertDialog(
          title: const Text('Regroup the pack'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Drops a rally pin at your current location and tells '
                'everyone to regroup there.',
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              icon: const Icon(Icons.group_work),
              label: const Text('Rally'),
            ),
          ],
        );
      },
    );
    if (label == null || !mounted) return;
    try {
      final pos = await Geolocator.getCurrentPosition();
      final repo = await ref.read(chatRepositoryProvider.future);
      await repo.sendAnnouncement(
        widget.tripId,
        label,
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (!mounted) return;
      ref.invalidate(latestAnnouncementProvider(widget.tripId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Rally point sent to the pack')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not set rally point: $e')),
      );
    }
  }

  /// Pick my live status for the pack.
  Future<void> _pickStatus(
    BuildContext context,
    String? myId,
    LiveTripState live,
  ) async {
    final current = myId == null ? null : live.memberStatus[myId];
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in const ['moving', 'stopped', 'break', 'fuel'])
              ListTile(
                leading: Icon(
                  statusMeta(s)?.icon ?? Icons.navigation,
                  color: statusMeta(s)?.color,
                ),
                title: Text(statusMeta(s)?.label ?? 'On the move'),
                trailing: (current ?? 'moving') == s
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      await repo.setStatus(widget.tripId, picked);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not set status: $e')),
      );
    }
  }

  /// Send a "catch up" nudge to one member.
  Future<void> _nudge(String toUserId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      await repo.sendNudge(widget.tripId, toUserId);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Nudge sent')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not send nudge: $e')),
      );
    }
  }

  /// Bottom sheet listing members low on battery, lowest first.
  void _showBatterySheet(
    BuildContext context,
    AsyncValue<TripDto> tripAsync,
  ) {
    final live = ref.read(liveTripProvider(widget.tripId));
    final low = [
      for (final m in live.members.values)
        if (m.battery != null && m.battery! <= _lowBatteryThreshold) m,
    ]..sort((a, b) => a.battery!.compareTo(b.battery!));

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        final textTheme = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.battery_alert, color: Color(0xFFEF4444)),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Low battery', style: textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final m in low)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: UserAvatar(
                            name: _nameForUser(m.userId, tripAsync),
                            avatarUrl: _avatarForUser(m.userId, tripAsync),
                            radius: 18,
                          ),
                          title: Text(_nameForUser(m.userId, tripAsync)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                m.battery! <= 10
                                    ? Icons.battery_0_bar
                                    : Icons.battery_2_bar,
                                size: 18,
                                color: const Color(0xFFEF4444),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${m.battery}%',
                                style: textTheme.labelLarge?.copyWith(
                                  color: const Color(0xFFEF4444),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _mapController.move(
                                m.position, _mapController.camera.zoom);
                            setState(() => _follow = false);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Bottom sheet listing every member by distance from the pack centre,
  /// stragglers first. Tapping a member recentres the map on them.
  void _showStragglerSheet(
    BuildContext context,
    PackCohesion cohesion,
    AsyncValue<TripDto> tripAsync,
  ) {
    final live = ref.read(liveTripProvider(widget.tripId));
    final myId = ref.read(meProvider).valueOrNull?.id;
    final ordered = [
      for (final m in live.members.values)
        (
          m.userId,
          cohesion.centre == null
              ? 0.0
              : const Distance().as(
                  LengthUnit.Meter, cohesion.centre!, m.position),
        ),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final stragglerIds = cohesion.stragglerIds;

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      cohesion.isTogether
                          ? Icons.groups
                          : Icons.directions_run,
                      color: cohesion.isTogether
                          ? const Color(0xFF2ECC71)
                          : const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      cohesion.isTogether
                          ? 'Pack together'
                          : '${cohesion.stragglers.length} trailing',
                      style: textTheme.titleLarge,
                    ),
                    const Spacer(),
                    Text(
                      'spread ${formatMetres(cohesion.spreadMetres)}',
                      style: textTheme.labelLarge
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final row in ordered)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: UserAvatar(
                            name: _nameForUser(row.$1, tripAsync),
                            avatarUrl: _avatarForUser(row.$1, tripAsync),
                            radius: 18,
                          ),
                          title: Text(_nameForUser(row.$1, tripAsync)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatMetres(row.$2),
                                style: textTheme.labelLarge?.copyWith(
                                  color: stragglerIds.contains(row.$1)
                                      ? const Color(0xFFF59E0B)
                                      : scheme.onSurfaceVariant,
                                  fontWeight: stragglerIds.contains(row.$1)
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                              if (row.$1 != myId)
                                IconButton(
                                  tooltip: 'Nudge to catch up',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.bolt,
                                      color: Color(0xFF7C3AED)),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _nudge(row.$1);
                                  },
                                ),
                            ],
                          ),
                          onTap: () {
                            final pos = live.members[row.$1]?.position;
                            Navigator.pop(ctx);
                            if (pos != null) {
                              _mapController.move(pos, _mapController.camera.zoom);
                              setState(() => _follow = false);
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add waypoint: $e')));
      }
    }
  }

  /// Build member markers, grouping nearby ones into cluster badges so a big
  /// pack stays readable. Grid cell size tracks zoom (≈ a marker's on-screen
  /// footprint), so clusters split apart as you zoom in. Tapping a cluster
  /// zooms toward it to expand.
  List<Marker> _buildMemberMarkers(
    LiveTripState live,
    AsyncValue<TripDto> tripAsync,
    Set<String> stragglerIds,
    Map<String, String> statuses,
  ) {
    final members = live.members.values.toList();
    if (members.isEmpty) return const [];
    // ~ one marker's width (60px) in degrees of longitude at this zoom.
    final cell = 95.0 / math.pow(2, _zoom);
    final cells = <String, List<MemberLocation>>{};
    for (final m in members) {
      final gx = (m.position.longitude / cell).floor();
      final gy = (m.position.latitude / cell).floor();
      cells.putIfAbsent('$gx:$gy', () => <MemberLocation>[]).add(m);
    }
    final markers = <Marker>[];
    for (final group in cells.values) {
      if (group.length == 1) {
        final m = group.first;
        markers.add(
          Marker(
            point: m.position,
            width: 56,
            height: 56,
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MemberProfileScreen(
                    tripId: widget.tripId,
                    userId: m.userId,
                  ),
                ),
              ),
              child: _MemberDot(
                color: _colorForUser(m.userId, tripAsync),
                avatarUrl: _avatarForUser(m.userId, tripAsync),
                name: _nameForUser(m.userId, tripAsync),
                battery: m.battery,
                heading: m.heading,
                isStraggler: stragglerIds.contains(m.userId),
                status: statuses[m.userId],
              ),
            ),
          ),
        );
      } else {
        var lat = 0.0;
        var lng = 0.0;
        for (final m in group) {
          lat += m.position.latitude;
          lng += m.position.longitude;
        }
        final centroid = LatLng(lat / group.length, lng / group.length);
        // Up to 3 member faces to preview who is in the cluster.
        final faces = group
            .take(3)
            .map((m) => (
                  _nameForUser(m.userId, tripAsync),
                  _avatarForUser(m.userId, tripAsync),
                ))
            .toList();
        markers.add(
          Marker(
            point: centroid,
            width: 58,
            height: 58,
            child: _ClusterMarker(
              count: group.length,
              faces: faces,
              onTap: () {
                final z = (_mapController.camera.zoom + 2).clamp(1.0, 18.0);
                _mapController.move(centroid, z);
                setState(() {
                  _zoom = z;
                  _follow = false;
                });
              },
            ),
          ),
        );
      }
    }
    return markers;
  }

  Color _colorForUser(String userId, AsyncValue<TripDto> tripAsync) {
    return tripAsync.maybeWhen(
      data: (trip) {
        for (final m in trip.members) {
          if (m.userId == userId) return _hex(m.color);
        }
        return Colors.blue;
      },
      orElse: () => Colors.blue,
    );
  }

  TripMemberDto? _memberFor(String userId, AsyncValue<TripDto> tripAsync) {
    return tripAsync.maybeWhen(
      data: (trip) {
        for (final m in trip.members) {
          if (m.userId == userId) return m;
        }
        return null;
      },
      orElse: () => null,
    );
  }

  String? _avatarForUser(String userId, AsyncValue<TripDto> tripAsync) =>
      _memberFor(userId, tripAsync)?.avatarUrl;

  String _nameForUser(String userId, AsyncValue<TripDto> tripAsync) =>
      _memberFor(userId, tripAsync)?.label ??
      '${userId.substring(0, userId.length.clamp(0, 6))}…';

  static Color _hex(String value) {
    final hex = value.replaceAll('#', '');
    final v = int.parse(hex, radix: 16);
    return Color(0xFF000000 | v);
  }
}

class _StraightLine extends StatelessWidget {
  const _StraightLine(this.waypoints);
  final List<WaypointDto> waypoints;

  @override
  Widget build(BuildContext context) {
    if (waypoints.length < 2) return const SizedBox.shrink();
    return PolylineLayer(
      polylines: [
        Polyline(
          points: [for (final w in waypoints) w.latLng],
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
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
            color: Colors.black.withValues(alpha: 0.2),
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
  const _MemberDot({
    required this.color,
    required this.name,
    this.avatarUrl,
    this.battery,
    this.heading,
    this.isStraggler = false,
    this.status,
  });

  final Color color;
  final String name;
  final String? avatarUrl;
  final int? battery;
  final double? heading;

  /// Trailing far behind the pack — draws an amber alert ring.
  final bool isStraggler;

  /// Live member status ('stopped'/'break'/'fuel'); null = on the move.
  final String? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Amber alert ring behind everything when this member is trailing.
          if (isStraggler)
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF59E0B), width: 3),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10,
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
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
                trackColor: scheme.primary.withValues(alpha: 0.2),
              ),
            ),
          // 48dp avatar with 3dp colored ring.
          Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
              boxShadow: [
                BoxShadow(
                  offset: const Offset(0, 4),
                  blurRadius: 12,
                  color: Colors.black.withValues(alpha: 0.15),
                ),
              ],
            ),
            // The member's avatar fills the ring, so a crowded trip stays
            // readable at a glance (falls back to colored initials offline).
            child: UserAvatar(name: name, avatarUrl: avatarUrl, radius: 18),
          ),
          // Status badge (stopped / break / fuel) in the bottom-right corner.
          if (statusMeta(status) != null)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: statusMeta(status)!.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Icon(
                  statusMeta(status)!.icon,
                  size: 11,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A badge standing in for several nearby members: a few fanned mini-avatars
/// with a member-count badge. Tap to zoom in and split the cluster apart.
class _ClusterMarker extends StatelessWidget {
  const _ClusterMarker({
    required this.count,
    required this.faces,
    required this.onTap,
  });

  final int count;
  final List<(String, String?)> faces;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = count > 99 ? '99+' : '$count';
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < faces.length; i++)
                  Transform.translate(
                    offset: Offset((i - (faces.length - 1) / 2) * 17, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.surface, width: 2),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 6,
                            color: Colors.black.withValues(alpha: 0.25),
                          ),
                        ],
                      ),
                      child: UserAvatar(
                        name: faces[i].$1,
                        avatarUrl: faces[i].$2,
                        radius: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.onPrimary, width: 1.5),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
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
      ..color = color.withValues(alpha: 0.85)
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

/// Modal shown when the crash detector fires. Counts down and auto-confirms
/// (pops `true`) if the user doesn't cancel — so a real crash still alerts the
/// group even if the user is incapacitated, but a false alarm can be dismissed.
class _CrashCountdownDialog extends StatefulWidget {
  const _CrashCountdownDialog({required this.seconds});

  final int seconds;

  @override
  State<_CrashCountdownDialog> createState() => _CrashCountdownDialogState();
}

class _CrashCountdownDialogState extends State<_CrashCountdownDialog> {
  late int _remaining = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 1) {
        t.cancel();
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Possible crash detected'),
      content: Text(
        'Alerting your trip group in $_remaining s. Cancel if you\'re OK.',
      ),
      actions: [
        TextButton(
          onPressed: () {
            _timer?.cancel();
            Navigator.of(context).pop(false);
          },
          child: const Text("I'm OK"),
        ),
        FilledButton(
          onPressed: () {
            _timer?.cancel();
            Navigator.of(context).pop(true);
          },
          child: const Text('Send alert now'),
        ),
      ],
    );
  }
}

/// Pick the newer of the REST-fetched and live-socket announcements (ISO
/// timestamps sort correctly). Shared by the banner and the rally marker.
MessageDto? pickLatestAnnouncement(
  MessageDto? fetched,
  Map<String, dynamic>? liveMap,
) {
  MessageDto? live;
  if (liveMap != null) {
    try {
      live = MessageDto.fromJson(liveMap);
    } catch (_) {
      live = null;
    }
  }
  if (fetched != null && live != null) {
    return live.sentAt.isAfter(fetched.sentAt) ? live : fetched;
  }
  return live ?? fetched;
}

/// Parse a rally LatLng from an announcement's "lat,lng" location attachment,
/// or null when the announcement isn't a rally.
LatLng? rallyPointOf(MessageDto? m) {
  if (m == null || m.attachmentKind != 'location' || m.attachmentUrl == null) {
    return null;
  }
  final parts = m.attachmentUrl!.split(',');
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0]);
  final lng = double.tryParse(parts[1]);
  if (lat == null || lng == null) return null;
  return LatLng(lat, lng);
}

/// Battery percentage at or below which a member is flagged as "low".
const int _lowBatteryThreshold = 20;

/// Visual metadata for a member status, or null for the default "on the move".
({IconData icon, String label, Color color})? statusMeta(String? status) {
  switch (status) {
    case 'stopped':
      return (
        icon: Icons.pan_tool,
        label: 'Stopped',
        color: const Color(0xFFEF4444),
      );
    case 'break':
      return (
        icon: Icons.coffee,
        label: 'On a break',
        color: const Color(0xFFF59E0B),
      );
    case 'fuel':
      return (
        icon: Icons.local_gas_station,
        label: 'Fuel stop',
        color: const Color(0xFF3B82F6),
      );
    default:
      return null;
  }
}

/// Teardrop rally pin for the marshall's "regroup here" point.
class _RallyPin extends StatelessWidget {
  const _RallyPin();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.group_work, color: Color(0xFF7C3AED), size: 34),
      ],
    );
  }
}

/// Warning chip shown only when one or more phones are low on battery.
class _LowBatteryChip extends StatelessWidget {
  const _LowBatteryChip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const warn = Color(0xFFEF4444);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: scheme.surface,
          borderRadius: AppRadii.full,
          elevation: 2,
          child: InkWell(
            borderRadius: AppRadii.full,
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.battery_alert, size: 18, color: warn),
                  const SizedBox(width: 6),
                  Text(
                    '$count low battery',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact HUD chip summarising how tightly the pack is travelling. Green
/// when together, amber with a trailing count when members fall behind. Tap to
/// open the straggler roster.
class _PackStatusChip extends StatelessWidget {
  const _PackStatusChip({required this.cohesion, required this.onTap});

  final PackCohesion cohesion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final together = cohesion.isTogether;
    final accent =
        together ? const Color(0xFF2ECC71) : const Color(0xFFF59E0B);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: scheme.surface,
          borderRadius: AppRadii.full,
          elevation: 2,
          child: InkWell(
            borderRadius: AppRadii.full,
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    together ? Icons.groups : Icons.directions_run,
                    size: 18,
                    color: accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    together
                        ? 'Pack together'
                        : '${cohesion.stragglers.length} trailing · ${formatMetres(cohesion.spreadMetres)}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned marshall announcement shown at the top of the map. Reads the latest
/// from REST (on open) and from the live socket (for members connected when it
/// was sent), picking whichever is newer. Dismiss is local and per-id.
class AnnouncementBanner extends ConsumerStatefulWidget {
  const AnnouncementBanner({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends ConsumerState<AnnouncementBanner> {
  String? _dismissedId;

  @override
  Widget build(BuildContext context) {
    final announcement = pickLatestAnnouncement(
      ref.watch(latestAnnouncementProvider(widget.tripId)).valueOrNull,
      ref.watch(liveTripProvider(widget.tripId)).latestAnnouncement,
    );
    if (announcement == null || announcement.id == _dismissedId) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // When the announcement is a rally, show live distance from me + Navigate.
    final rally = rallyPointOf(announcement);
    String? distanceLabel;
    if (rally != null) {
      final myId = ref.watch(meProvider).valueOrNull?.id;
      final myPos = myId == null
          ? null
          : ref.watch(liveTripProvider(widget.tripId)).members[myId]?.position;
      if (myPos != null) {
        distanceLabel = formatMetres(
          const Distance().as(LengthUnit.Meter, myPos, rally),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: scheme.tertiaryContainer,
        borderRadius: AppRadii.lg,
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                rally != null ? Icons.group_work : Icons.campaign,
                color: scheme.onTertiaryContainer,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      rally != null
                          ? 'Regroup · ${announcement.senderLabel}'
                          : 'Marshall · ${announcement.senderLabel}',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      distanceLabel != null
                          ? '${announcement.body} · $distanceLabel away'
                          : announcement.body,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                    if (rally != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: InkWell(
                          onTap: () => launchUrl(
                            Uri.parse(
                              'https://www.google.com/maps/dir/?api=1&destination=${rally.latitude},${rally.longitude}',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.navigation,
                                  size: 14, color: scheme.onTertiaryContainer),
                              const SizedBox(width: 4),
                              Text(
                                'Navigate',
                                style: textTheme.labelMedium?.copyWith(
                                  color: scheme.onTertiaryContainer,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close,
                    size: 18, color: scheme.onTertiaryContainer),
                onPressed: () =>
                    setState(() => _dismissedId = announcement.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
