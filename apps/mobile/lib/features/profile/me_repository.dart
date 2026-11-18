import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';

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
    this.bio,
    this.country,
  });

  final String id;
  final String phone;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final String? country;

  factory MeDto.fromJson(Map<String, dynamic> json) => MeDto(
        id: json['id'] as String,
        phone: json['phone'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        bio: json['bio'] as String?,
        country: json['country'] as String?,
      );

  MeDto copyWith({
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? country,
  }) =>
      MeDto(
        id: id,
        phone: phone,
        displayName: displayName ?? this.displayName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        bio: bio ?? this.bio,
        country: country ?? this.country,
      );
}

class MeRepository {
  MeRepository(this.dio);

  final Dio dio;

  Future<MeDto> fetch() async {
    final response = await dio.get<Map<String, dynamic>>('/me');
    return MeDto.fromJson(response.data!);
  }

  Future<MeDto> update({
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? country,
  }) async {
    final response = await dio.patch<Map<String, dynamic>>(
      '/me',
      data: {
        if (displayName != null) 'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (bio != null) 'bio': bio,
        if (country != null) 'country': country,
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
  ref.watch(sessionEpochProvider);
  final repo = await ref.watch(meRepositoryProvider.future);
  return repo.fetch();
});
