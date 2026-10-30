import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-profile order + visibility for the home "Your body" list.
class BodyPanelPrefs {
  BodyPanelPrefs({
    required this.order,
    required this.hidden,
  });

  /// All known system codes in display order (including hidden).
  final List<String> order;

  /// Codes the user turned off.
  final Set<String> hidden;

  static const _skip = {'endocrine'};

  /// Systems that have a dedicated silhouette on the v2 body map.
  /// Source: assets/brand/vitalog-body-map-organs.html
  /// Home "Your body" list — keep short so it fits beside the figure.
  static const homeSpotlightCodes = [
    'blood',
    'heart',
    'liver',
    'kidney',
    'thyroid',
    'pancreas', // metabolic / blood sugar in catalogue
  ];

  static const glyphCodes = {
    'general',
    'lungs',
    'bones',
    'blood',
    'heart',
    'liver',
    'immune',
    'pancreas',
    'kidney',
    'adrenal',
    'thyroid',
    'parathyroid',
    'pituitary',
    'prostate',
    'reproductive',
  };

  /// Short home labels so the body card stays readable on a phone.
  static const shortLabels = {
    'general': 'General',
    'lungs': 'Lungs',
    'bones': 'Bones',
    'blood': 'Blood',
    'heart': 'Heart',
    'liver': 'Liver',
    'immune': 'Immune',
    'pancreas': 'Metabolic',
    'kidney': 'Kidneys',
    'adrenal': 'Adrenal',
    'thyroid': 'Thyroid',
    'metabolic': 'Metabolic',
    'parathyroid': 'Parathyroid',
    'pituitary': 'Pituitary',
    'prostate': 'Prostate',
    'reproductive': 'Reproductive',
  };

  static String shortLabel(String code, [String? fallback]) {
    final known = shortLabels[code];
    if (known != null) return known;
    final raw = (fallback ?? code).trim();
    if (raw.isEmpty) return code;
    final cut = raw.split(RegExp(r'[&/]')).first.trim();
    return cut.isEmpty ? code : cut;
  }

  static String _key(String profileId) => 'body_panel_prefs_$profileId';

  List<String> get visibleOrder => [
        for (final c in order)
          if (!hidden.contains(c)) c
      ];

  static BodyPanelPrefs defaultsFromCatalog(Iterable<String> catalogCodes) {
    final order = [
      for (final c in catalogCodes)
        if (!_skip.contains(c)) c,
    ];
    return BodyPanelPrefs(order: order, hidden: {});
  }

  static Future<BodyPanelPrefs> load({
    required String? profileId,
    required Iterable<String> catalogCodes,
  }) async {
    final fallback = defaultsFromCatalog(catalogCodes);
    if (profileId == null) return fallback;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(profileId));
    if (raw == null || raw.isEmpty) return fallback;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return fallback;
      final known = {
        for (final c in catalogCodes)
          if (!_skip.contains(c)) c,
      };
      final order = <String>[];
      final seen = <String>{};
      final rawOrder = decoded['order'];
      if (rawOrder is List) {
        for (final item in rawOrder) {
          if (item is! String) continue;
          if (!known.contains(item)) continue;
          if (seen.add(item)) order.add(item);
        }
      }
      for (final c in fallback.order) {
        if (seen.add(c)) order.add(c);
      }
      final hidden = <String>{};
      final rawHidden = decoded['hidden'];
      if (rawHidden is List) {
        for (final item in rawHidden) {
          if (item is String && known.contains(item)) hidden.add(item);
        }
      }
      return BodyPanelPrefs(order: order, hidden: hidden);
    } catch (_) {
      return fallback;
    }
  }

  Future<void> save(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(profileId),
      jsonEncode({
        'order': order,
        'hidden': hidden.toList()..sort(),
      }),
    );
  }

  BodyPanelPrefs copyWith({
    List<String>? order,
    Set<String>? hidden,
  }) =>
      BodyPanelPrefs(
        order: order ?? this.order,
        hidden: hidden ?? this.hidden,
      );

  List<T> applyToSummaries<T>(
    List<T> all, {
    required String Function(T) codeOf,
  }) {
    final byCode = {for (final s in all) codeOf(s): s};
    return [
      for (final code in visibleOrder)
        if (byCode.containsKey(code)) byCode[code] as T,
    ];
  }

  /// Catalogue codes that paint using a different silhouette key.
  static const mapAliases = {
    'metabolic': 'pancreas',
  };

  Map<String, V> mapFlags<V>(Map<String, V> all) {
    final visible = visibleOrder.toSet();
    final out = <String, V>{};
    for (final e in all.entries) {
      if (!visible.contains(e.key)) continue;
      final paintAs = mapAliases[e.key] ?? e.key;
      if (!glyphCodes.contains(paintAs)) continue;
      out[paintAs] = e.value;
    }
    return out;
  }
}
