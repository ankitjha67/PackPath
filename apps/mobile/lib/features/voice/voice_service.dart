import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/api_client.dart';

/// Single LiveKit room per trip, joined as a publishing participant in
/// "muted by default" mode. The PTT button toggles the local audio
/// publication on while held and off when released — that's
/// walkie-talkie semantics on top of an always-connected SFU.
class VoiceService {
  VoiceService(this._dio);

  final Dio _dio;

  Room? _room;

  bool get isConnected => _room != null;

  Future<void> connect(String tripId) async {
    if (_room != null) return;

    final response = await _dio.post('/trips/$tripId/voice/token');
    final data = response.data as Map<String, dynamic>;
    final url = data['url'] as String;
    final token = data['token'] as String;

    final room = Room();
    await room.connect(
      url,
      token,
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
      ),
    );
    // Start with mic muted; we publish on demand via [setTalking].
    await room.localParticipant?.setMicrophoneEnabled(false);
    _room = room;
  }

  Future<void> setTalking(bool on) async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    await lp.setMicrophoneEnabled(on);
  }

  Iterable<RemoteParticipant> get speakers =>
      _room?.remoteParticipants.values.where(
        (p) => p.audioTrackPublications.any(
          (t) => !(t.muted),
        ),
      ) ??
      const Iterable.empty();

  Future<void> disconnect() async {
    final r = _room;
    _room = null;
    if (r != null) {
      await r.disconnect();
      await r.dispose();
    }
  }
}

final voiceServiceProvider = FutureProvider<VoiceService>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  final svc = VoiceService(dio);
  ref.onDispose(svc.disconnect);
  return svc;
});
