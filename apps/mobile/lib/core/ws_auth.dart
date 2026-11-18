import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'server_config.dart';
import 'session.dart';
import 'token_storage.dart';

/// Returns the current access token, transparently refreshing it via
/// `/auth/refresh` when it is expired (or about to expire).
///
/// The WebSocket passes its token as a query param at connect time, so a
/// long-lived socket that drops and reconnects after the 15-minute access-TTL
/// would otherwise reconnect forever with a dead token (403). This keeps the
/// token fresh on every (re)connect so queued frames — including SOS/crash —
/// actually deliver once connectivity returns. Returns null only when refresh
/// fails (e.g. the refresh token itself expired → the user must re-auth).
typedef FreshTokenFn = Future<String?> Function();

bool _isExpired(String jwt, {int skewSeconds = 30}) {
  try {
    final parts = jwt.split('.');
    if (parts.length != 3) return true;
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    final map =
        jsonDecode(utf8.decode(base64.decode(payload))) as Map<String, dynamic>;
    final exp = map['exp'];
    if (exp is! int) return true;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowSec + skewSeconds >= exp;
  } catch (_) {
    return true;
  }
}

final freshAccessTokenProvider = Provider<FreshTokenFn>((ref) {
  final storage = ref.watch(tokenStorageSyncProvider);
  // Bare client: the refresh endpoint is unauthenticated and must not go
  // through the 401-refresh interceptor.
  final dio =
      Dio(BaseOptions(baseUrl: ref.watch(serverConfigProvider).httpBase));

  Future<bool>? inflight;
  Future<bool> refresh() {
    inflight ??= () async {
      // Bind this refresh to the session it started in so a save that lands
      // after a logout or account switch can't restore the previous account's
      // tokens (the WS reconnects independently of the Dio interceptor).
      final startEpoch = ref.read(sessionEpochProvider);
      try {
        final rt = storage.refreshToken;
        if (rt == null) return false;
        final r = await dio.post<Map<String, dynamic>>(
          '/auth/refresh',
          data: {'refresh_token': rt},
        );
        final data = r.data!;
        if (ref.read(sessionEpochProvider) != startEpoch) return false;
        await storage.save(
          access: data['access_token'] as String,
          refresh: data['refresh_token'] as String,
          isValid: () => ref.read(sessionEpochProvider) == startEpoch,
        );
        return ref.read(sessionEpochProvider) == startEpoch;
      } catch (_) {
        return false;
      } finally {
        inflight = null;
      }
    }();
    return inflight!;
  }

  return () async {
    final current = storage.accessToken;
    if (current != null && current.isNotEmpty && !_isExpired(current)) {
      return current;
    }
    final ok = await refresh();
    return ok ? storage.accessToken : null;
  };
});
