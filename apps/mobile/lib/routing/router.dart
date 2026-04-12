import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/otp_screen.dart';
import '../features/trips/create_trip_screen.dart';
import '../features/trips/join_trip_screen.dart';
import '../features/trips/trip_list_screen.dart';
import '../features/trips/trip_map_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    routes: [
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
    ],
  );
});
