import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import 'auth_notifier.dart';
import 'session.dart';
import 'token_storage.dart';

/// Provides a Dio configured with the API base URL, a bearer-token injector,
/// and a 401 handler that transparently refreshes the access token and retries
/// the original request. Refreshes are single-flighted so a burst of 401s
/// triggers exactly one `/auth/refresh` call; if refresh fails the session is
/// cleared and the router redirects to /login.
final apiClientProvider = FutureProvider<Dio>((ref) async {
  final storage = await ref.watch(tokenStorageProvider.future);

  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
    ),
  );

  // Bare client used only for the refresh call, so it never re-enters the
  // 401 interceptor (which would recurse).
  final refreshDio = Dio(BaseOptions(baseUrl: Env.apiBaseUrl));

  // Single-flight guard: while a refresh is in progress, concurrent callers
  // await the same future instead of each hitting the endpoint.
  Future<bool>? inflight;

  Future<bool> refreshTokens() {
    inflight ??= () async {
      try {
        final rt = storage.refreshToken;
        if (rt == null) return false;
        final r = await refreshDio.post<Map<String, dynamic>>(
          '/auth/refresh',
          data: {'refresh_token': rt},
        );
        final data = r.data!;
        await storage.save(
          access: data['access_token'] as String,
          refresh: data['refresh_token'] as String,
        );
        return true;
      } catch (_) {
        return false;
      } finally {
        inflight = null;
      }
    }();
    return inflight!;
  }

  Future<void> forceLogout() async {
    await storage.clear();
    ref.read(sessionEpochProvider.notifier).state++;
    ref.read(authNotifierProvider).notifyChanged();
  }

  dio.interceptors.add(
    QueuedInterceptorsWrapper(
      onRequest: (options, handler) {
        final token = storage.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        final opts = e.requestOptions;
        final is401 = e.response?.statusCode == 401;
        final isAuthRoute =
            opts.path.contains('/auth/refresh') ||
            opts.path.contains('/auth/otp');
        final alreadyRetried = opts.extra['__pp_retried'] == true;

        if (!is401 || isAuthRoute || alreadyRetried) {
          return handler.next(e);
        }

        final refreshed = await refreshTokens();
        if (!refreshed) {
          await forceLogout();
          return handler.next(e);
        }

        // Retry once with the fresh token.
        opts.extra['__pp_retried'] = true;
        opts.headers['Authorization'] = 'Bearer ${storage.accessToken}';
        try {
          final clone = await dio.fetch<dynamic>(opts);
          return handler.resolve(clone);
        } on DioException catch (retryErr) {
          if (retryErr.response?.statusCode == 401) {
            await forceLogout();
          }
          return handler.next(retryErr);
        }
      },
    ),
  );

  return dio;
});
