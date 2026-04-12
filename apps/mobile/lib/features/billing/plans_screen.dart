import 'package:flutter/material.dart';

/// PackPath plans. The actual Razorpay (IN) and Stripe (intl) flows
/// land in polish week — for now this screen lists the tiers and the
/// upgrade button is a stub.
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Plans')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PlanCard(
            name: 'Free',
            price: '₹0',
            highlights: const [
              'Up to 5 members per trip',
              '24-hour trip windows',
              '7 days of history',
              'Live group map',
              'Group chat',
              'Routes + ETAs',
            ],
            ctaLabel: 'Current plan',
            onCta: null,
          ),
          const SizedBox(height: 16),
          _PlanCard(
            name: 'Pro',
            price: '₹149 / \$2.99 / month',
            featured: true,
            highlights: const [
              'Unlimited members',
              '7-day trip windows',
              '90 days of history',
              'Push-to-talk voice',
              'Offline tile downloads',
              'Trip recap shareable',
            ],
            ctaLabel: 'Upgrade',
            onCta: () => _showSoon(context),
          ),
          const SizedBox(height: 16),
          _PlanCard(
            name: 'Family',
            price: '₹299 / \$5.99 / month',
            highlights: const [
              'Everything in Pro',
              '6 Pro seats to share',
              'Family billing in one place',
            ],
            ctaLabel: 'Upgrade',
            onCta: () => _showSoon(context),
          ),
          const SizedBox(height: 24),
          Text(
            'Razorpay handles India billing, Stripe handles global. '
            'You can cancel any time from this screen.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Billing flow lands in the polish week — stay tuned.'),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.price,
    required this.highlights,
    required this.ctaLabel,
    required this.onCta,
    this.featured = false,
  });

  final String name;
  final String price;
  final List<String> highlights;
  final String ctaLabel;
  final VoidCallback? onCta;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: featured ? 4 : 1,
      shape: RoundedRectangleBorder(
        side: featured
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(name, style: theme.textTheme.headlineSmall),
                if (featured) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'POPULAR',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(price, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final h in highlights)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(h)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onCta,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(ctaLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
