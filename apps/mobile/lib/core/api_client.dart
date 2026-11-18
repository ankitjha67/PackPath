import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_notifier.dart';
import 'server_config.dart';
import 'session.dart';
import 'token_storage.dart';

/// Provides a Dio configured with the API base URL, a bearer-token injector,
/// and a 401 handler that transparently refreshes the access token and retries
/// the original request. Refreshes are single-flighted so a burst of 401s
/// triggers exactly one `/auth/refresh` call; if refresh fails the session is
/// cleared and the router redirects to /login.
final apiClientProvider = FutureProvider<Dio>((ref) async {
  final storage = await ref.watch(tokenStorageProvider.future);
  // Rebuilds whenever the self-hosted server URL changes.
  final base = ref.watch(serverConfigProvider).httpBase;

  final dio = Dio(
    BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
    ),
  );

  // Bare client used only for the refresh call, so it never re-enters the
  // 401 interceptor (which would recurse).
  final refreshDio = Dio(BaseOptions(baseUrl: base));

  // Single-flight guard: while a refresh is in progress, concurrent callers
  // await the same future instead of each hitting the endpoint.
  Future<bool>? inflight;

  Future<bool> refreshTokens() {
    inflight ??= () async {
      // Capture the session this refresh belongs to; if the user logs out or
      // a different account logs in mid-flight, we must not write these tokens
      // into the new session.
      final startEpoch = ref.read(sessionEpochProvider);
      try {
        final rt = storage.refreshToken;
        if (rt == null) return false;
        final r = await refreshDio.post<Map<String, dynamic>>(
          '/auth/refresh',
          data: {'refresh_token': rt},
        );
        final data = r.data!;
        if (ref.read(sessionEpochProvider) != startEpoch) return false;
        // The validity check is re-evaluated inside the serialized write, so a
        // logout/switch that lands while this save is queued still wins.
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

  Future<void> forceLogout() async {
    // Bump the epoch before the async clear so a concurrent refresh's save is
    // rejected instead of racing the clear.
    ref.read(sessionEpochProvider.notifier).state++;
    await storage.clear();
    ref.read(authNotifierProvider).notifyChanged();
  }

  dio.interceptors.add(
    QueuedInterceptorsWrapper(
      onRequest: (options, handler) {
        // Stamp the originating session so a delayed 401 can't mutate the
        // auth state of a later session (logout / account switch).
        options.extra['__pp_epoch'] = ref.read(sessionEpochProvider);
        final token = storage.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        final opts = e.requestOptions;
        final is401 = e.response?.statusCode == 401;
        final isAuthRoute = opts.path.contains('/auth/refresh') ||
            opts.path.contains('/auth/otp');
        final alreadyRetried = opts.extra['__pp_retried'] == true;

        if (!is401 || isAuthRoute || alreadyRetried) {
          return handler.next(e);
        }

        // If the session changed since this request started, it's stale —
        // fail it without refreshing, retrying, or logging anyone out.
        final reqEpoch = opts.extra['__pp_epoch'];
        if (reqEpoch != ref.read(sessionEpochProvider)) {
          return handler.next(e);
        }

        final refreshed = await refreshTokens();
        if (!refreshed) {
          // Only clear the session if we're still in the one that 401'd.
          if (reqEpoch == ref.read(sessionEpochProvider)) {
            await forceLogout();
          }
          return handler.next(e);
        }

        // The session may have changed while refreshing — don't retry with
        // another account's credentials.
        if (reqEpoch != ref.read(sessionEpochProvider)) {
          return handler.next(e);
        }

        // Retry once with the fresh token.
        opts.extra['__pp_retried'] = true;
        opts.headers['Authorization'] = 'Bearer ${storage.accessToken}';
        try {
          final clone = await dio.fetch<dynamic>(opts);
          return handler.resolve(clone);
        } on DioException catch (retryErr) {
          if (retryErr.response?.statusCode == 401 &&
              reqEpoch == ref.read(sessionEpochProvider)) {
            await forceLogout();
          }
          return handler.next(retryErr);
        }
      },
    ),
  );

  return dio;
});
