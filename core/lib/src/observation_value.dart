/// Parse a reported lab value such as "12.4", "<0.01", ">=5".
class ParsedObservationValue {
  const ParsedObservationValue({
    required this.reported,
    this.comparator,
    this.numeric,
    this.text,
  });

  final String reported;
  final String? comparator;
  final double? numeric;
  final String? text;
}

final _comparatorPrefix = RegExp(r'^\s*(<=|>=|<|>)\s*(.+)$');
final _numeric = RegExp(r'^-?\d+(\.\d+)?$');

ParsedObservationValue parseReportedValue(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return ParsedObservationValue(reported: raw, text: raw);
  }

  final match = _comparatorPrefix.firstMatch(trimmed);
  if (match != null) {
    final rest = match.group(2)!.trim();
    final n = double.tryParse(rest);
    return ParsedObservationValue(
      reported: trimmed,
      comparator: match.group(1),
      numeric: n,
      text: n == null ? rest : null,
    );
  }

  if (_numeric.hasMatch(trimmed)) {
    return ParsedObservationValue(
      reported: trimmed,
      numeric: double.parse(trimmed),
    );
  }

  return ParsedObservationValue(reported: trimmed, text: trimmed);
}
