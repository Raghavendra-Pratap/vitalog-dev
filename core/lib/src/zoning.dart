import 'layout.dart';

enum ReportZone { header, results, notes, footer }

enum RowType {
  result,
  heading,
  attribute,
  band,
  note,
  headerRepeat,
  noise,
}

/// Layout row after zone + type classification (spec §6).
class ClassifiedRow {
  const ClassifiedRow({
    required this.row,
    required this.zone,
    required this.rowType,
    this.suspectType = false,
    this.section,
  });

  final LayoutRow row;
  final ReportZone zone;
  final RowType rowType;
  /// True when upgraded from heading/note/noise via safety net (§6.5).
  final bool suspectType;
  /// Nearest panel/heading context above this row.
  final String? section;

  String get text => row.text;
  int get page => row.page;
}

const _headerWords = <String>{
  'test',
  'test name',
  'investigation',
  'test description',
  'parameter',
  'result',
  'results',
  'observed value',
  'value',
  'value(s)',
  'unit',
  'units',
  'unit(s)',
  'biological reference interval',
  'bio. ref. interval',
  'reference range',
  'ref. range',
  'normal range',
  'method',
  'technology',
  'flag',
  'status',
};

final _attributeStart = RegExp(
  r'^(method|sample|specimen|sample\s*type)\s*:',
  caseSensitive: false,
);

final _bandLabel = RegExp(
  r'^(optimal|deficient|insufficient|sufficient|desirable|borderline|'
  r'high\s*risk|low\s*risk|normal|abnormal|1st\s*trimester|2nd\s*trimester|'
  r'3rd\s*trimester|non[- ]?pregnant|pregnant|adult|child|male|female)\b',
  caseSensitive: false,
);

final _endMarker = RegExp(
  r'^(interpretation|note|notes|comments|clinical\s+significance|'
  r'reference\s*:|~~\s*end|end\s+of\s+report|performed\s+at)\b',
  caseSensitive: false,
);

final _footerCue = RegExp(
  r'(page\s*\d+\s*(of|/)\s*\d+|consultant\s+pathologist|end\s+of\s+report|'
  r'accredited|nabl|iso\s*15189|ulr\s*no)',
  caseSensitive: false,
);

final _valueNumber = RegExp(
  r'(?:[<>≤≥]\s*)?\d{1,3}(?:,\d{3})+(?:\.\d+)?|'
  r'(?:[<>≤≥]\s*)?\d+(?:\.\d+)?',
);

final _qualitativeValue = RegExp(
  r'\b(positive|negative|reactive|non[-\s]?reactive|present|absent|nil|trace|'
  r'detected|not\s+detected|normal|clear|turbid|pale\s+yellow|straw|'
  r'\+{1,4})\b',
  caseSensitive: false,
);

final _knownUnit = RegExp(
  r'\b(mg/?dL|g/?dL|µg/?dL|ug/?dL|ng/?(?:dL|mL)|pg/?mL|µIU/?mL|uIU/?mL|'
  r'mIU/?mL|IU/?(?:L|mL)|U/?L|mmol/?L|%|ratio|fL|pg|10\^?[36]/µ?L|'
  r'cells/?µ?L|/cumm|mm/?hr|ng/?L)\b',
  caseSensitive: false,
);

bool looksLikeValueToken(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  if (_qualitativeValue.hasMatch(t)) return true;
  // Bare number or comparator+number (not a range-only "a - b" without name).
  if (RegExp(r'^[<>≤≥]?\s*\d{1,4}(?:[.,]\d+)?(?:\s*/\s*[Hh][Pp][Ff])?$')
      .hasMatch(t)) {
    return true;
  }
  if (_valueNumber.hasMatch(t) && RegExp(r'[A-Za-z]{2,}').hasMatch(t)) {
    // "T3 110.00" style — has value token inside.
    return true;
  }
  return _valueNumber.hasMatch(t) && !RegExp(r'^\d+\s*[-–]\s*\d+').hasMatch(t);
}

bool _isColumnHeaderRow(LayoutRow row) {
  final cells = [
    for (final c in row.cells)
      c.text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim(),
  ];
  var hits = 0;
  for (final c in cells) {
    if (_headerWords.contains(c)) hits++;
    for (final h in _headerWords) {
      if (c == h || (c.length <= 24 && c.contains(h) && h.length >= 4)) {
        hits++;
        break;
      }
    }
  }
  // Dedup overcount: require ≥2 distinct header-ish cells.
  final distinct = cells.where((c) {
    if (_headerWords.contains(c)) return true;
    return _headerWords.any((h) => c.contains(h) && h.length >= 4);
  }).toSet();
  return distinct.length >= 2 || hits >= 2;
}

bool _isParagraphBlock(LayoutRow row, {required double pageWidth}) {
  if (row.cells.isEmpty) return false;
  final words = row.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.length <= 8) return false;
  final span = row.cells.fold<double>(0, (s, c) => s + c.w);
  return pageWidth > 0 && span / pageWidth > 0.70;
}

