import 'package:flutter/material.dart';

/// A circular user avatar.
///
/// Renders the server-provided [avatarUrl] (a deterministic DiceBear image)
/// and, while it loads or if it fails (offline, blocked network), falls back
/// to a colored circle with the user's initials — so there is always *some*
/// recognizable, stable avatar. Color is derived from [name] so the same user
/// is always the same hue.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.radius = 18,
  });

  final String name;
  final String? avatarUrl;
  final double radius;

  // A small, legible, dark-mode-friendly palette. Index is picked from the
  // name hash so it's deterministic per user.
  static const _palette = <Color>[
    Color(0xFFEF6C57), // coral
    Color(0xFF4F9DDE), // blue
    Color(0xFF59B36B), // green
    Color(0xFFC06CD0), // purple
    Color(0xFFE0A33E), // amber
    Color(0xFF3FB6B0), // teal
    Color(0xFFE2698F), // pink
    Color(0xFF8E7CF0), // indigo
  ];

  Color get _color {
    var hash = 0;
    for (final code in name.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  String get _initials {
    // "Rustic_Marmot_6405" -> "RM"; plain names -> first two letters.
    final words = name
        .split(RegExp(r'[\s_]+'))
        .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(w[0]))
        .toList();
    if (words.isEmpty) {
      final letters = name.replaceAll(RegExp(r'[^A-Za-z]'), '');
      return letters.isEmpty
          ? '?'
          : letters.substring(0, letters.length.clamp(0, 2)).toUpperCase();
    }
    if (words.length == 1) {
      return words.first.substring(0, words.first.length.clamp(0, 2)).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  Widget _fallback() {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _color,
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    if (url == null || url.isEmpty) return _fallback();
    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          // Tint DiceBott's transparent background so it sits on the avatar
          // color rather than the page.
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _fallback(),
          errorBuilder: (context, error, stack) => _fallback(),
        ),
      ),
    );
  }
}
