import 'dart:convert';

import 'package:flutter/services.dart';

/// Offline name suggestions for medicines / remedies.
/// Not advice, not interactions, not a formulary claim.
class DrugSuggestion {
  const DrugSuggestion({
    required this.name,
    required this.kind,
    required this.aliases,
  });
  final String name;
  final String kind;
  final List<String> aliases;
}

class DrugIndex {
  DrugIndex._();
  static final DrugIndex instance = DrugIndex._();

  List<DrugSuggestion>? _all;

  Future<List<DrugSuggestion>> ensureLoaded() async {
    if (_all != null) return _all!;
    try {
      final raw = await rootBundle.loadString('assets/catalog/drugs.json');
      final list = jsonDecode(raw) as List<dynamic>;
      _all = [
        for (final e in list)
          DrugSuggestion(
            name: (e as Map)['name'] as String,
            kind: e['kind'] as String? ?? 'other',
            aliases: ((e['aliases'] as String?) ?? '')
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
          ),
      ];
    } catch (_) {
      _all = const [];
    }
    return _all!;
  }

  Future<List<DrugSuggestion>> search(
    String query, {
    int limit = 12,
    bool preferBrand = false,
  }) async {
    final all = await ensureLoaded();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all.take(limit).toList();
    final scored = <(int, DrugSuggestion)>[];
    for (final d in all) {
      final name = d.name.toLowerCase();
      var score = 0;
      if (preferBrand) {
        // Brand mode: boost alias (brand) hits; still show salt matches lower.
        for (final a in d.aliases) {
          final al = a.toLowerCase();
          if (al == q) {
            score = 110;
          } else if (al.startsWith(q)) {
            score = score < 90 ? 90 : score;
          } else if (al.contains(q)) {
            score = score < 70 ? 70 : score;
          }
        }
        if (name == q) {
          score = score < 60 ? 60 : score;
        } else if (name.startsWith(q)) {
          score = score < 45 ? 45 : score;
        } else if (name.contains(q)) {
          score = score < 30 ? 30 : score;
        }
      } else {
        if (name == q) {
          score = 100;
        } else if (name.startsWith(q)) {
          score = 80;
        } else if (name.contains(q)) {
          score = 50;
        } else if (d.aliases.any((a) => a.toLowerCase().contains(q))) {
          score = 40;
        }
      }
      if (score > 0) scored.add((score, d));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final s in scored.take(limit)) s.$2];
  }
}
