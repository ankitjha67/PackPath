import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Initialises Firebase, requests notification permission and registers
/// the FCM token with the PackPath backend so chat messages from offline
/// trips can land as system pushes.
///
/// Safe to call multiple times — Firebase init is guarded and the
/// backend upserts on token, not user.
class PushService {
  PushService(this._dio);

  final Dio _dio;
  bool _ready = false;

  Future<void> initAndRegister() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (e) {
      // No google-services.json / GoogleService-Info.plist yet — silently
      // skip so the rest of the app keeps working in dev.
      debugPrint('Firebase init skipped: $e');
      return;
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await messaging.getToken();
    if (token == null) return;

    final platform = kIsWeb
        ? 'web'
        : (Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web'));
    try {
      await _dio.post(
        '/devices',
        data: {'fcm_token': token, 'platform': platform},
      );
      _ready = true;
    } catch (e) {
      debugPrint('Device registration failed: $e');
    }

    // Re-register on token rotation.
    messaging.onTokenRefresh.listen((newToken) {
      _dio.post(
        '/devices',
        data: {'fcm_token': newToken, 'platform': platform},
      );
    });
  }

  bool get isReady => _ready;
}

final pushServiceProvider = FutureProvider<PushService>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return PushService(dio);
});
