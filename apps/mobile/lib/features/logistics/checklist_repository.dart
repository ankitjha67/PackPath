import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Phase 6 — the shared, live trip checklist (packing / supplies / to-dos).
/// Writes go through these REST calls; the live list is kept in LiveTripState
/// via checklist_* WebSocket frames.

class ChecklistCategory {
  const ChecklistCategory(this.id, this.label, this.icon, this.color);
  final String id;
  final String label;
  final IconData icon;
  final Color color;
}

const kChecklistCategories = <ChecklistCategory>[
  ChecklistCategory('packing', 'Packing', Icons.luggage, Color(0xFF6366F1)),
  ChecklistCategory(
    'supplies',
    'Supplies',
    Icons.shopping_bag,
    Color(0xFF0EA5E9),
  ),
  ChecklistCategory('food', 'Food', Icons.restaurant, Color(0xFFF59E0B)),
  ChecklistCategory('gear', 'Gear', Icons.backpack, Color(0xFF10B981)),
  ChecklistCategory('todo', 'To-do', Icons.checklist, Color(0xFFEC4899)),
  ChecklistCategory('other', 'Other', Icons.category, Color(0xFF64748B)),
];

ChecklistCategory checklistCategoryFor(String id) => kChecklistCategories
    .firstWhere((c) => c.id == id, orElse: () => kChecklistCategories.last);

class ChecklistItemDto {
  const ChecklistItemDto({
    required this.id,
    required this.title,
    required this.category,
    required this.qty,
    required this.done,
    this.assignedTo,
    this.assigneeName,
  });

  final String id;
  final String title;
  final String category;
  final int qty;
  final bool done;
  final String? assignedTo;
  final String? assigneeName;

  factory ChecklistItemDto.fromJson(Map<String, dynamic> j) => ChecklistItemDto(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        category: j['category'] as String? ?? 'other',
        qty: (j['qty'] as num?)?.toInt() ?? 1,
        done: j['done'] as bool? ?? false,
        assignedTo: j['assigned_to'] as String?,
        assigneeName: j['assignee_name'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'qty': qty,
        'done': done,
        'assigned_to': assignedTo,
        'assignee_name': assigneeName,
      };
}

class ChecklistRepository {
  ChecklistRepository(this.dio, this.tripId);

  final Dio dio;
  final String tripId;

  String get _base => '/trips/$tripId/checklist';

  Future<List<ChecklistItemDto>> list() async {
    final res = await dio.get(_base);
    return (res.data as List)
        .map((e) => ChecklistItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ChecklistItemDto> add({
    required String title,
    required String category,
    int qty = 1,
    bool assignToMe = false,
  }) async {
    final res = await dio.post(
      _base,
      data: {
        'title': title,
        'category': category,
        'qty': qty,
        'assign_to_me': assignToMe,
      },
    );
    return ChecklistItemDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<ChecklistItemDto> claim(String id) async {
    final res = await dio.post('$_base/$id/claim');
    return ChecklistItemDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<ChecklistItemDto> toggle(String id) async {
    final res = await dio.post('$_base/$id/toggle');
    return ChecklistItemDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> remove(String id) async {
    await dio.delete('$_base/$id');
  }
}

final checklistRepositoryProvider =
    FutureProvider.autoDispose.family<ChecklistRepository, String>((
  ref,
  tripId,
) async {
  final dio = await ref.watch(apiClientProvider.future);
  return ChecklistRepository(dio, tripId);
});
