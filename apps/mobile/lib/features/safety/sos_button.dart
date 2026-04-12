import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../map/live_trip_controller.dart';

/// Big red SOS button. Tap once arms; second tap inside 3 s fires.
/// Two-tap pattern keeps a stray pocket touch from flooding the pack.
class SosButton extends ConsumerStatefulWidget {
  const SosButton({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<SosButton> {
  bool _armed = false;

  Future<void> _press() async {
    if (!_armed) {
      setState(() => _armed = true);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    final controller = ref.read(liveTripProvider(widget.tripId).notifier);
    controller.sendSafety(kind: 'sos', details: {'reason': 'manual'});
    setState(() => _armed = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('SOS sent — your pack has been alerted.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _press,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: _armed ? Colors.red : Colors.red.shade700,
          shape: BoxShape.circle,
          border: Border.all(
            color: _armed ? Colors.yellowAccent : Colors.white,
            width: 3,
          ),
          boxShadow: const [
            BoxShadow(blurRadius: 6, color: Colors.black38),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          _armed ? 'TAP\nAGAIN' : 'SOS',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
