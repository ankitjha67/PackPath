import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'trips_repository.dart';

/// Show the trip's join code as both text and a QR. The deep-link target
/// (`packpath://join/<code>`) will be wired in routing once the polish
/// week ships universal links.
class ShareTripScreen extends ConsumerWidget {
  const ShareTripScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripDetailProvider(tripId));
    return Scaffold(
      appBar: AppBar(title: const Text('Invite to trip')),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (trip) {
          final deepLink = 'packpath://join/${trip.joinCode}';
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    trip.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: deepLink,
                        size: 240,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: SelectableText(
                      trip.joinCode,
                      style: const TextStyle(
                        fontSize: 36,
                        letterSpacing: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy join code'),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: trip.joinCode),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied')),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Anyone in your pack can scan the QR or enter '
                    '${trip.joinCode} from the Join Trip screen.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
