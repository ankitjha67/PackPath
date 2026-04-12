import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// Watches the accelerometer and emits a "probable crash" callback when
/// a g-spike above [threshold] occurs. The caller is responsible for
/// the cancel-countdown UI before sending the actual frame.
///
/// We compute the magnitude of the user-acceleration vector — `userAcc`
/// excludes gravity — so the static baseline is ~0 and any sharp spike
/// stands out clearly.
class CrashDetector {
  CrashDetector({
    this.threshold = 4.0,
    this.cooldown = const Duration(seconds: 30),
  });

  final double threshold; // in g
  final Duration cooldown;

  StreamSubscription<UserAccelerometerEvent>? _sub;
  DateTime? _lastFire;
  void Function(double gForce)? _onSpike;

  void start(void Function(double gForce) onSpike) {
    _onSpike = onSpike;
    _sub ??= userAccelerometerEventStream().listen(_onEvent);
  }

  void _onEvent(UserAccelerometerEvent e) {
    final magnitude = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / 9.81;
    if (magnitude < threshold) return;
    final now = DateTime.now();
    if (_lastFire != null && now.difference(_lastFire!) < cooldown) return;
    _lastFire = now;
    _onSpike?.call(magnitude);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _onSpike = null;
  }
}
