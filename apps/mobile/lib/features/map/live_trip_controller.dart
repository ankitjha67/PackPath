import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/token_storage.dart';
import '../../core/ws_auth.dart';
import '../../core/ws_client.dart';
import '../../shared/models/member_location.dart';
import '../chat/mesh/mesh_transport.dart';
import '../chat/mesh/mesh_chat_coordinator.dart';
import '../chat/mesh/nearby_mesh_transport.dart';
import 'location_service.dart';
import 'outbound_queue.dart';

/// Owns the WebSocket connection for one trip and exposes the live snapshot
/// of every member's last-known location.
///
/// Also runs the device GPS publisher and the durable outbound queue —
/// frames captured while disconnected are buffered to Hive and drained on
/// reconnect, in insertion order.
/// Max breadcrumb points kept per member (older points drop off the tail).
const int _maxTrailPoints = 40;

class LiveTripState {
  const LiveTripState({
    required this.connected,
    required this.members,
    this.typingUserIds = const {},
    this.onlineUserIds = const {},
    this.readyUserIds = const {},
    this.memberStatus = const {},
    this.trails = const {},
    this.roadHazards = const {},
    this.activeDetour,
    this.queuedFrames = 0,
    this.nearbyPeers = 0,
    this.activeSafetyAlert,
    this.latestAnnouncement,
    this.lastNudge,
    this.lastEvent,
  });

  final bool connected;
  final Map<String, MemberLocation> members;
  final Set<String> typingUserIds;

  /// Trip members currently connected (WS presence). Drives the online dot
  /// on the members list and profiles.
  final Set<String> onlineUserIds;

  /// Trip members who have marked themselves ready (ready-check). Seeded from
  /// REST when the panel opens and kept live by 'ready' frames.
  final Set<String> readyUserIds;

  /// Live per-member status ('moving'/'stopped'/'break'/'fuel') from 'status'
  /// frames. Absent means the default (on the move).
  final Map<String, String> memberStatus;

  /// Recent path per member (most recent last), capped, for breadcrumb trails.
  final Map<String, List<LatLng>> trails;

  /// Live member-reported road hazards, keyed by hazard id. A hazard drops off
  /// when it is cleared (`road_hazard_cleared`). Seeded from REST on open.
  final Map<String, Map<String, dynamic>> roadHazards;

  /// The open detour proposal the pack is currently voting on, if any. Carries
  /// the running tally; cleared when resolved.
  final Map<String, dynamic>? activeDetour;

  final int queuedFrames;

  /// Count of trip members reachable over the Bluetooth/Nearby mesh right now.
  final int nearbyPeers;
  final Map<String, dynamic>? activeSafetyAlert;

  /// Most recent marshall announcement delivered over the live socket. Drives
  /// the pinned banner for members already connected when it was sent.
  final Map<String, dynamic>? latestAnnouncement;

  /// Most recent nudge aimed at *this* user (filtered on receipt). The map
  /// screen shows an alert + haptic and dedupes on nudge_id.
  final Map<String, dynamic>? lastNudge;
  final String? lastEvent;

