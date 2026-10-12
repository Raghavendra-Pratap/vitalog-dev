import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-profile hide list for Home → Needs attention chips.
/// Hidden codes still appear under All tests / Trends.
class AttentionPrefs {
  AttentionPrefs({required this.hidden});

  final Set<String> hidden;

  static String _key(String profileId) => 'attention_hidden_$profileId';

  static Future<AttentionPrefs> load(String? profileId) async {
    if (profileId == null) return AttentionPrefs(hidden: {});
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(profileId));
    if (raw == null || raw.isEmpty) return AttentionPrefs(hidden: {});
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return AttentionPrefs(hidden: {});
      return AttentionPrefs(
        hidden: {
          for (final item in decoded)
            if (item is String && item.trim().isNotEmpty) item.trim(),
        },
      );
    } catch (_) {
      return AttentionPrefs(hidden: {});
    }
  }

  Future<void> save(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(profileId),
      jsonEncode(hidden.toList()..sort()),
    );
  }

  AttentionPrefs copyWith({Set<String>? hidden}) =>
      AttentionPrefs(hidden: hidden ?? this.hidden);
}
