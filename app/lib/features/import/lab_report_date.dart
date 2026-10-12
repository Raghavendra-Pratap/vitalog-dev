/// Best-effort collection / report dates from lab PDF or paste text.
library;

class LabReportDates {
  const LabReportDates({
    this.collectedAt,
    this.reportedAt,
    this.sourceLabel,
  });

  final DateTime? collectedAt;
  final DateTime? reportedAt;
  /// Which field we preferred for [collectedAt] (for UI).
  final String? sourceLabel;

  /// Date to store on the report / observations.
  DateTime get effective =>
      collectedAt ?? reportedAt ?? DateTime.now();
}

/// Prefer sample/collection date over report/print date.
LabReportDates parseLabReportDates(String raw) {
  final text = raw.replaceAll('\r\n', '\n');
  DateTime? collected;
  DateTime? reported;
  String? collectedLabel;
  String? reportedLabel;

  // Labelled lines first (most reliable).
  final labelled = <(RegExp, String, bool)>[
    // (pattern, label, isCollected)
    (RegExp(r'(?:sample\s*(?:collected|collection)|collected\s*on|collection\s*date|specimen\s*(?:date|collected)|sample\s*date)\s*[:\-]?\s*([^\n]{6,40})', caseSensitive: false), 'Collected', true),
    (RegExp(r'(?:registered\s*on|registration\s*date|received\s*on)\s*[:\-]?\s*([^\n]{6,40})', caseSensitive: false), 'Registered', true),
    (RegExp(r'(?:reported\s*on|report\s*date|result\s*date|printed\s*on)\s*[:\-]?\s*([^\n]{6,40})', caseSensitive: false), 'Reported', false),
  ];

  for (final (re, label, isCollected) in labelled) {
    for (final m in re.allMatches(text)) {
      final d = _parseDateToken(m.group(1)!);
      if (d == null) continue;
      if (isCollected) {
        collected ??= d;
        collectedLabel ??= label;
      } else {
        reported ??= d;
        reportedLabel ??= label;
      }
    }
  }

  // Fallback: first plausible date near the top of the extract (header).
  if (collected == null && reported == null) {
    final head = text.length > 2500 ? text.substring(0, 2500) : text;
    final loose = RegExp(
      r'\b(\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}|\d{1,2}\s+[A-Za-z]{3,9}\s+\d{2,4}|\d{4}[/.\-]\d{1,2}[/.\-]\d{1,2})\b',
    );
    for (final m in loose.allMatches(head)) {
      final d = _parseDateToken(m.group(1)!);
      if (d == null) continue;
      // Skip absurd future / ancient dates.
      final now = DateTime.now();
      if (d.isAfter(now.add(const Duration(days: 2)))) continue;
      if (d.isBefore(DateTime(now.year - 30))) continue;
      collected = d;
      collectedLabel = 'Detected in header';
      break;
    }
  }

  return LabReportDates(
    collectedAt: collected,
    reportedAt: reported,
    sourceLabel: collected != null
        ? collectedLabel
        : reported != null
            ? reportedLabel
            : null,
  );
}

DateTime? _parseDateToken(String raw) {
  var s = raw.trim();
  // Cut trailing junk (time, commas, lab codes).
  s = s.split(RegExp(r'[|,;]|at\s+\d', caseSensitive: false)).first.trim();
  s = s.replaceAll(RegExp(r'\s+'), ' ');

  // dd/mm/yyyy or dd-mm-yyyy or dd.mm.yyyy
  var m = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})$').firstMatch(s);
  if (m != null) {
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    return _valid(y, mo, d);
  }

  // yyyy-mm-dd
  m = RegExp(r'^(\d{4})[/.\-](\d{1,2})[/.\-](\d{1,2})$').firstMatch(s);
  if (m != null) {
    return _valid(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  // 27 Sep 2026 / 27-Sep-2026 / 27 September 2026
  m = RegExp(
    r'^(\d{1,2})[\s\-/]+([A-Za-z]{3,9})[\s\-/]+(\d{2,4})$',
  ).firstMatch(s);
  if (m != null) {
    final d = int.parse(m.group(1)!);
    final mo = _month(m.group(2)!);
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    if (mo == null) return null;
    return _valid(y, mo, d);
  }

  // Sep 27, 2026
  m = RegExp(
    r'^([A-Za-z]{3,9})\s+(\d{1,2}),?\s+(\d{2,4})$',
  ).firstMatch(s);
  if (m != null) {
    final mo = _month(m.group(1)!);
    final d = int.parse(m.group(2)!);
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    if (mo == null) return null;
    return _valid(y, mo, d);
  }

  return DateTime.tryParse(s);
}

DateTime? _valid(int y, int mo, int d) {
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  try {
    final dt = DateTime(y, mo, d);
    if (dt.year != y || dt.month != mo || dt.day != d) return null;
    return dt;
  } catch (_) {
    return null;
  }
}

int? _month(String raw) {
  const map = {
    'jan': 1, 'january': 1,
    'feb': 2, 'february': 2,
    'mar': 3, 'march': 3,
    'apr': 4, 'april': 4,
    'may': 5,
    'jun': 6, 'june': 6,
    'jul': 7, 'july': 7,
    'aug': 8, 'august': 8,
    'sep': 9, 'sept': 9, 'september': 9,
    'oct': 10, 'october': 10,
    'nov': 11, 'november': 11,
    'dec': 12, 'december': 12,
  };
  return map[raw.toLowerCase()];
}
