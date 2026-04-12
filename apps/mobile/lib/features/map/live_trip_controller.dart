import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/token_storage.dart';
import '../../core/ws_client.dart';
import '../../shared/models/member_location.dart';

/// Owns the WebSocket connection for one trip and exposes the live snapshot
/// of every member's last-known location.
///
/// This is the "Weekend 3 — live map" engine. It does NOT yet read the device
/// GPS — that comes when we wire `geolocator` to the publish loop. Right now
/// you can drive it from the API tests or another mobile session.
class LiveTripState {
  const LiveTripState({
    required this.connected,
    required this.members,
    this.lastEvent,
  });

  final bool connected;
  final Map<String, MemberLocation> members;
  final String? lastEvent;

  LiveTripState copyWith({
    bool? connected,
    Map<String, MemberLocation>? members,
    String? lastEvent,
  }) =>
      LiveTripState(
        connected: connected ?? this.connected,
        members: members ?? this.members,
        lastEvent: lastEvent ?? this.lastEvent,
      );

  static const empty = LiveTripState(connected: false, members: {});
}

class LiveTripController extends StateNotifier<LiveTripState> {
  LiveTripController({required this.tripId, required this.token})
      : super(LiveTripState.empty) {
    _connect();
  }

  final String tripId;
  final String token;

  TripSocket? _socket;
  StreamSubscription<Map<String, dynamic>>? _sub;

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
  }

  void _onFrame(Map<String, dynamic> frame) {
    final type = frame['type'] as String?;
    final userId = frame['user_id'] as String?;
    if (type == null || userId == null) return;

    if (type == 'location') {
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
    } else if (type == 'message') {
      state = state.copyWith(lastEvent: 'message');
    }
  }

  /// Publish the current device's position. Wired by the location service in
  /// Weekend 3 follow-up; for now you can call this from a debug button.
  void publishLocation({
    required double lat,
    required double lng,
    double? heading,
    double? speed,
    int? battery,
  }) {
    _socket?.send({
      'type': 'location',
      'lat': lat,
      'lng': lng,
      if (heading != null) 'hdg': heading,
      if (speed != null) 'spd': speed,
      if (battery != null) 'bat': battery,
      't': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _socket?.close();
    super.dispose();
  }
}

final liveTripProvider = StateNotifierProvider.autoDispose
    .family<LiveTripController, LiveTripState, String>((ref, tripId) {
  // We need an access token to authenticate the WS handshake. The token
  // storage provider is async, so we read its current value via a side
  // channel: callers should ensure they're authenticated before navigating
  // here. If the token is null we surface an error state.
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
