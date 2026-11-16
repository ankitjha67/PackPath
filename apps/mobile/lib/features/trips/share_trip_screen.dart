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
                    'INVITE WAYFINDERS',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          letterSpacing: 1.5,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                  ),
                  const SizedBox(height: 4),
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
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Text('PACK ID',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  letterSpacing: 1.5,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                )),
                        const SizedBox(height: 4),
                        SelectableText(
                          trip.joinCode,
                          style: const TextStyle(
                            fontSize: 36,
                            letterSpacing: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share invite link'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                          text: 'Join my PackPath trip "${trip.name}" — '
                              'code ${trip.joinCode} ($deepLink)'));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Invite copied — paste anywhere.')),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy code only'),
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
