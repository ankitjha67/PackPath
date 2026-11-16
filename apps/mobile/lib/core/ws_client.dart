import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/env.dart';

/// Thin wrapper around `WebSocketChannel` for `/ws/trips/{id}`.
/// Reconnect logic comes in Weekend 3.
class TripSocket {
  TripSocket({required this.tripId, required this.accessToken});

  final String tripId;
  final String accessToken;

  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _controller;

  /// Completes when the underlying WebSocket handshake has actually finished
  /// (or throws if it fails). Callers should treat the connection as "live"
  /// only after this resolves — the channel accepts `sink.add` calls before
  /// then, but anything sent is dropped if the socket never opens.
  Future<void> get ready => _channel?.ready ?? Future<void>.value();

  Stream<Map<String, dynamic>> connect() {
    final uri = Uri.parse(
      '${Env.wsBaseUrl}/ws/trips/$tripId?token=$accessToken',
    );
    _channel = WebSocketChannel.connect(uri);
    _controller = StreamController<Map<String, dynamic>>.broadcast();

    _channel!.stream.listen(
      (raw) {
        try {
          final decoded = jsonDecode(raw as String);
          if (decoded is Map<String, dynamic>) {
            _controller!.add(decoded);
          }
        } catch (_) {
          // Drop malformed frames silently in v1.
        }
      },
      onDone: () => _controller?.close(),
      onError: (Object err) => _controller?.addError(err),
      cancelOnError: false,
    );

    return _controller!.stream;
  }

  void send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  Future<void> close() async {
    await _channel?.sink.close();
    await _controller?.close();
  }
}
