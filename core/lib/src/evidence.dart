import 'token_parse.dart';

enum ExtractionOutcome { autoAccept, review, unrecognised }

class MatchCandidate {
  const MatchCandidate({
    required this.parameterCode,
    required this.score,
    this.reasons = const [],
  });
  final String parameterCode;
  final int score;
  final List<String> reasons;
}

class ScoredExtractionRow {
  const ScoredExtractionRow({
    required this.parsed,
    required this.candidates,
    required this.outcome,
  });
  final ParsedExtractionRow parsed;
  final List<MatchCandidate> candidates;
  final ExtractionOutcome outcome;

  MatchCandidate? get best =>
      candidates.isEmpty ? null : candidates.first;
}

/// Catalogue snapshot for matching (loaded by app from catalog.db).
class MatchCatalog {
  const MatchCatalog({
    required this.aliasToCodes,
    required this.paramNames,
    required this.paramUnits,
    this.physicalLimits = const {},
    this.unitAliases = const {},
  });

  /// alias_norm → parameter codes (may be ambiguous).
  final Map<String, List<String>> aliasToCodes;
  final Map<String, String> paramNames;
  final Map<String, String> paramUnits;
  /// parameter_code → (low, high, unit)
  final Map<String, (double, double, String)> physicalLimits;
  final Map<String, String> unitAliases;
}

/// Match + evidence score (spec §8). Learned rules / embeddings deferred.
List<ScoredExtractionRow> matchAndScore(
  List<ParsedExtractionRow> rows,
  MatchCatalog catalog,
) {
  final scored = <ScoredExtractionRow>[];
  for (final row in rows) {
    final cands = _cascade(row, catalog);
    cands.sort((a, b) => b.score.compareTo(a.score));
    final top = cands.take(3).toList();
    // Ambiguity penalty
    if (top.length >= 2 && (top[0].score - top[1].score).abs() <= 10) {
      for (var i = 0; i < top.length; i++) {
        top[i] = MatchCandidate(
          parameterCode: top[i].parameterCode,
          score: top[i].score - 20,
          reasons: [...top[i].reasons, 'ambiguous_candidates'],
        );
      }
      top.sort((a, b) => b.score.compareTo(a.score));
    }
    final best = top.isEmpty ? null : top.first;
    final outcome = _outcome(best);
    scored.add(
      ScoredExtractionRow(parsed: row, candidates: top, outcome: outcome),
    );
  }
  return _applyCrossChecks(scored, catalog);
}

ExtractionOutcome _outcome(MatchCandidate? best) {
  if (best == null || best.score < 30) return ExtractionOutcome.unrecognised;
  if (best.score >= 70) return ExtractionOutcome.autoAccept;
  return ExtractionOutcome.review;
}

List<MatchCandidate> _cascade(ParsedExtractionRow row, MatchCatalog catalog) {
  final out = <MatchCandidate>[];
  void addAll(Iterable<String> codes, int base, String reason) {
    for (final code in codes) {
      out.add(
        MatchCandidate(
          parameterCode: code,
          score: _evidence(row, code, base, catalog, reason),
          reasons: [reason],
        ),
      );
    }
  }

  final keys = <String>{row.nameNorm};
  // Bracket variants: try full and inside/outside
  final raw = row.nameRaw;
  final br = RegExp(r'^(.*?)\(([^)]+)\)\s*$').firstMatch(raw);
  if (br != null) {
    keys.add(_norm(br.group(1)!));
    keys.add(_norm(br.group(2)!));
  }

  var found = false;
  for (final k in keys) {
    if (k.isEmpty) continue;
    final codes = catalog.aliasToCodes[k];
    if (codes != null && codes.isNotEmpty) {
      addAll(codes, 40, 'exact_alias');
      found = true;
    }
  }
  if (found) return _dedupeBest(out);

  // Soft prefix for longer names only
  if (row.nameNorm.length >= 5) {
    final aliasKeys = catalog.aliasToCodes.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final a in aliasKeys) {
      if (a.length < 5) break;
      if (row.nameNorm == a ||
          row.nameNorm.startsWith(a) ||
          row.nameNorm.endsWith(a) ||
          a.startsWith(row.nameNorm)) {
        addAll(catalog.aliasToCodes[a]!, 30, 'soft_alias');
        found = true;
        break;
      }
    }
  }
  if (found) return _dedupeBest(out);

  // Fuzzy: edit distance ≤ 1 on 3–5 chars; never under 3
  if (row.nameNorm.length >= 3 && row.nameNorm.length <= 5) {
    for (final e in catalog.aliasToCodes.entries) {
      if (e.key.length < 3 || e.key.length > 6) continue;
      if (_editDistance(row.nameNorm, e.key) <= 1) {
        addAll(e.value, 15, 'fuzzy_edit1');
        found = true;
      }
    }
  } else if (row.nameNorm.length >= 6) {
    for (final e in catalog.aliasToCodes.entries) {
      if (e.key.length < 6) continue;
      if (_jaroWinkler(row.nameNorm, e.key) >= 0.92) {
        addAll(e.value, 15, 'fuzzy_jw');
        found = true;
        if (out.length >= 6) break;
      }
    }
  }

  return _dedupeBest(out);
}

List<MatchCandidate> _dedupeBest(List<MatchCandidate> raw) {
  final best = <String, MatchCandidate>{};
  for (final c in raw) {
    final prev = best[c.parameterCode];
    if (prev == null || c.score > prev.score) best[c.parameterCode] = c;
  }
  return best.values.toList();
}

