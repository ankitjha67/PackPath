import 'package:flutter/material.dart';

/// Icon, colour and label for each establishment category. Shared by the map
/// markers, the add-place form, the detail sheet and the directory.
class CategoryMeta {
  const CategoryMeta(this.key, this.label, this.icon, this.color);
  final String key;
  final String label;
  final IconData icon;
  final Color color;
}

const List<CategoryMeta> kCategories = [
  CategoryMeta('fuel', 'Fuel', Icons.local_gas_station, Color(0xFF3B82F6)),
  CategoryMeta('food', 'Food', Icons.restaurant, Color(0xFFF97316)),
  CategoryMeta('repair', 'Repair', Icons.build, Color(0xFFEF4444)),
  CategoryMeta('lodging', 'Stay', Icons.hotel, Color(0xFF8B5CF6)),
  CategoryMeta('viewpoint', 'Viewpoint', Icons.photo_camera, Color(0xFF10B981)),
  CategoryMeta('medical', 'Medical', Icons.local_hospital, Color(0xFFDC2626)),
  CategoryMeta('atm', 'ATM', Icons.local_atm, Color(0xFF0EA5E9)),
  CategoryMeta('parking', 'Parking', Icons.local_parking, Color(0xFF64748B)),
  CategoryMeta('water', 'Water', Icons.water_drop, Color(0xFF06B6D4)),
  CategoryMeta('shop', 'Shop', Icons.storefront, Color(0xFFEAB308)),
  CategoryMeta('other', 'Other', Icons.place, Color(0xFF94A3B8)),
];

CategoryMeta categoryMeta(String key) =>
    kCategories.firstWhere((c) => c.key == key, orElse: () => kCategories.last);
