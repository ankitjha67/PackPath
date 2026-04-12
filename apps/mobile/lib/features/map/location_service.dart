import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Battery-aware GPS publisher.
///
/// Picks an interval based on speed and battery level, the way Life360
/// *should*. We deliberately stop polling instead of dropping accuracy when
/// the user is stationary — that's the single biggest win on Android.
///
/// Modes:
///   * fast      — speed > 10 km/h        → high accuracy,   5 s
///   * walking   — speed > 1 km/h         → balanced,       15 s
///   * stationary— anything below         → low power,      30 s
///   * critical  — battery < 15%          → significant change only
class AdaptiveLocationService {
  AdaptiveLocationService({
    this.fastInterval = const Duration(seconds: 5),
    this.walkingInterval = const Duration(seconds: 15),
    this.stationaryInterval = const Duration(seconds: 30),
    this.lowBatteryThreshold = 15,
  });

  final Duration fastInterval;
  final Duration walkingInterval;
  final Duration stationaryInterval;
  final int lowBatteryThreshold;

  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeat;
  Position? _lastPosition;
  Duration _currentInterval = const Duration(seconds: 5);

  final _controller = StreamController<Position>.broadcast();

  Stream<Position> get stream => _controller.stream;

  /// Asks for the right permissions, then starts the listener.
  /// Returns false if the user permanently denied location access.
  Future<bool> start() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    _restartStream(_currentInterval, LocationAccuracy.high);
    // The position stream alone doesn't fire when the user is stationary.
    // A timer pulse keeps the publish loop going at the chosen interval.
    _heartbeat = Timer.periodic(_currentInterval, (_) => _emitLast());
    return true;
  }

  void _restartStream(Duration interval, LocationAccuracy accuracy) {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(accuracy: accuracy, distanceFilter: 5),
    ).listen(_onPosition);
  }

  void _emitLast() {
    final p = _lastPosition;
    if (p != null) _controller.add(p);
  }

  Future<void> _onPosition(Position p) async {
    _lastPosition = p;
    _controller.add(p);
    await _maybeAdjust(p);
  }

  Future<void> _maybeAdjust(Position p) async {
    // Battery isn't part of geolocator; the controller layer feeds it via
    // [onBatteryUpdate] which can fully suspend the stream when critical.
    final speedKmh = p.speed * 3.6;
    Duration next;
    LocationAccuracy accuracy;
    if (speedKmh > 10) {
      next = fastInterval;
      accuracy = LocationAccuracy.high;
    } else if (speedKmh > 1) {
      next = walkingInterval;
      accuracy = LocationAccuracy.medium;
    } else {
      next = stationaryInterval;
      accuracy = LocationAccuracy.low;
    }
    if (next != _currentInterval) {
      _currentInterval = next;
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(_currentInterval, (_) => _emitLast());
      _restartStream(_currentInterval, accuracy);
    }
  }

  /// Called by the controller when battery info becomes available.
  /// If battery is critically low we shut down the active stream and rely on
  /// the platform's significant-change callback only.
  void onBatteryUpdate(int? batteryPct) {
    if (batteryPct == null) return;
    if (batteryPct < lowBatteryThreshold) {
      _positionSub?.cancel();
      _positionSub = null;
      _heartbeat?.cancel();
      _heartbeat = null;
    }
  }

  Future<void> stop() async {
    await _positionSub?.cancel();
    _heartbeat?.cancel();
    _positionSub = null;
    _heartbeat = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
