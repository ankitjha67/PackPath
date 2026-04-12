import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'features/map/map_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // Load SharedPreferences once at startup so the map-provider notifier
  // can be created synchronously inside Riverpod.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        mapProviderControllerProvider.overrideWith(
          (ref) => MapProviderController(prefs),
        ),
      ],
      child: const PackPathApp(),
    ),
  );
}
