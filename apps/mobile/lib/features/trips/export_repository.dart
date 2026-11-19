import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api_client.dart';

/// Route & calendar exports (GPX / ICS) for a trip.
class ExportRepository {
  ExportRepository(this.dio);
  final Dio dio;

  /// Download a trip export ('gpx' or 'ics') to a local file and return its
  /// path. Uses the authorized Dio client so the Bearer token is attached.
  Future<String> downloadExport(String tripId, String kind) async {
    final path =
        kind == 'ics' ? '/trips/$tripId/trip.ics' : '/trips/$tripId/export.gpx';
    final res = await dio.get<String>(
      path,
      options: Options(responseType: ResponseType.plain),
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/packpath-$tripId.$kind');
    await file.writeAsString(res.data ?? '');
    return file.path;
  }
}

final exportRepositoryProvider = FutureProvider<ExportRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return ExportRepository(dio);
});
