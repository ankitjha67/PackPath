import 'dart:async';
import 'dart:math';

import 'package:hive/hive.dart';

import 'mesh_message.dart';
import 'mesh_transport.dart';

/// Glue between a [MeshTransport] and the trip chat.
///
/// Responsibilities:
///  * start/stop the transport for a trip;
///  * surface inbound mesh messages to the chat UI (as chat frames);
///  * when a message is sent while the server is unreachable, broadcast it
///    over the mesh AND persist it to a durable "reconcile" outbox so it can
///    be written back to the server once connectivity returns (idempotent via
///    the client message id).
class MeshChatCoordinator {
  MeshChatCoordinator({required this.transport});

  final MeshTransport transport;

  final _rng = Random();
  StreamSubscription<MeshMessage>? _inboundSub;
  Box<String>? _outbox;
  String _tripId = '';
  String _selfId = '';
  bool _started = false;

  /// Number of nearby peers, for a UI badge.
  Stream<int> get peerCount => transport.peerCount;

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_rng.nextInt(1 << 32)}';

  /// Start the mesh for [tripId]. [onInbound] is invoked with a chat frame
  /// (same envelope as WS frames) for each fresh peer message.
  Future<void> start({
    required String tripId,
    required String selfId,
    required void Function(Map<String, dynamic> frame) onInbound,
  }) async {
    if (_started) return;
    _started = true;
    _tripId = tripId;
    _selfId = selfId;
    _outbox = await Hive.openBox<String>('pp.mesh_outbox_$tripId');

    try {
      await transport.start(tripId: tripId, selfId: selfId);
    } catch (_) {
      // Radio unavailable / permission denied — degrade to online-only.
      _started = false;
      return;
    }

    _inboundSub = transport.inbound.listen((msg) {
      onInbound({
        'type': 'message',
        'user_id': msg.senderId,
        'body': msg.body,
        'cid': msg.id,
        'origin': 'mesh',
      });
    });
  }

  /// Broadcast [body] over the mesh and persist it for server reconciliation.
  /// Returns the client message id (also used for de-duplication in the UI).
  Future<String> sendOffline(String body) async {
    final id = _newId();
    final msg = MeshMessage(
      id: id,
      tripId: _tripId,
      senderId: _selfId,
      body: body,
      sentAt: DateTime.now().toUtc(),
    );
    await _outbox?.put(id, msg.encode());
    try {
      await transport.broadcast(msg);
    } catch (_) {/* no peers / radio hiccup — still queued for server */}
    return id;
  }

  /// Flush the reconcile outbox to the server via [send], which should deliver
  /// one (clientId, body) pair and complete when accepted. Entries are removed
  /// as they succeed; a throwing [send] stops the flush for a later retry.
  Future<void> reconcile(
    Future<void> Function(String clientId, String body) send,
  ) async {
    final box = _outbox;
    if (box == null || box.isEmpty) return;
    for (final key in box.keys.toList()) {
      final raw = box.get(key);
      if (raw == null) continue;
      final msg = MeshMessage.tryParse(raw);
      if (msg == null) {
        await box.delete(key);
        continue;
      }
      try {
        await send(msg.id, msg.body);
        await box.delete(key);
      } catch (_) {
        break;
      }
    }
  }

  Future<void> stop() async {
    await _inboundSub?.cancel();
    _inboundSub = null;
    if (_started) {
      try {
        await transport.stop();
      } catch (_) {}
    }
    _started = false;
  }
}