  LiveTripState copyWith({
    bool? connected,
    Map<String, MemberLocation>? members,
    Set<String>? typingUserIds,
    Set<String>? onlineUserIds,
    Set<String>? readyUserIds,
    Map<String, String>? memberStatus,
    Map<String, List<LatLng>>? trails,
    Map<String, Map<String, dynamic>>? roadHazards,
    Map<String, dynamic>? activeDetour,
    bool clearDetour = false,
    int? queuedFrames,
    int? nearbyPeers,
    Map<String, dynamic>? activeSafetyAlert,
    bool clearSafetyAlert = false,
    Map<String, dynamic>? latestAnnouncement,
    Map<String, dynamic>? lastNudge,
    String? lastEvent,
  }) =>
      LiveTripState(
        connected: connected ?? this.connected,
        members: members ?? this.members,
        typingUserIds: typingUserIds ?? this.typingUserIds,
        onlineUserIds: onlineUserIds ?? this.onlineUserIds,
        readyUserIds: readyUserIds ?? this.readyUserIds,
        memberStatus: memberStatus ?? this.memberStatus,
        trails: trails ?? this.trails,
        roadHazards: roadHazards ?? this.roadHazards,
        activeDetour:
            clearDetour ? null : (activeDetour ?? this.activeDetour),
        queuedFrames: queuedFrames ?? this.queuedFrames,
        nearbyPeers: nearbyPeers ?? this.nearbyPeers,
        activeSafetyAlert: clearSafetyAlert
            ? null
            : (activeSafetyAlert ?? this.activeSafetyAlert),
        latestAnnouncement: latestAnnouncement ?? this.latestAnnouncement,
        lastNudge: lastNudge ?? this.lastNudge,
        lastEvent: lastEvent ?? this.lastEvent,
      );

  static const empty = LiveTripState(connected: false, members: {});
}

class LiveTripController extends StateNotifier<LiveTripState> {
  LiveTripController({
    required this.tripId,
    required this.token,
    required FreshTokenFn freshToken,
    required MeshTransport meshTransport,
  })  : _freshToken = freshToken,
        _mesh = MeshChatCoordinator(transport: meshTransport),
        super(LiveTripState.empty) {
    _selfId = _subFromJwt(token);
    _bootstrap();
  }

  final String tripId;

  /// The access token captured at creation — used only to derive [_selfId].
  /// Every (re)connect fetches a fresh token via [_freshToken] so a socket
  /// that outlives the 15-minute access-TTL can still reconnect.
  final String token;
  final FreshTokenFn _freshToken;

  /// Bluetooth/Nearby mesh for offline chat (unified auto-failover).
  final MeshChatCoordinator _mesh;
  late final String _selfId;

  TripSocket? _socket;
  StreamSubscription<Map<String, dynamic>>? _sub;

  AdaptiveLocationService? _locationService;
  StreamSubscription<Position>? _locationSub;
  StreamSubscription<int>? _meshPeerSub;
  OutboundQueue? _queue;

  // Battery telemetry, sampled periodically and stamped onto location frames so
  // the pack sees each member's battery ring and the service can drop to
  // significant-change-only when critically low.
  Battery? _battery;
  Timer? _batteryTimer;
  int? _batteryPct;

  // Reconnect bookkeeping.
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _disposed = false;
  static const _maxReconnectDelay = Duration(seconds: 30);
  final _rng = Random();

  /// Broadcast stream of inbound chat / arrival frames so screens beyond
  /// the map (e.g. ChatScreen) can subscribe without owning a second WS.
  final _chatController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get chatStream => _chatController.stream;

  Future<void> _bootstrap() async {
    _queue = await OutboundQueue.open(tripId);
    if (!mounted) return; // backed out of the screen mid-await
    state = state.copyWith(queuedFrames: _queue!.length);
    unawaited(_connect());
    await _startMesh();
    if (!mounted) return;
    await _startBroadcasting();
  }

  /// Bring up the nearby mesh so chat keeps working with no internet. Inbound
  /// peer messages are pushed into the same chat stream as WS messages.
  Future<void> _startMesh() async {
    if (_selfId.isEmpty) return;
    await _mesh.start(
      tripId: tripId,
      selfId: _selfId,
      onInbound: (frame) {
        if (!mounted) return;
        state = state.copyWith(lastEvent: 'mesh');
        _chatController.add(frame);
      },
    );
    _meshPeerSub = _mesh.peerCount.listen((n) {
      if (!mounted) return;
      state = state.copyWith(nearbyPeers: n);
    });
  }

