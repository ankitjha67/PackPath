import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';

/// Category metadata (icon/colour/label) is defined in establishment_icons.dart
/// so both the map markers and the directory stay consistent.

class EstablishmentDto {
  const EstablishmentDto({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    required this.avgStars,
    required this.ratingCount,
    this.address,
    this.phone,
    this.notes,
    this.distanceM,
    this.myStars,
  });

  final String id;
  final String name;
  final String category;
  final double lat;
  final double lng;
  final double avgStars;
  final int ratingCount;
  final String? address;
  final String? phone;
  final String? notes;
  final double? distanceM;
  final int? myStars;

  LatLng get latLng => LatLng(lat, lng);

  factory EstablishmentDto.fromJson(Map<String, dynamic> j) => EstablishmentDto(
        id: j['id'] as String,
        name: j['name'] as String,
        category: j['category'] as String? ?? 'other',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        avgStars: (j['avg_stars'] as num?)?.toDouble() ?? 0,
        ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
        address: j['address'] as String?,
        phone: j['phone'] as String?,
        notes: j['notes'] as String?,
        distanceM: (j['distance_m'] as num?)?.toDouble(),
        myStars: (j['my_stars'] as num?)?.toInt(),
      );
}

class EstablishmentRatingDto {
  const EstablishmentRatingDto({
    required this.id,
    required this.userId,
    required this.stars,
    this.reviewerName,
    this.reviewerAvatar,
    this.comment,
    this.tags,
  });

  final String id;
  final String userId;
  final int stars;
  final String? reviewerName;
  final String? reviewerAvatar;
  final String? comment;
  final String? tags;

  List<String> get tagList => (tags ?? '')
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  factory EstablishmentRatingDto.fromJson(Map<String, dynamic> j) =>
      EstablishmentRatingDto(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        stars: (j['stars'] as num).toInt(),
        reviewerName: j['reviewer_name'] as String?,
        reviewerAvatar: j['reviewer_avatar'] as String?,
        comment: j['comment'] as String?,
        tags: j['tags'] as String?,
      );
}

class EstablishmentsRepository {
  EstablishmentsRepository(this.dio);

  final Dio dio;

  Future<EstablishmentDto> create({
    required String name,
    required String category,
    required double lat,
    required double lng,
    String? address,
    String? phone,
    String? notes,
  }) async {
    final res = await dio.post('/establishments', data: {
      'name': name,
      'category': category,
      'lat': lat,
      'lng': lng,
      if (address != null) 'address': address,
      if (phone != null) 'phone': phone,
      if (notes != null) 'notes': notes,
    });
    return EstablishmentDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<EstablishmentDto>> nearby(
    double lat,
    double lng, {
    double radiusKm = 25,
    String? category,
  }) async {
    final res = await dio.get('/establishments', queryParameters: {
      'lat': lat,
      'lng': lng,
      'radius_km': radiusKm,
      if (category != null) 'category': category,
    });
    return (res.data as List)
        .map((e) => EstablishmentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EstablishmentDto> detail(String id) async {
    final res = await dio.get('/establishments/$id');
    return EstablishmentDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<EstablishmentDto> rate(
    String id,
    int stars, {
    String? comment,
    String? tags,
  }) async {
    final res = await dio.post('/establishments/$id/ratings', data: {
      'stars': stars,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
    });
    return EstablishmentDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<EstablishmentRatingDto>> ratings(String id) async {
    final res = await dio.get('/establishments/$id/ratings');
    return (res.data as List)
        .map((e) => EstablishmentRatingDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final establishmentsRepositoryProvider =
    FutureProvider<EstablishmentsRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return EstablishmentsRepository(dio);
});

/// Nearby places for the map/directory. Key is "lat|lng|category" (lat/lng
/// rounded by the caller) so it refetches as the map pans, not every frame.
final nearbyEstablishmentsProvider =
    FutureProvider.autoDispose.family<List<EstablishmentDto>, String>((
  ref,
  key,
) async {
  final parts = key.split('|');
  final lat = double.parse(parts[0]);
  final lng = double.parse(parts[1]);
  final category = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
  final repo = await ref.watch(establishmentsRepositoryProvider.future);
  return repo.nearby(lat, lng, category: category);
});

final establishmentRatingsProvider =
    FutureProvider.autoDispose.family<List<EstablishmentRatingDto>, String>((
  ref,
  id,
) async {
  final repo = await ref.watch(establishmentsRepositoryProvider.future);
  return repo.ratings(id);
});
