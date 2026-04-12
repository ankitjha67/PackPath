import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/analytics/personal_stats_screen.dart';
import '../features/audit/audit_log_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/otp_screen.dart';
import '../features/billing/plans_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/expenses/expenses_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/privacy/privacy_screen.dart';
import '../features/recap/recap_screen.dart';
import '../features/trips/create_trip_screen.dart';
import '../features/trips/join_trip_screen.dart';
import '../features/trips/share_trip_screen.dart';
import '../features/trips/trip_list_screen.dart';
import '../features/trips/trip_map_screen.dart';

/// Whether the current user has already finished onboarding. Override
/// in `main.dart` from the persisted SharedPreferences flag.
final hasSeenOnboardingProvider = Provider<bool>(
  (ref) => throw UnimplementedError(
    'hasSeenOnboardingProvider must be overridden in main.dart',
  ),
);

final routerProvider = Provider<GoRouter>((ref) {
  final hasSeenOnboarding = ref.watch(hasSeenOnboardingProvider);
  return GoRouter(
    initialLocation: hasSeenOnboarding ? '/login' : '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/otp',
        builder: (context, state) {
          final phone = state.uri.queryParameters['phone'] ?? '';
          final debug = state.uri.queryParameters['debug'];
          return OtpScreen(phone: phone, debugOtp: debug);
        },
      ),
      GoRoute(path: '/trips', builder: (_, __) => const TripListScreen()),
      GoRoute(path: '/trips/new', builder: (_, __) => const CreateTripScreen()),
      GoRoute(path: '/trips/join', builder: (_, __) => const JoinTripScreen()),
      GoRoute(
        path: '/trips/:id',
        builder: (context, state) =>
            TripMapScreen(tripId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/trips/:id/chat',
        builder: (context, state) =>
            ChatScreen(tripId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/trips/:id/share',
        builder: (context, state) =>
            ShareTripScreen(tripId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/trips/:id/recap',
        builder: (context, state) =>
            TripRecapScreen(tripId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/trips/:id/expenses',
        builder: (context, state) =>
            ExpensesScreen(tripId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/privacy', builder: (_, __) => const PrivacyScreen()),
      GoRoute(path: '/audit', builder: (_, __) => const AuditLogScreen()),
      GoRoute(
        path: '/me/stats',
        builder: (_, __) => const PersonalStatsScreen(),
      ),
      GoRoute(path: '/plans', builder: (_, __) => const PlansScreen()),
    ],
  );
});