int _evidence(
  ParsedExtractionRow row,
  String code,
  int base,
  MatchCatalog catalog,
  String matchReason,
) {
  var score = base;
  final reasons = <String>[matchReason];
  final unit = row.unitNorm ?? row.unitRaw ?? '';
  final expected = catalog.paramUnits[code] ?? '';
  if (unit.isNotEmpty && expected.isNotEmpty) {
    if (_unitsCompatible(unit, expected)) {
      score += 20;
      reasons.add('unit_ok');
    } else {
      score -= 30;
      reasons.add('unit_mismatch');
    }
  }
  final lim = catalog.physicalLimits[code];
  if (lim != null && row.valueNum != null) {
    if (row.valueNum! >= lim.$1 && row.valueNum! <= lim.$2) {
      score += 15;
      reasons.add('physical_ok');
    } else {
      score -= 40;
      reasons.add('physical_fail');
    }
  }
  if (row.refLow != null && row.refHigh != null && row.valueNum != null) {
    final mid = (row.refLow! + row.refHigh!) / 2;
    if (mid > 0) {
      final ratio = row.valueNum! / mid;
      if (ratio >= 0.1 && ratio <= 10) {
        score += 10;
        reasons.add('range_magnitude_ok');
      }
    }
  }
  if (row.section != null && row.section!.trim().isNotEmpty) {
    score += 5;
    reasons.add('section_context');
  }
  return score.clamp(-100, 100);
}

bool _unitsCompatible(String a, String b) {
  String n(String s) => s
      .toLowerCase()
      .replaceAll('µ', 'u')
      .replaceAll('μ', 'u')
      .replaceAll(RegExp(r'[\s/_^]'), '');
  final na = n(a);
  final nb = n(b);
  if (na == nb) return true;
  if (na.contains(nb) || nb.contains(na)) return true;
  // Common equivalents
  const pairs = [
    ['uiu/ml', 'uiuml'],
    ['ng/dl', 'ngdl'],
    ['ug/dl', 'ugdl'],
    ['mg/dl', 'mgdl'],
    ['g/dl', 'gdl'],
  ];
  for (final p in pairs) {
    if ((na == p[0] || na == p[1]) && (nb == p[0] || nb == p[1])) return true;
  }
  return false;
}

List<ScoredExtractionRow> _applyCrossChecks(
  List<ScoredExtractionRow> rows,
  MatchCatalog catalog,
) {
  // Lightweight lipids check when all present
  double? val(String code) {
    for (final r in rows) {
      if (r.best?.parameterCode == code) return r.parsed.valueNum;
    }
    return null;
  }

  final tc = val('tc');
  final hdl = val('hdl');
  final ldl = val('ldl');
  final vldl = val('vldl');
  if (tc != null && hdl != null && ldl != null && vldl != null) {
    final sum = hdl + ldl + vldl;
    final ok = (sum - tc).abs() <= tc * 0.10;
    if (!ok) {
      return [
        for (final r in rows)
          if (['tc', 'hdl', 'ldl', 'vldl'].contains(r.best?.parameterCode))
            ScoredExtractionRow(
              parsed: r.parsed,
              candidates: [
                for (final c in r.candidates)
                  MatchCandidate(
                    parameterCode: c.parameterCode,
                    score: (c.score - 25).clamp(-100, 100),
                    reasons: [...c.reasons, 'crosscheck_lipids_fail'],
                  ),
              ],
              outcome: r.outcome == ExtractionOutcome.autoAccept
                  ? ExtractionOutcome.review
                  : r.outcome,
            )
          else
            r,
      ];
    }
  }
  return rows;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replaceAll('µ', 'u')
    .replaceAll('μ', 'u')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final m = a.length;
  final n = b.length;
  final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  for (var i = 0; i <= m; i++) {
    dp[i][0] = i;
  }
  for (var j = 0; j <= n; j++) {
    dp[0][j] = j;
  }
  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      dp[i][j] = [
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
  }
  return dp[m][n];
}

double _jaroWinkler(String s1, String s2) {
  if (s1 == s2) return 1;
  final jaro = _jaro(s1, s2);
  var prefix = 0;
  final maxP = s1.length < s2.length ? s1.length : s2.length;
  for (var i = 0; i < maxP && i < 4; i++) {
    if (s1[i] == s2[i]) {
      prefix++;
    } else {
      break;
    }
  }
  return jaro + prefix * 0.1 * (1 - jaro);
}

double _jaro(String s1, String s2) {
  if (s1.isEmpty || s2.isEmpty) return 0;
  final matchDist = (s1.length > s2.length ? s1.length : s2.length) ~/ 2 - 1;
  final md = matchDist < 0 ? 0 : matchDist;
  final s1m = List<bool>.filled(s1.length, false);
  final s2m = List<bool>.filled(s2.length, false);
  var matches = 0;
  for (var i = 0; i < s1.length; i++) {
    final start = i - md < 0 ? 0 : i - md;
    final end = i + md + 1 > s2.length ? s2.length : i + md + 1;
    for (var j = start; j < end; j++) {
      if (s2m[j] || s1[i] != s2[j]) continue;
      s1m[i] = true;
      s2m[j] = true;
      matches++;
      break;
    }
  }
  if (matches == 0) return 0;
  var t = 0;
  var k = 0;
  for (var i = 0; i < s1.length; i++) {
    if (!s1m[i]) continue;
    while (!s2m[k]) {
      k++;
    }
    if (s1[i] != s2[k]) t++;
    k++;
  }
  final m = matches.toDouble();
  return (m / s1.length + m / s2.length + (m - t / 2) / m) / 3;
}
