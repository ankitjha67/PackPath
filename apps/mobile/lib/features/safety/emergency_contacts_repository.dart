import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';

class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
  });
  final String id;
  final String name;
  final String phone;

  factory EmergencyContact.fromJson(Map<String, dynamic> j) => EmergencyContact(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String,
      );
}

class EmergencyContactsRepository {
  EmergencyContactsRepository(this.dio);
  final Dio dio;

  Future<List<EmergencyContact>> list() async {
    final res = await dio.get('/me/emergency-contacts');
    return (res.data as List)
        .map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EmergencyContact> add(String name, String phone) async {
    final res = await dio.post(
      '/me/emergency-contacts',
      data: {'name': name, 'phone': phone},
    );
    return EmergencyContact.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> delete(String id) => dio.delete('/me/emergency-contacts/$id');
}

final emergencyContactsRepositoryProvider =
    FutureProvider<EmergencyContactsRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return EmergencyContactsRepository(dio);
});

final emergencyContactsProvider =
    FutureProvider.autoDispose<List<EmergencyContact>>((ref) async {
  ref.watch(sessionEpochProvider);
  final repo = await ref.watch(emergencyContactsRepositoryProvider.future);
  return repo.list();
});
