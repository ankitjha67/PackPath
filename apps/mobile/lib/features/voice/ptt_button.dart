import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kinetic_path_tokens.dart';
import 'voice_service.dart';

/// Big circular hold-to-talk button. Tap to connect to the trip's LiveKit
/// room (lazy), press-and-hold to publish your mic, release to mute.
class PttButton extends ConsumerStatefulWidget {
  const PttButton({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends ConsumerState<PttButton>
    with SingleTickerProviderStateMixin {
  bool _connecting = false;
  bool _connected = false;
  bool _talking = false;
  String? _error;

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final Animation<double> _pulse = Tween<double>(
    begin: 1.0,
    end: 1.06,
  ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

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
    if (!mounted) return;
    setState(() => _talking = on);
    if (on) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KineticPathTokens>()!;
    final scheme = Theme.of(context).colorScheme;
    final decoration = _talking
        ? BoxDecoration(
            color: scheme.error,
            shape: BoxShape.circle,
            boxShadow: tokens.floatingShadow,
          )
        : BoxDecoration(
            gradient: tokens.ctaGradient,
            shape: BoxShape.circle,
            boxShadow: tokens.floatingShadow,
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _error!,
              style: TextStyle(
                color: scheme.error,
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
          child: ScaleTransition(
            scale: _pulse,
            child: Container(
              width: 76,
              height: 76,
              decoration: decoration,
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
