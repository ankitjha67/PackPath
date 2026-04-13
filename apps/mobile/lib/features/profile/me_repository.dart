import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Current user as returned by `GET /me`.
///
/// Backend schema (see `apps/backend/app/schemas/user.py`):
/// - id: uuid
/// - phone: string
/// - display_name: string | null
/// - avatar_url: string | null
class MeDto {
  const MeDto({
    required this.id,
    required this.phone,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String phone;
  final String? displayName;
  final String? avatarUrl;

  factory MeDto.fromJson(Map<String, dynamic> json) => MeDto(
        id: json['id'] as String,
        phone: json['phone'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );

  MeDto copyWith({String? displayName, String? avatarUrl}) => MeDto(
        id: id,
        phone: phone,
        displayName: displayName ?? this.displayName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
      );
}

class MeRepository {
  MeRepository(this.dio);

  final Dio dio;

  Future<MeDto> fetch() async {
    final response = await dio.get<Map<String, dynamic>>('/me');
    return MeDto.fromJson(response.data!);
  }

  Future<MeDto> update({String? displayName, String? avatarUrl}) async {
    final response = await dio.patch<Map<String, dynamic>>(
      '/me',
      data: {
        if (displayName != null) 'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      },
    );
    return MeDto.fromJson(response.data!);
  }
}

final meRepositoryProvider = FutureProvider<MeRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return MeRepository(dio);
});

/// Current user. Watch this from anywhere that needs `GET /me`.
final meProvider = FutureProvider<MeDto>((ref) async {
  final repo = await ref.watch(meRepositoryProvider.future);
  return repo.fetch();
});
