import 'zoning.dart';

/// Parsed tokens from a result row (spec §7).
class ParsedExtractionRow {
  const ParsedExtractionRow({
    required this.nameRaw,
    required this.nameNorm,
    required this.valueRaw,
    this.valueNum,
    this.comparator,
    this.valueText,
    this.flagPrinted,
    this.unitRaw,
    this.unitNorm,
    this.refLow,
    this.refHigh,
    this.refText,
    this.method,
    this.specimen,
    this.bands = const [],
    required this.sourceLine,
    required this.page,
    this.section,
    this.suspectType = false,
  });

  final String nameRaw;
  final String nameNorm;
  final String valueRaw;
  final double? valueNum;
  final String? comparator;
  final String? valueText;
  final String? flagPrinted;
  final String? unitRaw;
  final String? unitNorm;
  final double? refLow;
  final double? refHigh;
  final String? refText;
  final String? method;
  final String? specimen;
  final List<ParsedBand> bands;
  final String sourceLine;
  final int page;
  final String? section;
  final bool suspectType;
}

class ParsedBand {
  const ParsedBand({required this.label, this.low, this.high, this.text});
  final String label;
  final double? low;
  final double? high;
  final String? text;
}

final _specimenWords = RegExp(
  r'\b(serum|sr\.?|plasma|whole\s+blood|edta|fluoride|heparin)\b',
  caseSensitive: false,
);
final _methodWords = RegExp(
  r'\b(clia|eclia|cmia|hplc|calculated|enzymatic|ise|elisa|photometry|'
  r'immuno(?:assay|turbidimetry)?|cibc|ultrasensitive)\b',
  caseSensitive: false,
);
final _keepDirect = RegExp(r'\bdirect\b', caseSensitive: false);

final _flagRe = RegExp(
  r'\b(H|L|High|Low|\*|↑|↓|HH|LL)\b',
);

final _rangeRe = RegExp(
  r'(?:(?<low>\d+(?:[.,]\d+)?)\s*[-–—to]+\s*(?<high>\d+(?:[.,]\d+)?)|'
  r'(?:upto|up\s*to|<|≤)\s*(?<max>\d+(?:[.,]\d+)?)|'
  r'(?:>|≥)\s*(?<min>\d+(?:[.,]\d+)?))',
  caseSensitive: false,
);

final _valueTokenRe = RegExp(
  r'^(?<comp>[<>≤≥])?\s*(?<num>\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:[.,]\d+)?)'
  r'(?:\s*/\s*[Hh][Pp][Ff])?$',
);

final _qualRe = RegExp(
  r'^(positive|negative|reactive|non[-\s]?reactive|present|absent|nil|trace|'
  r'detected|not\s+detected|normal|clear|turbid|pale\s+yellow|straw|\+{1,4})$',
  caseSensitive: false,
);

/// Parse classified result (+ attached attribute/band) rows into tokens.
List<ParsedExtractionRow> parseResultTokens(
  List<ClassifiedRow> classified, {
  Map<String, String>? unitAliases,
}) {
  final out = <ParsedExtractionRow>[];
  for (var i = 0; i < classified.length; i++) {
    final c = classified[i];
    if (c.rowType != RowType.result) continue;

    final attrs = <String>[];
    final bands = <ParsedBand>[];
    var j = i + 1;
    while (j < classified.length) {
      final n = classified[j];
      if (n.page != c.page) break;
      if (n.rowType == RowType.attribute) {
        attrs.add(n.text);
        j++;
        continue;
      }
      if (n.rowType == RowType.band) {
        bands.add(_parseBand(n.text));
        j++;
        continue;
      }
      break;
    }

    final parsed = _parseOne(
      c,
      attrs: attrs,
      bands: bands,
      unitAliases: unitAliases ?? const {},
    );
    if (parsed != null) out.add(parsed);
  }
  return out;
}

ParsedBand _parseBand(String text) {
  final m = RegExp(r'^([^:]+):\s*(.+)$').firstMatch(text);
  final label = (m?.group(1) ?? text).trim();
  final rest = (m?.group(2) ?? '').trim();
  double? low;
  double? high;
  final rm = _rangeRe.firstMatch(rest);
  if (rm != null) {
    low = _toDouble(rm.namedGroup('low') ?? rm.namedGroup('min'));
    high = _toDouble(rm.namedGroup('high') ?? rm.namedGroup('max'));
  }
  return ParsedBand(label: label, low: low, high: high, text: rest.isEmpty ? text : rest);
}

