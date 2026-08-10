import 'dart:async';
import 'dart:math';

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
    this.activeSafetyAlert,
    this.lastEvent,
  });

  final bool connected;
  final Map<String, MemberLocation> members;
  final Set<String> typingUserIds;
  final int queuedFrames;
  final Map<String, dynamic>? activeSafetyAlert;
  final String? lastEvent;

  LiveTripState copyWith({
    bool? connected,
    Map<String, MemberLocation>? members,
    Set<String>? typingUserIds,
    int? queuedFrames,
    Map<String, dynamic>? activeSafetyAlert,
    bool clearSafetyAlert = false,
    String? lastEvent,
  }) =>
      LiveTripState(
        connected: connected ?? this.connected,
        members: members ?? this.members,
        typingUserIds: typingUserIds ?? this.typingUserIds,
        queuedFrames: queuedFrames ?? this.queuedFrames,
        activeSafetyAlert: clearSafetyAlert
            ? null
            : (activeSafetyAlert ?? this.activeSafetyAlert),
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
    _connect();
    await _startBroadcasting();
  }

  void _connect() {
    if (_disposed || token.isEmpty) return;
    // Tear down any previous socket before reconnecting so we never leak a
    // dangling subscription/connection.
    _sub?.cancel();
    _socket?.close();

    final socket = TripSocket(tripId: tripId, accessToken: token);
    _socket = socket;
    _sub = socket.connect().listen(
          _onFrame,
          onError: (Object _) => _onDisconnected('error'),
          onDone: () => _onDisconnected('closed'),
          cancelOnError: true,
        );
    state = state.copyWith(connected: true, lastEvent: 'connected');
    // Drain whatever the queue picked up while we were disconnected.
    unawaited(_drainQueue());
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
    _reconnectTimer = Timer(delay, _connect);
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
      );
    });
  }

  void _onFrame(Map<String, dynamic> frame) {
    // A frame arriving means the socket is healthy — reset backoff.
    _reconnectAttempts = 0;
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
    } else if (type == 'safety') {
      state = state.copyWith(
        activeSafetyAlert: frame,
        lastEvent: 'safety:${frame['kind']}',
      );
    }
  }

  /// Dismiss the currently-active safety alert (called by the alert sheet).
  void clearSafetyAlert() {
    state = state.copyWith(clearSafetyAlert: true);
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
    final frame = {'type': 'message', 'body': body};
    if (state.connected && _socket != null) {
      _socket!.send(frame);
      return true;
    }
    await _enqueue(frame);
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
  void sendSafety({
    required String kind,
    Map<String, dynamic> details = const {},
  }) {
    if (_socket == null) return;
    _socket!.send({
      'type': kind,
      ...details,
      't': DateTime.now().toUtc().toIso8601String(),
    });
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
  // Read the token synchronously (storage is opened eagerly in main.dart), so
  // a cold-start deep link to a trip doesn't throw while async storage loads.
  // An empty token leaves the controller disconnected rather than crashing;
  // the router already keeps unauthenticated users out of trip routes.
  final storage = ref.watch(tokenStorageSyncProvider);
  final token = storage.accessToken ?? '';
  // StateNotifierProvider disposes the notifier itself — no ref.onDispose.
  return LiveTripController(tripId: tripId, token: token);
});
