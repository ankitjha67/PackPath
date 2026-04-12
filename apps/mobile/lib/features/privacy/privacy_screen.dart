import 'package:flutter/material.dart';

/// Privacy dashboard. The whole point of this screen is to be specific
/// and concrete — vague trust statements are worth less than a single
/// bulleted list of "here is exactly what we store".
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            "PackPath's promise",
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'We never sell your location data. We never share it with '
            'advertisers. We never give it to data brokers. Sharing is '
            'scoped to the trip you joined and ends with the trip.',
          ),
          const SizedBox(height: 24),
          _section(
            context,
            icon: Icons.location_on_outlined,
            title: 'What we collect during a trip',
            bullets: const [
              'Latitude / longitude / heading / speed every 5–30 s',
              'Battery percentage (so the pack can see who needs to charge)',
              'Chat messages you send to the trip',
              'Waypoints you add',
            ],
          ),
          _section(
            context,
            icon: Icons.folder_outlined,
            title: 'What we store',
            bullets: const [
              'Phone number (for login)',
              'Display name and avatar (only if you set them)',
              'Location history for the duration of the trip + 7 days '
                  '(90 days on PackPath Pro)',
              'Chat history for the duration of the trip + 7 days '
                  '(90 days on PackPath Pro)',
            ],
          ),
          _section(
            context,
            icon: Icons.visibility_off_outlined,
            title: 'Ghost mode',
            bullets: const [
              'Hides your location from the pack instantly',
              'You still see everyone else and the chat',
              'Toggle from the trip menu — no need to leave the trip',
            ],
          ),
          _section(
            context,
            icon: Icons.do_not_disturb_on_outlined,
            title: 'When sharing stops',
            bullets: const [
              'When the owner ends the trip',
              'When you leave the trip',
              'When the trip end time passes',
              'Immediately when you toggle Ghost mode',
            ],
          ),
          _section(
            context,
            icon: Icons.delete_outline,
            title: 'Deleting your data',
            bullets: const [
              'Email privacy@packpath.app from your registered number to '
                  'wipe everything within 30 days',
              'Account deletion removes all trips you own and all '
                  'location and chat history',
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Last updated April 2026',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<String> bullets,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          for (final b in bullets)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(b)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
