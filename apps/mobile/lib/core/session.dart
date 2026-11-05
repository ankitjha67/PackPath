import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Monotonic counter bumped on every login and logout. Per-account data
/// providers `ref.watch(sessionEpochProvider)` so their cached values are
/// recomputed when the active account changes — preventing user A's data
/// from leaking into user B's session on the same device.
final sessionEpochProvider = StateProvider<int>((ref) => 0);
