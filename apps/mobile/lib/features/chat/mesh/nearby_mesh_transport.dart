import 'dart:async';
import 'dart:collection';

import 'package:flutter_nearby_connections/flutter_nearby_connections.dart';

import 'mesh_message.dart';
import 'mesh_transport.dart';

/// [MeshTransport] backed by `flutter_nearby_connections` — Google Nearby
/// Connections on Android and Multipeer Connectivity on iOS. Peers on the same
/// trip discover each other over Bluetooth / peer-to-peer Wi-Fi with no
/// internet, form a P2P cluster, and exchange chat messages.
///
/// All plugin-specific surface is confined to this file; everything else in
/// the app talks to the [MeshTransport] interface, so a different radio can be
/// dropped in without touching the chat layer. This code needs on-device
/// testing (two phones) — it cannot be exercised in CI or a simulator.
class NearbyMeshTransport implements MeshTransport {
  NearbyService? _service;
  StreamSubscription<dynamic>? _stateSub;
  StreamSubscription<dynamic>? _dataSub;

  final _inbound = StreamController<MeshMessage>.broadcast();
  final _peerCount = StreamController<int>.broadcast();

  late String _tripId;
  late String _selfId;
  late String _tripTag;

  /// deviceIds currently in the connected state.
  final Set<String> _connected = {};

  /// Fixed Nearby/Multipeer service type. iOS requires this to be declared
  /// statically in Info.plist (NSBonjourServices), so it can't vary per trip;
  /// trips are instead segregated by the device-name tag + message filter.
  static const _serviceType = 'packpath';

  static String _tripTagFor(String tripId) {
    final hex = tripId.replaceAll('-', '').toLowerCase();
    return hex.length >= 8 ? hex.substring(0, 8) : hex.padRight(8, '0');
  }

  /// Bounded LRU of message ids already seen, so a message relayed around the
  /// cluster is delivered/forwarded exactly once.
  final LinkedHashSet<String> _seen = LinkedHashSet<String>();
  static const _seenCap = 500;

  @override
  Stream<MeshMessage> get inbound => _inbound.stream;

  @override
  Stream<int> get peerCount => _peerCount.stream;

  @override
  Future<void> start({required String tripId, required String selfId}) async {
    _tripId = tripId;
    _selfId = selfId;
    _tripTag = _tripTagFor(tripId);

    final service = NearbyService();
    _service = service;

    // Device name carries the trip tag so we only invite same-trip peers:
    // "<tripTag>~<userId>".
    final deviceName = '$_tripTag~$selfId';

    await service.init(
      serviceType: _serviceType,
      deviceName: deviceName,
      strategy: Strategy.P2P_Cluster,
      callback: (isRunning) async {
        if (!isRunning) return;
        await service.stopAdvertisingPeer();
        await service.stopBrowsingForPeers();
        await service.startAdvertisingPeer();
        await service.startBrowsingForPeers();
      },
    );

    _stateSub = service.stateChangedSubscription(callback: (devicesList) {
      for (final device in devicesList) {
        switch (device.state) {
          case SessionState.notConnected:
            _connected.remove(device.deviceId);
            // Only invite peers advertising our trip tag.
            if (_isSameTrip(device.deviceName)) {
              try {
                service.invitePeer(
                  deviceId: device.deviceId,
                  deviceName: device.deviceName,
                );
              } catch (_) {/* already inviting/connecting */}
            }
            break;
          case SessionState.connecting:
            break;
          case SessionState.connected:
            _connected.add(device.deviceId);
            break;
        }
      }
      _peerCount.add(_connected.length);
    });

    _dataSub = service.dataReceivedSubscription(callback: (data) {
      final raw = (data is Map) ? data['message'] as String? : null;
      if (raw == null) return;
      _handleIncoming(raw);
    });
  }

  bool _isSameTrip(String deviceName) {
    final tilde = deviceName.indexOf('~');
    final tag = tilde >= 0 ? deviceName.substring(0, tilde) : deviceName;
    return tag == _tripTag;
  }

  void _handleIncoming(String raw) {
    final msg = MeshMessage.tryParse(raw);
    if (msg == null) return;
    if (msg.tripId != _tripId) return; // not our trip
    if (_markSeen(msg.id)) return; // duplicate
    if (msg.senderId != _selfId) {
      _inbound.add(msg);
    }
    // Relay onward (decrement TTL) so devices out of direct range still get it.
    if (msg.ttl > 0) {
      _sendToPeers(msg.copyWith(ttl: msg.ttl - 1));
    }
  }

  /// Returns true if [id] was already seen (and records it otherwise).
  bool _markSeen(String id) {
    if (_seen.contains(id)) return true;
    _seen.add(id);
    if (_seen.length > _seenCap) {
      _seen.remove(_seen.first);
    }
    return false;
  }

  @override
  Future<void> broadcast(MeshMessage message) async {
    // Record our own id so a relayed copy coming back is ignored.
    _markSeen(message.id);
    await _sendToPeers(message);
  }

  Future<void> _sendToPeers(MeshMessage message) async {
    final service = _service;
    if (service == null) return;
    final payload = message.encode();
    for (final deviceId in _connected.toList()) {
      try {
        service.sendMessage(deviceId, payload);
      } catch (_) {/* peer dropped mid-send */}
    }
  }

  @override
  Future<void> stop() async {
    await _stateSub?.cancel();
    await _dataSub?.cancel();
    _stateSub = null;
    _dataSub = null;
    final service = _service;
    _service = null;
    if (service != null) {
      try {
        await service.stopAdvertisingPeer();
        await service.stopBrowsingForPeers();
      } catch (_) {}
    }
    _connected.clear();
    await _inbound.close();
    await _peerCount.close();
  }
}
