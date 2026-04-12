import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/token_storage.dart';
import '../../core/ws_client.dart';
import '../../shared/models/member_location.dart';
import 'location_service.dart';
import 'outbound_queue.dart';

/// Owns the WebSocket connection for one trip and exposes the live snapshot
/// of every member's last-known location.
///
/// Also runs the device GPS publisher and the durable outbound queue —
/// frames captured while disconnected are buffered to Hive and drained on
/// reconnect, in insertion order.
class LiveTripState {
  const LiveTripState({
    required this.connected,
    required this.members,
    this.typingUserIds = const {},
    this.queuedFrames = 0,
    this.lastEvent,
  });

  final bool connected;
  final Map<String, MemberLocation> members;
  final Set<String> typingUserIds;
  final int queuedFrames;
  final String? lastEvent;

  LiveTripState copyWith({
    bool? connected,
    Map<String, MemberLocation>? members,
    Set<String>? typingUserIds,
    int? queuedFrames,
    String? lastEvent,
  }) =>
      LiveTripState(
        connected: connected ?? this.connected,
        members: members ?? this.members,
        typingUserIds: typingUserIds ?? this.typingUserIds,
        queuedFrames: queuedFrames ?? this.queuedFrames,
        lastEvent: lastEvent ?? this.lastEvent,
      );

  static const empty = LiveTripState(connected: false, members: {});
}

class LiveTripController extends StateNotifier<LiveTripState> {
  LiveTripController({required this.tripId, required this.token})
      : super(LiveTripState.empty) {
    _bootstrap();
  }

  final String tripId;
  final String token;

  TripSocket? _socket;
  StreamSubscription<Map<String, dynamic>>? _sub;

  AdaptiveLocationService? _locationService;
  StreamSubscription<Position>? _locationSub;
  OutboundQueue? _queue;

  /// Broadcast stream of inbound chat / arrival frames so screens beyond
  /// the map (e.g. ChatScreen) can subscribe without owning a second WS.
  final _chatController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get chatStream => _chatController.stream;

  Future<void> _bootstrap() async {
    _queue = await OutboundQueue.open();
    state = state.copyWith(queuedFrames: _queue!.length);
    _connect();
    await _startBroadcasting();
  }

  void _connect() {
    _socket = TripSocket(tripId: tripId, accessToken: token);
    _sub = _socket!.connect().listen(
          _onFrame,
          onError: (Object _) =>
              state = state.copyWith(connected: false, lastEvent: 'error'),
          onDone: () =>
              state = state.copyWith(connected: false, lastEvent: 'closed'),
        );
    state = state.copyWith(connected: true, lastEvent: 'connected');
    // Drain whatever the queue picked up while we were disconnected.
    unawaited(_drainQueue());
  }

  Future<void> _startBroadcasting() async {
    final svc = AdaptiveLocationService();
    final ok = await svc.start();
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
      );
    });
  }

  void _onFrame(Map<String, dynamic> frame) {
    final type = frame['type'] as String?;
    final userId = frame['user_id'] as String?;
    if (type == null) return;

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
      state = state.copyWith(members: next, lastEvent: 'location');
    } else if (type == 'presence') {
      state = state.copyWith(lastEvent: 'presence:${frame['state']}');
    } else if (type == 'typing' && userId != null) {
      final next = Set<String>.from(state.typingUserIds);
      if (frame['state'] == 'start') {
        next.add(userId);
      } else {
        next.remove(userId);
      }
      state = state.copyWith(typingUserIds: next, lastEvent: 'typing');
    } else if (type == 'message') {
      // Drop the sender's typing indicator since the message landed.
      if (userId != null && state.typingUserIds.contains(userId)) {
        final next = Set<String>.from(state.typingUserIds)..remove(userId);
        state = state.copyWith(typingUserIds: next);
      }
      state = state.copyWith(lastEvent: 'message');
      _chatController.add(frame);
    } else if (type == 'arrival') {
      state = state.copyWith(
        lastEvent: 'arrival:${frame['waypoint_name'] ?? ''}',
      );
      _chatController.add(frame);
    }
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

  /// Send a chat message via the trip socket. Falls back to error state if
  /// the WS isn't up — a future revision will queue messages too.
  void sendChat(String body) {
    if (!state.connected || _socket == null) return;
    _socket!.send({'type': 'message', 'body': body});
  }

  /// Notify peers that the local user is typing. Call with `false` when
  /// the input becomes empty or after a 3s idle.
  void sendTyping({required bool start}) {
    if (!state.connected || _socket == null) return;
    _socket!.send({'type': 'typing', 'state': start ? 'start' : 'stop'});
  }

  Future<void> _enqueue(Map<String, dynamic> frame) async {
    final q = _queue;
    if (q == null) return;
    await q.add(frame);
    state = state.copyWith(queuedFrames: q.length);
  }

  Future<void> _drainQueue() async {
    final q = _queue;
    if (q == null || q.isEmpty || _socket == null) return;
    await q.drain((frame) async {
      _socket!.send(frame);
    });
    state = state.copyWith(queuedFrames: q.length);
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _locationService?.dispose();
    _sub?.cancel();
    _socket?.close();
    _chatController.close();
    super.dispose();
  }
}

final liveTripProvider = StateNotifierProvider.autoDispose
    .family<LiveTripController, LiveTripState, String>((ref, tripId) {
  final storageAsync = ref.watch(tokenStorageProvider);
  final token = storageAsync.maybeWhen(
    data: (s) => s.accessToken,
    orElse: () => null,
  );
  if (token == null) {
    throw StateError('No access token — log in first');
  }
  final controller = LiveTripController(tripId: tripId, token: token);
  ref.onDispose(controller.dispose);
  return controller;
});
