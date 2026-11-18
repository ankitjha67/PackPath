import 'mesh_message.dart';

/// Abstraction over a nearby-device transport (Bluetooth / Wi-Fi Direct via
/// Nearby Connections, BLE, etc). The rest of the app depends only on this
/// interface, so the concrete radio can be swapped or stubbed (e.g. on web)
/// without touching the chat layer.
abstract class MeshTransport {
  /// Begin advertising + discovering peers for [tripId]. [selfId] is the local
  /// user id, stamped onto outgoing messages and used to ignore our own.
  Future<void> start({required String tripId, required String selfId});

  /// Stop all advertising/discovery and drop connections.
  Future<void> stop();

  /// Broadcast [message] to every currently-connected peer.
  Future<void> broadcast(MeshMessage message);

  /// De-duplicated stream of messages received from peers (already filtered to
  /// the active trip and excluding our own).
  Stream<MeshMessage> get inbound;

  /// Number of currently-connected peers (for a "N nearby" UI badge).
  Stream<int> get peerCount;
}

/// No-op transport used where nearby radios are unavailable (e.g. Flutter web)
/// or before the feature is enabled. Keeps the app fully functional online.
class NoopMeshTransport implements MeshTransport {
  const NoopMeshTransport();

  @override
  Future<void> start({required String tripId, required String selfId}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> broadcast(MeshMessage message) async {}

  @override
  Stream<MeshMessage> get inbound => const Stream.empty();

  @override
  Stream<int> get peerCount => const Stream.empty();
}
