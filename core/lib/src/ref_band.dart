import 'dart:convert';

import 'flag.dart';

/// One printed reference band / stage on a lab slip (ADR-003 / ADR-006).
///
/// Labels are lab/user text as entered — never invent clinical diagnoses.
class RefBand {
  const RefBand({
    this.label,
    this.low,
    this.high,
    this.safe,
  });

  final String? label;
  final double? low;
  final double? high;
  /// User/lab attributed: true = safe band, false = unsafe, null = unset.
  /// Never a diagnosis (ADR-003).
  final bool? safe;

  bool get hasBounds => low != null || high != null;

  Map<String, Object?> toJson() => {
        if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
        if (low != null) 'low': low,
        if (high != null) 'high': high,
        if (safe != null) 'safe': safe,
      };

  static RefBand? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final label = (m['label'] as String?)?.trim();
    final low = _asDouble(m['low']);
    final high = _asDouble(m['high']);
    if ((label == null || label.isEmpty) && low == null && high == null) {
      return null;
    }
    final safeRaw = m['safe'];
    bool? safe;
    if (safeRaw is bool) {
      safe = safeRaw;
    } else if (safeRaw is num) {
      safe = safeRaw != 0;
    } else if (safeRaw is String) {
      final s = safeRaw.trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'safe') safe = true;
      if (s == 'false' || s == '0' || s == 'unsafe') safe = false;
    }
    return RefBand(
      label: (label == null || label.isEmpty) ? null : label,
      low: low,
      high: high,
      safe: safe,
    );
  }

  RefBand copyWith({
    String? label,
    double? low,
    double? high,
    bool? safe,
    bool clearLabel = false,
    bool clearLow = false,
    bool clearHigh = false,
    bool clearSafe = false,
  }) =>
      RefBand(
        label: clearLabel ? null : (label ?? this.label),
        low: clearLow ? null : (low ?? this.low),
        high: clearHigh ? null : (high ?? this.high),
        safe: clearSafe ? null : (safe ?? this.safe),
      );

  @override
  bool operator ==(Object other) =>
      other is RefBand &&
      other.label == label &&
      other.low == low &&
      other.high == high &&
      other.safe == safe;

  @override
  int get hashCode => Object.hash(label, low, high, safe);
}

double? _asDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim().replaceAll(',', ''));
  return null;
}

/// Decode `observation.ref_bands_json`. Returns null when empty / invalid.
List<RefBand>? decodeRefBandsJson(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty || t == 'null' || t == '[]') return null;
  try {
    final decoded = jsonDecode(t);
    if (decoded is! List) return null;
    final out = <RefBand>[];
    for (final item in decoded) {
      final b = RefBand.fromJson(item);
      if (b != null && b.hasBounds) out.add(b);
    }
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}

/// Encode bands for SQLite. Null when empty.
String? encodeRefBandsJson(List<RefBand>? bands) {
  if (bands == null || bands.isEmpty) return null;
  final cleaned = [
    for (final b in bands)
      if (b.hasBounds) b,
  ];
  if (cleaned.isEmpty) return null;
  return jsonEncode([for (final b in cleaned) b.toJson()]);
}

/// Stable key for frequency / identity of a band set (order-sensitive as printed).
String normalizeRefBandsKey(List<RefBand> bands) {
  final parts = <String>[];
  for (final b in bands) {
    if (!b.hasBounds) continue;
    final label = (b.label ?? '').trim().toLowerCase();
    parts.add(
      '$label|${b.low?.toString() ?? '∅'}|${b.high?.toString() ?? '∅'}',
    );
  }
  return parts.join('||');
}

/// Outer envelope of all band lows / highs (for charts + simple interval mirror).
({double? low, double? high}) envelopeFromBands(List<RefBand> bands) {
  double? lo;
  double? hi;
  for (final b in bands) {
    if (b.low != null) {
      lo = lo == null ? b.low : (b.low! < lo! ? b.low : lo);
    }
    if (b.high != null) {
      hi = hi == null ? b.high : (b.high! > hi! ? b.high : hi);
    }
  }
  return (low: lo, high: hi);
}

/// Band-aware flag: in any printed stage → normal; below all → low; above all →
/// high; gap between stages → abnormal. Falls back to simple refs when bands absent.
ObservationFlag? computeFlagWithBands({
  required double? value,
  double? refLow,
  double? refHigh,
  List<RefBand>? refBands,
}) {
  if (value == null) return null;
  final bands = refBands == null
      ? null
      : [for (final b in refBands) if (b.hasBounds) b];
  if (bands != null && bands.isNotEmpty) {
    for (final b in bands) {
      final inBand = computeNumericFlag(
        value: value,
        refLow: b.low,
        refHigh: b.high,
      );
      if (inBand == ObservationFlag.normal) return ObservationFlag.normal;
    }
    final env = envelopeFromBands(bands);
    if (env.low != null && value < env.low!) return ObservationFlag.low;
    if (env.high != null && value > env.high!) return ObservationFlag.high;
    return ObservationFlag.abnormal;
  }
  return computeNumericFlag(value: value, refLow: refLow, refHigh: refHigh);
}
