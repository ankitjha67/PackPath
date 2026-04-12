import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voice_service.dart';

/// Big circular hold-to-talk button. Tap to connect to the trip's LiveKit
/// room (lazy), press-and-hold to publish your mic, release to mute.
class PttButton extends ConsumerStatefulWidget {
  const PttButton({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends ConsumerState<PttButton> {
  bool _connecting = false;
  bool _connected = false;
  bool _talking = false;
  String? _error;

  Future<void> _ensureConnected() async {
    if (_connected || _connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final svc = await ref.read(voiceServiceProvider.future);
      await svc.connect(widget.tripId);
      setState(() => _connected = true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _setTalking(bool on) async {
    final svc = await ref.read(voiceServiceProvider.future);
    await svc.setTalking(on);
    if (mounted) setState(() => _talking = on);
  }

  @override
  Widget build(BuildContext context) {
    final color = _talking
        ? Colors.redAccent
        : (_connected ? Colors.green : Colors.blueGrey);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        GestureDetector(
          onTap: _ensureConnected,
          onLongPressStart: (_) async {
            await _ensureConnected();
            if (_connected) await _setTalking(true);
          },
          onLongPressEnd: (_) async {
            if (_connected) await _setTalking(false);
          },
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(blurRadius: 8, color: Colors.black26),
              ],
            ),
            child: _connecting
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.mic, color: Colors.white, size: 36),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _talking
              ? 'Talking…'
              : (_connected ? 'Hold to talk' : 'Tap to join voice'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
