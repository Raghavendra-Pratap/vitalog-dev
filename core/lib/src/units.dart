/// Linear unit conversion: canonical = value * factor + offset.
class UnitConversion {
  const UnitConversion({
    required this.fromUnit,
    required this.toUnit,
    required this.factor,
    this.offset = 0,
  });

  final String fromUnit;
  final String toUnit;
  final double factor;
  final double offset;

  double convert(double value) => value * factor + offset;
}

/// Normalize common unit spellings for lookup.
String normalizeUnitAlias(String raw) {
  return raw.toLowerCase().replaceAll(RegExp(r'[\s·•]'), '').replaceAll('µ', 'u');
}

/// Built-in conversions used before catalogue.db is loaded.
const List<UnitConversion> builtInConversions = [
  UnitConversion(fromUnit: 'mmol/L', toUnit: 'mg/dL', factor: 18.0182), // glucose
  UnitConversion(fromUnit: 'mg/dL', toUnit: 'mmol/L', factor: 1 / 18.0182),
];

double? convertUnit({
  required double value,
  required String fromUnit,
  required String toUnit,
  List<UnitConversion> conversions = builtInConversions,
}) {
  final from = normalizeUnitAlias(fromUnit);
  final to = normalizeUnitAlias(toUnit);
  if (from == to) return value;
  for (final c in conversions) {
    if (normalizeUnitAlias(c.fromUnit) == from &&
        normalizeUnitAlias(c.toUnit) == to) {
      return c.convert(value);
    }
  }
  return null;
}