  /// Decode the `sub` (user id) claim from the JWT without verifying it —
  /// used only to stamp/identify our own mesh messages.
  static String _subFromJwt(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return '';
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final map = jsonDecode(utf8.decode(base64.decode(payload)))
          as Map<String, dynamic>;
      return map['sub'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _connect() async {
    if (_disposed) return;
    // Fetch a fresh (refreshed-if-expired) token on every connect so a
    // long-lived socket can reconnect after the access token expires —
    // otherwise queued SOS/crash frames would never deliver.
    final freshToken = await _freshToken();
    if (_disposed) return;
    if (freshToken == null || freshToken.isEmpty) {
      // Couldn't get a usable token (refresh failed) — back off and retry.
      _scheduleReconnect();
      return;
    }
    // Tear down any previous socket before reconnecting so we never leak a
    // dangling subscription/connection.
    _sub?.cancel();
    _socket?.close();

    final socket = TripSocket(tripId: tripId, accessToken: freshToken);
    _socket = socket;
    _sub = socket.connect().listen(
          _onFrame,
          onError: (Object _) => _onDisconnected('error'),
          onDone: () => _onDisconnected('closed'),
          cancelOnError: true,
        );
    // Mark the connection live only once the WS handshake actually completes.
    // Setting connected:true immediately (before the socket opens) let chat /
    // location frames captured in the dial window write into a sink that never
    // opened and get dropped; now they stay on the durable-queue/mesh path
    // until the socket is truly ready.
    unawaited(
      socket.ready.then((_) {
        if (_disposed || _socket != socket) return;
        state = state.copyWith(connected: true, lastEvent: 'connected');
        // Drain whatever the queue buffered while disconnected, and push any
        // mesh-only chat messages to the server now that we're back online.
        unawaited(_drainQueue());
        unawaited(_reconcileMesh());
      }).catchError((Object _) {
        if (_disposed || _socket != socket) return;
        _onDisconnected('error');
      }),
    );
  }

  Future<void> _reconcileMesh() async {
    if (_socket == null) return;
    await _mesh.reconcile((clientId, body) async {
      final s = _socket;
      if (s == null) throw StateError('socket closed mid-reconcile');
      s.send({'type': 'message', 'body': body, 'cid': clientId});
    });
  }

  void _onDisconnected(String reason) {
    if (_disposed) return;
    state = state.copyWith(connected: false, lastEvent: reason);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    // Exponential backoff capped at 30s, with jitter to avoid a thundering
    // herd when a whole group regains signal at once.
    final base = min(
      _maxReconnectDelay.inMilliseconds,
      500 * (1 << _reconnectAttempts.clamp(0, 6)),
    );
    final delay = Duration(
      milliseconds: base ~/ 2 + _rng.nextInt((base ~/ 2) + 1),
    );
    _reconnectAttempts++;
    _reconnectTimer = Timer(delay, () => unawaited(_connect()));
  }

  Future<void> _startBroadcasting() async {
    final svc = AdaptiveLocationService();
    final ok = await svc.start();
    if (!mounted) {
      svc.dispose();
      return;
    }
    if (!ok) {
      state = state.copyWith(lastEvent: 'no-permission');
      return;
    }
    _locationService = svc;
    _locationSub = svc.stream.listen((p) {
      publishLocation(
        lat: p.latitude,
        lng: p.longitude,
        heading: p.heading,
        speed: p.speed,
        battery: _batteryPct,
      );
    });
    // Sample battery now and every 60s; feed the service so it can suspend the
    // GPS stream when critically low.
    _battery = Battery();
    await _refreshBattery();
    _batteryTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshBattery(),
    );
  }

  Future<void> _refreshBattery() async {
    final b = _battery;
    if (b == null) return;
    try {
      final pct = await b.batteryLevel;
      if (!mounted) return;
      _batteryPct = pct;
      _locationService?.onBatteryUpdate(pct);
    } catch (_) {
      // Battery level unavailable on this platform — leave telemetry unset.
    }
  }

  void _onFrame(Map<String, dynamic> frame) {
    // A frame arriving means the socket is healthy — reset backoff.
    _reconnectAttempts = 0;
    final type = frame['type'] as String?;
    final userId = frame['user_id'] as String?;
    if (type == null) return;

    // Any frame carrying a user_id proves that member is connected right now.
    if (userId != null && !state.onlineUserIds.contains(userId)) {
      state = state.copyWith(
        onlineUserIds: {...state.onlineUserIds, userId},
      );
    }

    if (type == 'location' && userId != null) {
      final lat = (frame['lat'] as num?)?.toDouble();
      final lng = (frame['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      final next = Map<String, MemberLocation>.from(state.members);
      next[userId] = MemberLocation(
        userId: userId,
        position: LatLng(lat, lng),
        heading: (frame['hdg'] as num?)?.toDouble(),
        speed: (frame['spd'] as num?)?.toDouble(),
        battery: (frame['bat'] as num?)?.toInt(),
      );
      // Append to this member's breadcrumb trail (capped).
      final trails = Map<String, List<LatLng>>.from(state.trails);
      final trail = List<LatLng>.from(trails[userId] ?? const <LatLng>[])
        ..add(LatLng(lat, lng));
      if (trail.length > _maxTrailPoints) {
        trail.removeRange(0, trail.length - _maxTrailPoints);
      }
      trails[userId] = trail;
      state = state.copyWith(members: next, trails: trails, lastEvent: 'location');
    } else if (type == 'presence') {
      final online = Set<String>.from(state.onlineUserIds);
      if (userId != null) {
        if (frame['state'] == 'left') {
          online.remove(userId);
        } else {
          online.add(userId);
        }
      }
      state = state.copyWith(
        onlineUserIds: online,
        lastEvent: 'presence:${frame['state']}',
      );
    } else if (type == 'typing' && userId != null) {
      final next = Set<String>.from(state.typingUserIds);
      if (frame['state'] == 'start') {
        next.add(userId);
      } else {
        next.remove(userId);
      }
      state = state.copyWith(typingUserIds: next, lastEvent: 'typing');
    } else if (type == 'ready' && userId != null) {
      final next = Set<String>.from(state.readyUserIds);
      if (frame['is_ready'] == true) {
        next.add(userId);
      } else {
        next.remove(userId);
      }
      state = state.copyWith(readyUserIds: next, lastEvent: 'ready');
    } else if (type == 'status' && userId != null) {
      final status = frame['status'] as String?;
      final next = Map<String, String>.from(state.memberStatus);
      if (status == null || status == 'moving') {
        next.remove(userId);
      } else {
        next[userId] = status;
      }
      state = state.copyWith(memberStatus: next, lastEvent: 'status');
    } else if (type == 'nudge') {
      // Only the targeted member reacts to a nudge.
      if (frame['to_user_id'] == _selfId) {
        state = state.copyWith(
          lastNudge: Map<String, dynamic>.from(frame),
          lastEvent: 'nudge',
        );
      }
    } else if (type == 'message') {
      // Drop the sender's typing indicator since the message landed.
      if (userId != null && state.typingUserIds.contains(userId)) {
        final next = Set<String>.from(state.typingUserIds)..remove(userId);
        state = state.copyWith(typingUserIds: next);
      }
      // A marshall announcement arrives as a message frame with kind
      // 'announcement' — pin it as the latest broadcast.
      if (frame['kind'] == 'announcement') {
        state = state.copyWith(
          latestAnnouncement: Map<String, dynamic>.from(frame),
          lastEvent: 'announcement',
        );
      } else {
        state = state.copyWith(lastEvent: 'message');
      }
      _chatController.add(frame);
    } else if (type == 'arrival') {
      state = state.copyWith(
        lastEvent: 'arrival:${frame['waypoint_name'] ?? ''}',
      );
      _chatController.add(frame);
    } else if (type == 'reaction') {
      // Forwarded to the chat screen, which keeps the live reaction overlay.
      _chatController.add(frame);
    } else if (type == 'safety') {
      state = state.copyWith(
        activeSafetyAlert: frame,
        lastEvent: 'safety:${frame['kind']}',
      );
    } else if (type == 'safety_resolved') {
      // "I'm safe / all clear" — clear the active alert if it's this one.
      if (state.activeSafetyAlert?['alert_id'] == frame['alert_id']) {
        state = state.copyWith(
          clearSafetyAlert: true,
          lastEvent: 'safety_resolved',
        );
      }
    } else if (type == 'road_hazard') {
      final id = frame['id'] as String?;
      if (id != null) {
        final next = Map<String, Map<String, dynamic>>.from(state.roadHazards);
        next[id] = Map<String, dynamic>.from(frame);
        state = state.copyWith(roadHazards: next, lastEvent: 'road_hazard');
      }
    } else if (type == 'road_hazard_cleared') {
      final id = frame['id'] as String?;
      if (id != null && state.roadHazards.containsKey(id)) {
        final next = Map<String, Map<String, dynamic>>.from(state.roadHazards)
          ..remove(id);
        state = state.copyWith(
          roadHazards: next,
          lastEvent: 'road_hazard_cleared',
        );
      }
    } else if (type == 'detour_proposed') {
      state = state.copyWith(
        activeDetour: Map<String, dynamic>.from(frame),
        lastEvent: 'detour_proposed',
      );
    } else if (type == 'detour_vote') {
      // Update the running tally on the active proposal if it's this one.
      if (state.activeDetour?['id'] == frame['id']) {
        final updated = Map<String, dynamic>.from(state.activeDetour!)
          ..['yes'] = frame['yes']
          ..['no'] = frame['no'];
        state = state.copyWith(activeDetour: updated, lastEvent: 'detour_vote');
      }
    } else if (type == 'detour_resolved') {
      if (state.activeDetour?['id'] == frame['id']) {
        state = state.copyWith(
          clearDetour: true,
          lastEvent: 'detour_resolved:${frame['outcome']}',
        );
      }
    }
  }

  /// Seed the live hazard set from a REST snapshot (map open) so hazards
  /// dropped before this client connected are already on the map.
  void seedRoadHazards(List<Map<String, dynamic>> hazards) {
    final next = <String, Map<String, dynamic>>{};
    for (final h in hazards) {
      final id = h['id'] as String?;
      if (id != null) next[id] = h;
    }
    state = state.copyWith(roadHazards: next);
  }

  /// Seed / set the currently open detour (map open, or after proposing).
  void seedActiveDetour(Map<String, dynamic>? detour) {
    if (detour == null) {
      state = state.copyWith(clearDetour: true);
    } else {
      state = state.copyWith(activeDetour: detour);
    }
  }

  /// Dismiss the active detour banner locally (e.g. after this user acts).
  void clearDetour() {
    state = state.copyWith(clearDetour: true);
  }

  /// Dismiss the currently-active safety alert (called by the alert sheet).
  void clearSafetyAlert() {
    state = state.copyWith(clearSafetyAlert: true);
  }

  /// Seed the ready-check set from a REST snapshot (called when the ready
  /// panel opens) so it reflects toggles made while this client was away.
  void seedReady(Set<String> readyIds) {
    state = state.copyWith(readyUserIds: readyIds);
  }

  void publishLocation({
    required double lat,
    required double lng,
    double? heading,
    double? speed,
    int? battery,
  }) {
    final frame = <String, dynamic>{
      'type': 'location',
      'lat': lat,
      'lng': lng,
      if (heading != null) 'hdg': heading,
      if (speed != null) 'spd': speed,
      if (battery != null) 'bat': battery,
      't': DateTime.now().toUtc().toIso8601String(),
    };
    if (state.connected && _socket != null) {
      _socket!.send(frame);
    } else {
      // Buffer for the next reconnect.
      unawaited(_enqueue(frame));
    }
  }

  /// Send a chat message. Returns true if it went out over the live socket,
  /// false if it was durably queued for the next reconnect (so the UI can
  /// show a "queued" state instead of a false "sent"). This is the seam the
  /// Bluetooth transport hooks into for offline delivery.
  Future<bool> sendChat(String body) async {
    if (state.connected && _socket != null) {
      _socket!.send({'type': 'message', 'body': body});
      return true;
    }
    // Offline: deliver to nearby members over the Bluetooth/Nearby mesh and
    // durably queue for the server to pick up on reconnect.
    await _mesh.sendOffline(body);
    return false;
  }

  /// Notify peers that the local user is typing. Call with `false` when
  /// the input becomes empty or after a 3s idle.
  void sendTyping({required bool start}) {
    if (!state.connected || _socket == null) return;
    _socket!.send({'type': 'typing', 'state': start ? 'start' : 'stop'});
  }

  /// Fire a safety frame ("sos" or "crash") into the trip. The server
  /// persists, fans out as a `safety` frame, and may add a follow-up
  /// chat message.
  ///
  /// Returns true if it went out over the live socket, false if it was durably
  /// queued for the next reconnect. Safety alerts matter most exactly when
  /// connectivity is flaky, so — unlike a plain `_socket != null` check, which
  /// stays non-null against a dead socket after a drop — an offline alert is
  /// buffered to the outbound queue and delivered on reconnect instead of
  /// being written into a closed sink and lost.
  Future<bool> sendSafety({
    required String kind,
    Map<String, dynamic> details = const {},
  }) async {
    final frame = <String, dynamic>{
      'type': kind,
      ...details,
      't': DateTime.now().toUtc().toIso8601String(),
    };
    if (state.connected && _socket != null) {
      _socket!.send(frame);
      return true;
    }
    await _enqueue(frame);
    return false;
  }

  Future<void> _enqueue(Map<String, dynamic> frame) async {
    final q = _queue;
    if (q == null) return;
    await q.add(frame);
    if (!mounted) return;
    state = state.copyWith(queuedFrames: q.length);
  }

  Future<void> _drainQueue() async {
    final q = _queue;
    if (q == null || q.isEmpty || _socket == null) return;
    await q.drain((frame) async {
      _socket!.send(frame);
    });
    if (!mounted) return;
    state = state.copyWith(queuedFrames: q.length);
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _batteryTimer?.cancel();
    _meshPeerSub?.cancel();
    _locationSub?.cancel();
    _locationService?.dispose();
    _sub?.cancel();
    _socket?.close();
    unawaited(_mesh.stop());
    _chatController.close();
    super.dispose();
  }
}

/// Builds the nearby-mesh transport for the current platform. Web has no
/// Bluetooth/Nearby radio, so it gets the no-op transport (online-only chat).
/// Override this in tests to inject a fake transport.
final meshTransportFactoryProvider = Provider<MeshTransport Function()>(
  (ref) => () => kIsWeb ? const NoopMeshTransport() : NearbyMeshTransport(),
);

final liveTripProvider = StateNotifierProvider.autoDispose
    .family<LiveTripController, LiveTripState, String>((ref, tripId) {
  // Read the token synchronously (storage is opened eagerly in main.dart), so
  // a cold-start deep link to a trip doesn't throw while async storage loads.
  // An empty token leaves the controller disconnected rather than crashing;
  // the router already keeps unauthenticated users out of trip routes.
  final storage = ref.watch(tokenStorageSyncProvider);
  final token = storage.accessToken ?? '';
  final meshTransport = ref.watch(meshTransportFactoryProvider)();
  // StateNotifierProvider disposes the notifier itself — no ref.onDispose.
  return LiveTripController(
    tripId: tripId,
    token: token,
    freshToken: ref.watch(freshAccessTokenProvider),
    meshTransport: meshTransport,
  );
});