ParsedExtractionRow? _parseOne(
  ClassifiedRow c, {
  required List<String> attrs,
  required List<ParsedBand> bands,
  required Map<String, String> unitAliases,
}) {
  final cells = [for (final cell in c.row.cells) cell.text.trim()]
      .where((t) => t.isNotEmpty)
      .toList();
  if (cells.isEmpty) return null;

  String? name;
  String? valueRaw;
  String? unitRaw;
  String? rangeRaw;
  String? flag;
  String? comparator;
  double? valueNum;
  String? valueText;

  // Heuristic L→R: name, value, unit, range (or name | value | range | unit for Agilus).
  if (cells.length == 1) {
    final parts = cells.first.split(RegExp(r'\s+'));
    // Find first value-like token index
    var vi = -1;
    for (var i = 0; i < parts.length; i++) {
      if (_isValuePart(parts[i])) {
        vi = i;
        break;
      }
    }
    if (vi <= 0) {
      // Try "Name 12.3 unit"
      final m = RegExp(
        r'^(.+?)\s+([<>≤≥]?\s*\d+(?:[.,]\d+)?)\s*([A-Za-zµ/%μ][A-Za-z0-9µ/%μ.^]*)?',
      ).firstMatch(cells.first);
      if (m == null) return null;
      name = m.group(1);
      valueRaw = m.group(2)?.replaceAll(' ', '');
      unitRaw = m.group(3);
    } else {
      name = parts.sublist(0, vi).join(' ');
      valueRaw = parts[vi];
      final rest = parts.sublist(vi + 1);
      for (final p in rest) {
        if (_flagRe.hasMatch(p) && p.length <= 4) {
          flag ??= p;
        } else if (_looksUnit(p, unitAliases)) {
          unitRaw ??= p;
        } else if (_rangeRe.hasMatch(p) || p.contains('-') || p.contains('–')) {
          rangeRaw = (rangeRaw == null) ? p : '$rangeRaw $p';
        } else if (unitRaw == null && RegExp(r'^[A-Za-zµ/%]').hasMatch(p)) {
          unitRaw = p;
        } else {
          rangeRaw = (rangeRaw == null) ? p : '$rangeRaw $p';
        }
      }
    }
  } else {
    name = cells.first;
    for (var i = 1; i < cells.length; i++) {
      final p = cells[i];
      if (valueRaw == null && _isValuePart(p)) {
        valueRaw = p;
        continue;
      }
      if (_flagRe.hasMatch(p) && p.length <= 5) {
        flag ??= p;
        continue;
      }
      if (unitRaw == null && _looksUnit(p, unitAliases)) {
        unitRaw = p;
        continue;
      }
      if (rangeRaw == null &&
          (_rangeRe.hasMatch(p) ||
              RegExp(r'\d\s*[-–]\s*\d').hasMatch(p) ||
              p.toLowerCase().startsWith('up'))) {
        rangeRaw = p;
        continue;
      }
      if (unitRaw == null &&
          RegExp(r'^[A-Za-zµμ/%]').hasMatch(p) &&
          !_isValuePart(p)) {
        unitRaw = p;
        continue;
      }
      rangeRaw = (rangeRaw == null) ? p : '$rangeRaw $p';
    }
  }

  if (name == null || name.trim().isEmpty) return null;
  if (valueRaw == null || valueRaw.trim().isEmpty) return null;

  final vm = _valueTokenRe.firstMatch(valueRaw.trim());
  if (vm != null) {
    comparator = vm.namedGroup('comp');
    valueNum = _toDouble(vm.namedGroup('num'));
    valueRaw = '${comparator ?? ''}${vm.namedGroup('num')}';
  } else if (_qualRe.hasMatch(valueRaw.trim())) {
    valueText = valueRaw.trim();
  } else {
    // Strip flag glued to value
    final cleaned = valueRaw.replaceAll(_flagRe, '').trim();
    final vm2 = _valueTokenRe.firstMatch(cleaned);
    if (vm2 != null) {
      comparator = vm2.namedGroup('comp');
      valueNum = _toDouble(vm2.namedGroup('num'));
      valueRaw = '${comparator ?? ''}${vm2.namedGroup('num')}';
    }
  }

  double? refLow;
  double? refHigh;
  if (rangeRaw != null) {
    final rm = _rangeRe.firstMatch(rangeRaw);
    if (rm != null) {
      refLow = _toDouble(rm.namedGroup('low') ?? rm.namedGroup('min'));
      refHigh = _toDouble(rm.namedGroup('high') ?? rm.namedGroup('max'));
    }
    // Unit from range cell: "13.0-17.0 g/dL"
    if (unitRaw == null) {
      final um = _knownUnitInline.firstMatch(rangeRaw);
      if (um != null) unitRaw = um.group(0);
    }
  }

  String? method;
  String? specimen;
  for (final a in attrs) {
    final lower = a.toLowerCase();
    if (lower.startsWith('method')) {
      method = a.split(RegExp(r':')).skip(1).join(':').trim();
    } else if (lower.contains('sample') || lower.contains('specimen')) {
      specimen = a.split(RegExp(r':')).skip(1).join(':').trim();
    }
  }

  final nameClean = _cleanName(name, methodOut: (m) {
    method ??= m;
  }, specimenOut: (s) {
    specimen ??= s;
  });

  final unitNorm = unitRaw == null
      ? null
      : (unitAliases[_normKey(unitRaw)] ?? unitRaw);

  return ParsedExtractionRow(
    nameRaw: name.trim(),
    nameNorm: nameClean,
    valueRaw: valueRaw.trim(),
    valueNum: valueNum,
    comparator: comparator,
    valueText: valueText,
    flagPrinted: flag,
    unitRaw: unitRaw,
    unitNorm: unitNorm,
    refLow: refLow,
    refHigh: refHigh,
    refText: rangeRaw,
    method: method,
    specimen: specimen,
    bands: bands,
    sourceLine: c.text,
    page: c.page,
    section: c.section,
    suspectType: c.suspectType,
  );
}

