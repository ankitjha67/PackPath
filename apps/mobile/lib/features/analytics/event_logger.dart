import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/api_client.dart';

/// Buffered telemetry — every event lands in a Hive box first, the
/// flusher batches them up and POSTs to /events. Works offline (the
/// queue drains on the next successful flush).
class EventLogger {
  EventLogger(this._dio, this._box);

  static const _boxName = 'pp.events_queue';
  static const _maxBatch = 100;
  static const _flushInterval = Duration(seconds: 30);

  final Dio _dio;
  final Box<String> _box;
  Timer? _timer;
  int _nextKey = 0;

  static Future<EventLogger> open(Dio dio) async {
    final box = await Hive.openBox<String>(_boxName);
    final logger = EventLogger(dio, box);
    final keys = box.keys.cast<int>().toList()..sort();
    logger._nextKey = keys.isEmpty ? 0 : keys.last + 1;
    logger._timer = Timer.periodic(_flushInterval, (_) => logger.flush());
    return logger;
  }

  Future<void> log(
    String name, {
    Map<String, dynamic> properties = const {},
    String? sessionId,
    String? tripId,
  }) async {
    final entry = jsonEncode({
      'name': name,
      'properties': properties,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'session_id': sessionId,
      'trip_id': tripId,
    });
    await _box.put(_nextKey++, entry);
  }

  /// Push the buffered events. Caller can also fire this manually on
  /// shutdown / app background.
  Future<void> flush() async {
    if (_box.isEmpty) return;
    final keys =
        (_box.keys.cast<int>().toList()..sort()).take(_maxBatch).toList();
    final batch = keys
        .map((k) => jsonDecode(_box.get(k)!) as Map<String, dynamic>)
        .toList();
    try {
      await _dio.post('/events', data: {'events': batch});
      await _box.deleteAll(keys);
    } catch (e) {
      debugPrint('event flush failed: $e');
    }
  }

  Future<void> close() async {
    _timer?.cancel();
    await flush();
  }
}

final eventLoggerProvider = FutureProvider<EventLogger>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  final logger = await EventLogger.open(dio);
  ref.onDispose(logger.close);
  return logger;
});
