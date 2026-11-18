import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class TripDocumentDto {
  const TripDocumentDto({
    required this.id,
    required this.title,
    required this.kind,
    this.url,
    this.body,
  });

  final String id;
  final String title;
  final String kind; // 'link' | 'note'
  final String? url;
  final String? body;

  factory TripDocumentDto.fromJson(Map<String, dynamic> json) =>
      TripDocumentDto(
        id: json['id'] as String,
        title: json['title'] as String,
        kind: json['kind'] as String,
        url: json['url'] as String?,
        body: json['body'] as String?,
      );
}

class DocumentsRepository {
  DocumentsRepository(this.dio);
  final Dio dio;

  Future<List<TripDocumentDto>> list(String tripId) async {
    final res = await dio.get('/trips/$tripId/documents');
    return (res.data as List)
        .map((e) => TripDocumentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addLink({
    required String tripId,
    required String title,
    required String url,
  }) async {
    await dio.post(
      '/trips/$tripId/documents',
      data: {'title': title, 'kind': 'link', 'url': url},
    );
  }

  Future<void> addNote({
    required String tripId,
    required String title,
    required String body,
  }) async {
    await dio.post(
      '/trips/$tripId/documents',
      data: {'title': title, 'kind': 'note', 'body': body},
    );
  }

  Future<void> delete({
    required String tripId,
    required String documentId,
  }) async {
    await dio.delete('/trips/$tripId/documents/$documentId');
  }
}

final documentsRepositoryProvider =
    FutureProvider<DocumentsRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return DocumentsRepository(dio);
});

final tripDocumentsProvider =
    FutureProvider.family<List<TripDocumentDto>, String>((ref, tripId) async {
  final repo = await ref.watch(documentsRepositoryProvider.future);
  return repo.list(tripId);
});
