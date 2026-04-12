import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/token_storage.dart';

class OtpRequestResult {
  const OtpRequestResult({required this.sent, this.debugOtp});
  final bool sent;
  final String? debugOtp;
}

class AuthRepository {
  AuthRepository({required this.dio, required this.storage});

  final Dio dio;
  final TokenStorage storage;

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
    await storage.save(
      access: data['access_token'] as String,
      refresh: data['refresh_token'] as String,
    );
  }

  Future<void> logout() => storage.clear();
}

final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  final storage = await ref.watch(tokenStorageProvider.future);
  return AuthRepository(dio: dio, storage: storage);
});