/// Classify layout rows into zones and row types (spec §6).
List<ClassifiedRow> classifyRows(
  List<LayoutRow> rows, {
  Set<String>? knownUnits,
}) {
  if (rows.isEmpty) return const [];

  var maxRight = 0.0;
  for (final r in rows) {
    for (final c in r.cells) {
      final right = c.x + c.w;
      if (right > maxRight) maxRight = right;
    }
  }
  final pageWidth = maxRight > 0 ? maxRight : 600.0;

  var zone = ReportZone.header;
  String? section;
  final out = <ClassifiedRow>[];
  var paragraphStreak = 0;

  for (final row in rows) {
    final text = row.text.trim();
    if (text.isEmpty) continue;

    // Zone transitions
    if (_isColumnHeaderRow(row)) {
      zone = ReportZone.results;
      out.add(
        ClassifiedRow(
          row: row,
          zone: zone,
          rowType: RowType.headerRepeat,
          section: section,
        ),
      );
      paragraphStreak = 0;
      continue;
    }

    if (_endMarker.hasMatch(text) ||
        (_footerCue.hasMatch(text) && zone == ReportZone.results)) {
      zone = _footerCue.hasMatch(text) &&
              RegExp(r'page\s*\d+', caseSensitive: false).hasMatch(text)
          ? ReportZone.footer
          : ReportZone.notes;
    }

    if (zone == ReportZone.results &&
        _isParagraphBlock(row, pageWidth: pageWidth)) {
      paragraphStreak++;
      if (paragraphStreak >= 2) {
        zone = ReportZone.notes;
      }
    } else {
      paragraphStreak = 0;
    }

    if (zone == ReportZone.header &&
        looksLikeValueToken(text) &&
        RegExp(r'[A-Za-z]{2,}').hasMatch(text)) {
      // Results often start without an explicit header on phone OCR.
      zone = ReportZone.results;
    }

    final type = zone == ReportZone.results
        ? _classifyResultZoneRow(row, text)
        : (zone == ReportZone.notes
            ? RowType.note
            : (zone == ReportZone.footer ? RowType.noise : RowType.noise));

    var finalType = type;
    var suspect = false;
    if (zone == ReportZone.results &&
        (type == RowType.heading ||
            type == RowType.note ||
            type == RowType.noise) &&
        _safetyNetUpgrade(text, knownUnits: knownUnits)) {
      finalType = RowType.result;
      suspect = true;
    }

    if (finalType == RowType.heading) {
      section = text;
    }

    out.add(
      ClassifiedRow(
        row: row,
        zone: zone,
        rowType: finalType,
        suspectType: suspect,
        section: section,
      ),
    );
  }
  return out;
}


bool _looksLikeAdminTimestamp(String text) {
  final t = text.trim();
  if (RegExp(r'^(registered|collected|reported|received)\s+on\s*:', caseSensitive: false)
      .hasMatch(t)) {
    return true;
  }
  if (RegExp(r'\b\d{1,2}:\d{2}\s*[AP]M\b', caseSensitive: false).hasMatch(t) &&
      !RegExp(r'\b(mg|g/dL|mmol|%|U/L)\b', caseSensitive: false).hasMatch(t)) {
    return true;
  }
  return false;
}

RowType _classifyResultZoneRow(LayoutRow row, String text) {
  if (_looksLikeAdminTimestamp(text)) return RowType.noise;
  if (_isColumnHeaderRow(row)) return RowType.headerRepeat;
  if (_attributeStart.hasMatch(text) ||
      RegExp(r'^\([^)]{3,40}\)$').hasMatch(text)) {
    return RowType.attribute;
  }
  if (_bandLabel.hasMatch(text) &&
      (RegExp(r'\d').hasMatch(text) || text.contains(':'))) {
    return RowType.band;
  }
  if (looksLikeValueToken(text) &&
      (RegExp(r'[A-Za-z]{2,}').hasMatch(text) || row.cells.length >= 2)) {
    return RowType.result;
  }
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  if (!looksLikeValueToken(text) && words <= 8 && text.length <= 60) {
    return RowType.heading;
  }
  if (words > 12 && text.contains('.')) return RowType.note;
  if (!RegExp(r'[A-Za-z]').hasMatch(text) && !looksLikeValueToken(text)) {
    return RowType.noise;
  }
  return RowType.noise;
}

bool _safetyNetUpgrade(String text, {Set<String>? knownUnits}) {
  if (!_valueNumber.hasMatch(text)) return false;
  if (_knownUnit.hasMatch(text)) return true;
  if (knownUnits == null || knownUnits.isEmpty) return false;
  final lower = text.toLowerCase();
  for (final u in knownUnits) {
    if (u.length >= 2 && lower.contains(u.toLowerCase())) return true;
  }
  return false;
}
