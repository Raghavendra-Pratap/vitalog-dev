import 'package:bodyline_core/bodyline_core.dart';

/// Historical lab reference-range suggestions for a profile + parameter.
///
/// Built from past observations (slip ranges). ADR-006: each observation keeps
/// its own printed range; suggestions only **prefill empty** Low/High fields —
/// never overwrite OCR/PDF/slip values.
class RefRangeSuggestion {
  const RefRangeSuggestion({
    required this.low,
    required this.high,
    required this.count,
    this.unit,
  });

  final double? low;
  final double? high;
  final String? unit;
  final int count;

  /// Compact range label for chips / menus.
  String get rangeLabel {
    final lo = low == null ? '—' : _fmtNum(low!);
    final hi = high == null ? '—' : _fmtNum(high!);
    return '$lo–$hi';
  }

  String get chipLabel {
    final u = unit?.trim();
    if (u == null || u.isEmpty) return rangeLabel;
    return '$rangeLabel $u';
  }

  static String _fmtNum(double n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toString();
  }
}

/// One historical row used as input to [buildRefRangeSuggestions].
class RefRangeHistoryRow {
  const RefRangeHistoryRow({
    this.refLow,
    this.refHigh,
    this.unit,
  });

  final double? refLow;
  final double? refHigh;
  final String? unit;
}

/// Frequency of distinct (low, high) pairs. Optional [unit] is the most common
/// non-empty unit among rows that share that pair.
///
/// - Skips rows where both refs are null.
/// - Sorted by [RefRangeSuggestion.count] descending; ties broken by low, then
///   high, then unit (stable for tests / UI).
List<RefRangeSuggestion> buildRefRangeSuggestions(
  Iterable<RefRangeHistoryRow> rows,
) {
  final buckets = <String, _Bucket>{};

  for (final row in rows) {
    if (row.refLow == null && row.refHigh == null) continue;
    final key = _pairKey(row.refLow, row.refHigh);
    final bucket = buckets.putIfAbsent(
      key,
      () => _Bucket(low: row.refLow, high: row.refHigh),
    );
    bucket.count += 1;
    final u = row.unit?.trim();
    if (u != null && u.isNotEmpty) {
      bucket.unitCounts[u] = (bucket.unitCounts[u] ?? 0) + 1;
    }
  }

  final out = <RefRangeSuggestion>[
    for (final b in buckets.values)
      RefRangeSuggestion(
        low: b.low,
        high: b.high,
        count: b.count,
        unit: b.topUnit(),
      ),
  ];

  out.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    final byLow = _nullsLast(a.low, b.low);
    if (byLow != 0) return byLow;
    final byHigh = _nullsLast(a.high, b.high);
    if (byHigh != 0) return byHigh;
    return (a.unit ?? '').compareTo(b.unit ?? '');
  });

  return out;
}

String _pairKey(double? low, double? high) =>
    '${low?.toString() ?? '∅'}|${high?.toString() ?? '∅'}';

int _nullsLast(double? a, double? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

class _Bucket {
  _Bucket({required this.low, required this.high});

  final double? low;
  final double? high;
  int count = 0;
  final Map<String, int> unitCounts = {};

  String? topUnit() {
    if (unitCounts.isEmpty) return null;
    String? best;
    var bestN = -1;
    final keys = unitCounts.keys.toList()..sort();
    for (final k in keys) {
      final n = unitCounts[k]!;
      if (n > bestN) {
        bestN = n;
        best = k;
      }
    }
    return best;
  }
}

/// ADR-006: only autofill when both Low and High are empty/null.
bool refsBothEmpty(String? lowText, String? highText) =>
    (lowText ?? '').trim().isEmpty && (highText ?? '').trim().isEmpty;

bool refsBothNull(double? low, double? high) => low == null && high == null;

String formatRefNum(double n) {
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toString();
}

// ---------------------------------------------------------------------------
// Multi-range / stage band-set suggestions (ADR-006 empty-only autofill)
// ---------------------------------------------------------------------------

/// Historical identical band-set suggestion for a profile + parameter.
class RefBandSetSuggestion {
  const RefBandSetSuggestion({
    required this.bands,
    required this.count,
    this.unit,
  });

  final List<RefBand> bands;
  final String? unit;
  final int count;

  String get chipLabel {
    if (bands.isEmpty) return '—';
    final parts = <String>[];
    for (final b in bands.take(3)) {
      final lo = b.low == null ? '—' : formatRefNum(b.low!);
      final hi = b.high == null ? '—' : formatRefNum(b.high!);
      final lab = (b.label ?? '').trim();
      parts.add(lab.isEmpty ? '$lo–$hi' : '$lab $lo–$hi');
    }
    final more = bands.length > 3 ? ' +${bands.length - 3}' : '';
    final core = parts.join(' · ') + more;
    final u = unit?.trim();
    if (u == null || u.isEmpty) return core;
    return '$core $u';
  }
}

/// One historical row used as input to [buildRefBandSetSuggestions].
class RefBandSetHistoryRow {
  const RefBandSetHistoryRow({
    this.refBands,
    this.unit,
  });

  final List<RefBand>? refBands;
  final String? unit;
}

/// Frequency of identical normalized band sets. Skips empty / null band lists.
List<RefBandSetSuggestion> buildRefBandSetSuggestions(
  Iterable<RefBandSetHistoryRow> rows,
) {
  final buckets = <String, _BandBucket>{};

  for (final row in rows) {
    final bands = row.refBands;
    if (bands == null || bands.isEmpty) continue;
    final cleaned = [for (final b in bands) if (b.hasBounds) b];
    if (cleaned.isEmpty) continue;
    final key = normalizeRefBandsKey(cleaned);
    if (key.isEmpty) continue;
    final bucket = buckets.putIfAbsent(
      key,
      () => _BandBucket(bands: List<RefBand>.unmodifiable(cleaned)),
    );
    bucket.count += 1;
    final u = row.unit?.trim();
    if (u != null && u.isNotEmpty) {
      bucket.unitCounts[u] = (bucket.unitCounts[u] ?? 0) + 1;
    }
  }

  final out = <RefBandSetSuggestion>[
    for (final b in buckets.values)
      RefBandSetSuggestion(
        bands: b.bands,
        count: b.count,
        unit: b.topUnit(),
      ),
  ];

  out.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    return normalizeRefBandsKey(a.bands)
        .compareTo(normalizeRefBandsKey(b.bands));
  });

  return out;
}

class _BandBucket {
  _BandBucket({required this.bands});

  final List<RefBand> bands;
  int count = 0;
  final Map<String, int> unitCounts = {};

  String? topUnit() {
    if (unitCounts.isEmpty) return null;
    String? best;
    var bestN = -1;
    final keys = unitCounts.keys.toList()..sort();
    for (final k in keys) {
      final n = unitCounts[k]!;
      if (n > bestN) {
        bestN = n;
        best = k;
      }
    }
    return best;
  }
}

/// ADR-006 for stages: only autofill when no bands and both Low/High empty.
bool refsAndBandsEmpty({
  required String? lowText,
  required String? highText,
  required List<RefBand>? bands,
}) {
  final hasBands = bands != null && bands.any((b) => b.hasBounds);
  return !hasBands && refsBothEmpty(lowText, highText);
}