final _knownUnitInline = RegExp(
  r'(mg/?dL|g/?dL|µg/?dL|ug/?dL|ng/?(?:dL|mL)|pg/?mL|µIU/?mL|uIU/?mL|'
  r'mIU/?mL|IU/?(?:L|mL)|U/?L|mmol/?L|%|fL|pg)',
  caseSensitive: false,
);

bool _isValuePart(String p) {
  final t = p.trim();
  if (_qualRe.hasMatch(t)) return true;
  if (_valueTokenRe.hasMatch(t)) return true;
  if (RegExp(r'^[<>≤≥]?\s*\d+(?:[.,]\d+)?$').hasMatch(t)) return true;
  return false;
}

bool _looksUnit(String p, Map<String, String> aliases) {
  final t = p.trim();
  if (t.isEmpty || t.length > 24) return false;
  if (aliases.containsKey(_normKey(t))) return true;
  return _knownUnitInline.hasMatch(t);
}

String _normKey(String s) => s
    .toLowerCase()
    .replaceAll('µ', 'u')
    .replaceAll('μ', 'u')
    .replaceAll(RegExp(r'\s+'), '');

String _cleanName(
  String name, {
  required void Function(String) methodOut,
  required void Function(String) specimenOut,
}) {
  var s = name.trim();
  s = s.replaceAll(RegExp(r'^[\u2022\-\*\d.)\s]+'), '');
  s = s.replaceAll(RegExp(r':\s*$'), '');
  // Parenthetical method
  final paren = RegExp(r'\(([^)]+)\)').allMatches(s).toList();
  for (final m in paren) {
    final inner = m.group(1)!;
    if (_methodWords.hasMatch(inner)) {
      methodOut(inner);
      s = s.replaceAll(m.group(0)!, ' ');
    }
  }
  final specM = _specimenWords.firstMatch(s);
  if (specM != null) {
    specimenOut(specM.group(0)!);
    s = s.replaceAll(_specimenWords, ' ');
  }
  final methM = _methodWords.firstMatch(s);
  if (methM != null && !_keepDirect.hasMatch(methM.group(0)!)) {
    methodOut(methM.group(0)!);
    s = s.replaceAll(_methodWords, ' ');
  }
  s = s.toLowerCase();
  s = s.replaceAll('&', ' and ');
  s = s.replaceAll('µ', 'u').replaceAll('μ', 'u');
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

double? _toDouble(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  var t = raw.replaceAll(',', '');
  // Decimal comma: 14,2 → only if single comma and no thousands pattern
  if (RegExp(r'^\d+,\d{1,2}$').hasMatch(raw)) {
    t = raw.replaceAll(',', '.');
  }
  return double.tryParse(t);
}
