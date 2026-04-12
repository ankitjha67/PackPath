import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Durable FIFO queue for location frames that couldn't be sent because the
/// WebSocket was down (no signal in the hills, app suspended, etc).
///
/// Each frame is just a JSON map. We keep them inside a single Hive box
/// keyed by an auto-incrementing int so order is preserved.
class OutboundQueue {
  OutboundQueue._(this._box);

  static const _boxName = 'pp.outbound_locations';
  final Box<String> _box;
  int _nextKey = 0;

  static Future<OutboundQueue> open() async {
    final box = await Hive.openBox<String>(_boxName);
    final queue = OutboundQueue._(box);
    final keys = box.keys.cast<int>().toList()..sort();
    queue._nextKey = keys.isEmpty ? 0 : keys.last + 1;
    return queue;
  }

  bool get isEmpty => _box.isEmpty;
  int get length => _box.length;

  Future<void> add(Map<String, dynamic> frame) async {
    await _box.put(_nextKey++, jsonEncode(frame));
    // Cap the queue at the most recent ~5 minutes of fast-mode frames so we
    // don't drain stale data forever after a long offline stint.
    const maxEntries = 1000;
    if (_box.length > maxEntries) {
      final keys = _box.keys.cast<int>().toList()..sort();
      await _box.deleteAll(keys.take(_box.length - maxEntries));
    }
  }

  /// Drain everything currently queued, in insertion order, calling [send]
  /// for each frame. If [send] throws, the entry stays in the queue and
  /// draining stops so the next reconnect can try again.
  Future<int> drain(Future<void> Function(Map<String, dynamic>) send) async {
    if (_box.isEmpty) return 0;
    final keys = _box.keys.cast<int>().toList()..sort();
    var sent = 0;
    for (final k in keys) {
      final raw = _box.get(k);
      if (raw == null) continue;
      try {
        final frame = jsonDecode(raw) as Map<String, dynamic>;
        await send(frame);
        await _box.delete(k);
        sent++;
      } catch (_) {
        break;
      }
    }
    return sent;
  }
}
