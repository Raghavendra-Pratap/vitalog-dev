/// Computed flag for an observation. UI maps these to copy (ADR-003).
enum ObservationFlag {
  normal,
  low,
  high,
  abnormal,
  criticalLow,
  criticalHigh,
}

/// User-visible label — never a diagnosis.
String flagLabel(ObservationFlag flag) {
  switch (flag) {
    case ObservationFlag.normal:
      return 'In range';
    case ObservationFlag.low:
    case ObservationFlag.criticalLow:
      return "Below the lab's range";
    case ObservationFlag.high:
    case ObservationFlag.criticalHigh:
      return "Above the lab's range";
    case ObservationFlag.abnormal:
      return 'Outside expected';
  }
}

/// Compute flag from a numeric value and optional lab range.
/// Lab range wins when both bounds (or one-sided) are present.
ObservationFlag? computeNumericFlag({
  required double? value,
  double? refLow,
  double? refHigh,
}) {
  if (value == null) return null;
  if (refLow == null && refHigh == null) return null;

  if (refLow != null && value < refLow) {
    return ObservationFlag.low;
  }
  if (refHigh != null && value > refHigh) {
    return ObservationFlag.high;
  }
  return ObservationFlag.normal;
}
