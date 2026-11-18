import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/auth_notifier.dart';
import '../../core/session.dart';
import '../../core/token_storage.dart';

class OtpRequestResult {
  const OtpRequestResult({required this.sent, this.debugOtp});
  final bool sent;
  final String? debugOtp;
}

class AuthRepository {
  AuthRepository({required this.dio, required this.storage, required this.ref});

  final Dio dio;
  final TokenStorage storage;
  final Ref ref;

  void _bumpEpoch() => ref.read(sessionEpochProvider.notifier).state++;
  void _notifyAuthChanged() => ref.read(authNotifierProvider).notifyChanged();

  Future<OtpRequestResult> requestOtp(String phone) async {
    final response = await dio.post(
      '/auth/otp/request',
      data: {'phone': phone},
    );
    final data = response.data as Map<String, dynamic>;
    return OtpRequestResult(
      sent: data['sent'] as bool,
      debugOtp: data['debug_otp'] as String?,
    );
  }

  Future<void> verifyOtp({required String phone, required String code}) async {
    final response = await dio.post(
      '/auth/otp/verify',
      data: {'phone': phone, 'code': code},
    );
    final data = response.data as Map<String, dynamic>;
    // Advance the epoch before persisting so a lingering refresh from a
    // previous account is rejected by TokenStorage.save's validity check
    // instead of overwriting the tokens we're about to write.
    _bumpEpoch();
    await storage.save(
      access: data['access_token'] as String,
      refresh: data['refresh_token'] as String,
    );
    _notifyAuthChanged();
  }

  Future<void> logout() async {
    // Invalidate the session epoch before the async clear so any in-flight
    // token refresh's save is rejected rather than restoring these tokens.
    _bumpEpoch();
    await storage.clear();
    _notifyAuthChanged();
  }
}

final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  final storage = await ref.watch(tokenStorageProvider.future);
  return AuthRepository(dio: dio, storage: storage, ref: ref);
});
