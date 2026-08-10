import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/auth_notifier.dart';
import 'core/token_storage.dart';
import 'features/map/map_providers.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'routing/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // Load SharedPreferences once at startup so the map-provider notifier
  // and the onboarding-seen gate can be created synchronously inside
  // Riverpod.
  final prefs = await SharedPreferences.getInstance();
  final hasSeenOnboarding =
      prefs.getBool(OnboardingScreen.onboardingSeenKey) ?? false;

  // Build token storage eagerly so the router can read auth state
  // synchronously (via authNotifierProvider) on the very first frame.
  final storage = await TokenStorage.open(prefs);
  final authNotifier = AuthNotifier(storage);

  runApp(
    ProviderScope(
      overrides: [
        mapProviderControllerProvider.overrideWith(
          (ref) => MapProviderController(prefs),
        ),
        hasSeenOnboardingProvider.overrideWithValue(hasSeenOnboarding),
        tokenStorageProvider.overrideWith((ref) async => storage),
        authNotifierProvider.overrideWithValue(authNotifier),
      ],
      child: const PackPathApp(),
    ),
  );
}
