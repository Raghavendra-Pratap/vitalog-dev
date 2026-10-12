import 'package:bodyline_core/bodyline_core.dart';

// Quality filters for OCR / paste lab parsing — prefer result rows over
// glossary prose and reject accession-style IDs as observation values.

final _prosePhrases = RegExp(
  r'(may\s*indicate|primar\w*\s+in\s+the|essential\s*for|'
  r'linked\s*to|suggest\w*\s*(?:liver|tissue|damage|injury)|'
  r'clinical\s*significance|key\s*enzymes\s*te\w*|'
  r'elevated\s+(?:alt|ast|enzymes)|blood\s*proteins|'
  r'are\s*essential|indicate\w*\s*(?:dehydration|tissue|bleeding)|'
  r'the\s+liver\b.{0,40}(?:enzyme|blood|filter)|'
  r'when\s+cells\s+are\s+dam|'
  r'hyperproteinemia|agammaglobul)',
  caseSensitive: false,
);

final _interpretationHeader = RegExp(
  r'^(interpretation|clinical significance|comments?|note|notes|'
  r'method(?:ology)?|limitations?|disclaimer|key enzymes)\s*:?\s*$',
  caseSensitive: false,
);

final _glossaryNumbered = RegExp(
  r'^\d{1,2}\.\s+[A-Za-z(].{8,}',
);

final _accessionValue = RegExp(
  r'^(\d{7,}|\d{5,}\s*/\s*[A-Za-z]{2,}\d+|RL\d{6,}|\d{6,}[A-Z]{2,}\d+)$',
  caseSensitive: false,
);

final _labUnitToken = RegExp(
  r'\b(mg/?dL|mgIdL|g/?dL|gIdL|ug/?dL|ugIdL|µg/?dL|mcg/?dL|U/?L|UIL|IU/?L|IUIL|mU/?L|mUIL|'
  r'uIU/?mL|µIU/?mL|mIU/?L|mIU/?mL|'
  r'ng/?mL|ng/?dL|ngIdL|pg/?mL|mmol/?L|umol/?L|µmol/?L|'
  r'mEq/?L|%|ratio|cells?/?µL|fL|pg)\b',
  caseSensitive: false,
);

final _hlFlagGlued = RegExp(
  r'(\d+(?:\.\d+)?)\s*[HL]\s*\*',
  caseSensitive: false,
);

/// Method / assay footnotes that Vision often emits on their own line.
final _methodNoiseLine = RegExp(
  r'^(diazo|calculated|calculation.*|ifcc.*|jfcc.*|enzymatic|biuret|'
  r'bcg\s*colorimetric|without\s*p5p|enzyma\w*|'
  r'method\s*:?\s*.*|'
  r'electrochemi\w*.*)$',
  caseSensitive: false,
);

/// Detach lab H*/L* flags glued to numeric results so stacked parsers see clean values.
String detachHlFlags(String raw) {
  return raw.replaceAllMapped(_hlFlagGlued, (m) => m.group(1)!);
}

/// Strip Vision/ML Kit caret / star artifacts on analyte labels.
String stripOcrLabelArtifacts(String raw) {
  return raw
      .split('\n')
      .map((line) {
        var t = line.trim();
        // "Gamma Glutamyl Transferase (GGT) ^" / "Globulin *"
        t = t.replaceAll(RegExp(r'[\*^•]+$'), '').trim();
        t = t.replaceAll(RegExp(r'\s+[\*^•]\s*$'), '').trim();
        return t;
      })
      .join('\n');
}

/// Alnum-only fold for OCR typo matching ("SUggest", "areessential", "darmage").
String ocrLooseFold(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

bool _looseLooksEducational(String loose) {
  if (loose.isEmpty) return false;
  const needles = <String>[
    'mayindicate',
    'primarilyinthe',
    'primartyinthe',
    'essentialfor',
    'areessential',
    'bloodproteins',
    'keyenzym',
    'linkedto',
    'suggestliver',
    'suggesttissue',
    'clinicalsignificance',
    'hyperproteinemia',
    'agammaglobul',
    'thelivertit',
    'livercolscontain',
    'enzymesleak',
    'whenCellsare',
    'whencellsare',
  ];
  for (final n in needles) {
    if (loose.contains(n)) return true;
  }
  return false;
}

/// Drop interpretation / glossary blocks that steal catalogue matches.
String stripInterpretationBlocks(String raw) {
  final out = <String>[];
  var skipping = false;
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) {
      if (!skipping) out.add(line);
      continue;
    }
    if (_interpretationHeader.hasMatch(t) ||
        ((_looseLooksEducational(ocrLooseFold(t)) || _prosePhrases.hasMatch(t)) &&
            t.length > 48)) {
      skipping = true;
      continue;
    }
    if (skipping) {
      if (RegExp(r'^--- page \d+', caseSensitive: false).hasMatch(t)) {
        skipping = false;
        out.add(line);
        continue;
      }
      if (_looksLikeResultRow(t)) {
        skipping = false;
        out.add(line);
        continue;
      }
      continue;
    }
    // Drop standalone method footnotes (keeps stacked name→value near).
    if (_methodNoiseLine.hasMatch(t)) continue;
    out.add(line);
  }
  return out.join('\n');
}

bool _looksLikeResultRow(String line) {
  if (line.length > 120) return false;
  if (_prosePhrases.hasMatch(line)) return false;
  if (_looseLooksEducational(ocrLooseFold(line))) return false;
  if (_glossaryNumbered.hasMatch(line) && !_labUnitToken.hasMatch(line)) {
    return false;
  }
  return RegExp(
        r'[A-Za-z]{2,}.*\d+(?:\.\d+)?',
      ).hasMatch(line) &&
      (RegExp(r'\d+(?:\.\d+)?').hasMatch(line) &&
          (_labUnitToken.hasMatch(line) ||
              RegExp(r'\d+\s*[-–to]+\s*\d+', caseSensitive: false)
                  .hasMatch(line) ||
              line.length < 60));
}

/// True when the line is educational glossary / interpretation prose.
bool isEducationalProse(String line) {
  final t = line.trim();
  if (t.isEmpty) return false;
  if (_interpretationHeader.hasMatch(t)) return true;
  if (_prosePhrases.hasMatch(t)) return true;
  if (_looseLooksEducational(ocrLooseFold(t))) return true;
  // Numbered glossary: "1. AST (SGOT): may indicate..." (OCR typos OK via fold)
  if (_glossaryNumbered.hasMatch(t)) {
    final afterColon = t.contains(':')
        ? t.substring(t.indexOf(':') + 1).trim()
        : '';
    if (afterColon.isNotEmpty &&
        !RegExp(r'^[<>]?\d').hasMatch(afterColon) &&
        afterColon.split(RegExp(r'\s+')).length >= 3) {
      return true;
    }
    // Even without colon body: "1. AST (SGOT): mayindicate..." folded
    if (_looseLooksEducational(ocrLooseFold(t))) return true;
  }
  // Long sentence-like lines without a unit / range.
  if (t.length >= 55 &&
      !_labUnitToken.hasMatch(t) &&
      !RegExp(r'\d+\s*[-–to]+\s*\d+').hasMatch(t) &&
      (RegExp(r'[.!?]').hasMatch(t) ||
          t.split(RegExp(r'\s+')).length >= 8)) {
    return true;
  }
  return false;
}

/// Patient / barcode / accession IDs must not become observation values.
bool isAccessionLikeValue(String value, {String unit = ''}) {
  final v = value.trim();
  final u = unit.trim();
  if (v.isEmpty) return false;
  if (_accessionValue.hasMatch(v.replaceAll(' ', ''))) return true;
  if (RegExp(r'^\d{7,}$').hasMatch(v)) return true;
  // Stacked OCR: value=18945041 unit=/RCL18588087
  if (RegExp(r'^/\s*[A-Za-z]{2,}\d+').hasMatch(u)) return true;
  if (RegExp(r'^[A-Za-z]{2,}\d{5,}$').hasMatch(u)) return true;
  if (v.contains('/') && RegExp(r'\d{5,}').hasMatch(v)) return true;
  return false;
}

/// Soft alias match: allow short suffixes (method notes), not whole sentences.
bool softAliasLengthOk(String normLabel, String alias) {
  if (normLabel.length <= alias.length) return true;
  // ~16 extra alnum chars ≈ short parenthetical / method; prose is far longer.
  return normLabel.length <= alias.length + 16;
}

/// Max lines to look ahead from a stacked analyte label for its value.
/// Keep tight so Vision/column OCR cannot borrow Bilirubin’s value for GGT.
const int kStackedValueLookahead = 4;

/// Whether reported unit is compatible with the catalogue canonical unit.
bool labUnitsCompatible(String reported, String catalog) {
  final trimmed = reported.trim();
  // Indian PDFs often put "-" in the units column for dimensionless ratios.
  if (trimmed.isEmpty ||
      trimmed == '-' ||
      trimmed == '–' ||
      trimmed == '—' ||
      trimmed == '−' ||
      trimmed == '.') {
    return true;
  }
  final r = _unitFold(reported);
  final c = _unitFold(catalog);
  if (r.isEmpty || c.isEmpty) return true;
  if (r == c) return true;
  // IU/L ≈ U/L for enzymes.
  if ((r == 'ul' || r == 'iul') && (c == 'ul' || c == 'iul')) return true;
  // Insulin / peptide hormones: mU/L ≈ µIU/mL ≈ uIU/mL ≈ mIU/L.
  // Only when the catalogue side is clearly a µIU/mIU family (not 10^6/µL).
  const hormoneCatalog = {'uiuml', 'iuml', 'miul', 'uiu', 'miuml'};
  const hormoneReported = {'mul', 'miul', 'uiuml', 'iuml', 'uiu', 'miuml'};
  if (hormoneCatalog.contains(c) && hormoneReported.contains(r)) return true;
  if (hormoneCatalog.contains(r) && hormoneReported.contains(c)) return true;
  if (r.contains(c) || c.contains(r)) return true;
  return false;
}

String _unitFold(String u) {
  var s = u.toLowerCase();
  // Preserve micro-prefix as ascii "u" before stripping non-alnum
  // (otherwise µg/dL → gdl and fails vs ug/dL → ugdl).
  s = s.replaceAll('µ', 'u').replaceAll('μ', 'u').replaceAll('mcg', 'ug');
  var f = s.replaceAll(RegExp(r'[^a-z0-9]'), '');
  // Slash → I/l/1 OCR forms that slipped past repairOcrLabUnits.
  const aliases = <String, String>{
    'uil': 'ul',
    'iuil': 'iul',
    'muil': 'mul',
    'gidl': 'gdl',
    'mgidl': 'mgdl',
    'uidl': 'udl',
    'ngiml': 'ngml',
    'ngidl': 'ngdl',
    'pgiml': 'pgml',
    'ugidl': 'ugdl',
    'mcgdl': 'ugdl',
    'mcgidl': 'ugdl',
    'mmolil': 'mmoll',
    'umolil': 'umoll',
    // Hormone µIU family after micro→u rewrite.
    'uiuml': 'uiuml',
    'iuml': 'uiuml',
    // µ misread as p/P before repairOcrLabUnits.
    'piuml': 'uiuml',
    'pgdl': 'ugdl',
  };
  return aliases[f] ?? f;
}

/// Urine "Blood" must not match "Blood proteins…" glossary lines.
bool isAmbiguousUrineBloodHit({
  required String parameterCode,
  required String sourceLine,
  String unit = '',
}) {
  if (parameterCode != 'u_blood') return false;
  final loose = ocrLooseFold(sourceLine);
  if (loose.contains('protein') ||
      loose.contains('albumin') ||
      loose.contains('globulin') ||
      loose.contains('essential')) {
    return true;
  }
  // Bare "Blood" with a serum-style unit is wrong.
  final uf = _unitFold(unit);
  if (uf.contains('gdl') || uf.contains('mgdl') || uf.contains('ul')) {
    return true;
  }
  return false;
}

/// Score a candidate hit; higher is better. Prefer real result rows.
int labHitScore({
  required String sourceLine,
  required String value,
  String unit = '',
  double? refLow,
  double? refHigh,
  String catalogUnit = '',
}) {
  var score = 0;
  final src = sourceLine.trim();
  if (isEducationalProse(src)) score -= 80;
  if (isAccessionLikeValue(value, unit: unit)) score -= 100;
  if (!labUnitsCompatible(unit, catalogUnit)) score -= 120;
  if (_labUnitToken.hasMatch(unit) || _labUnitToken.hasMatch(src)) score += 25;
  if (refLow != null || refHigh != null) score += 15;
  if (RegExp(r'\d+\s*[-–to]+\s*\d+', caseSensitive: false).hasMatch(src)) {
    score += 10;
  }
  // Compact result row vs long prose label.
  if (src.length <= 55) {
    score += 20;
  } else if (src.length > 90) {
    score -= 25;
  }
  // Value magnitude typical for labs (not 8-digit IDs).
  final n = double.tryParse(value.replaceAll(RegExp(r'[<>]'), ''));
  if (n != null) {
    if (n >= 0 && n < 100000) score += 10;
    if (n >= 1000000) score -= 50;
  }
  // Same-line name+value shape.
  if (RegExp(
    r'^[A-Za-z(].{0,50}?\s+[<>]?\d+(?:\.\d+)?',
  ).hasMatch(src)) {
    score += 20;
  }
  return score;
}

/// Prefer the richer / more result-like hit when collapsing duplicates.
bool shouldReplaceLabHit({
  required int existingScore,
  required int candidateScore,
  required bool candidateHasUnitOrRange,
  required bool existingHasUnitOrRange,
}) {
  if (candidateScore > existingScore) return true;
  if (candidateScore < existingScore) return false;
  // Tie: prefer unit/range richness (later only if equally rich).
  if (candidateHasUnitOrRange && !existingHasUnitOrRange) return true;
  if (!candidateHasUnitOrRange && existingHasUnitOrRange) return false;
  return true; // equal → keep later (stable with prior behaviour)
}


final _valueLineRe = RegExp(
  r'^([<>]?\d+(?:\.\d+)?)\s*(?:[HL]\*?)?\s*$',
  caseSensitive: false,
);
final _valueUnitLineRe = RegExp(
  r'^([<>]?\d+(?:\.\d+)?)\s*(?:[HL]\*?)?\s*'
  r'([A-Za-z/%][A-Za-z0-9/%.\-]*)'
  r'(?:\s+(?:'
  r'(\d+(?:\.\d+)?)\s*[-–to]+\s*(\d+(?:\.\d+)?)|'
  r'up\s*to\s*(\d+(?:\.\d+)?)|'
  r'<\s*(\d+(?:\.\d+)?)'
  r'))?\s*$',
  caseSensitive: false,
);
final _unitLineRe = RegExp(r'^[A-Za-z/%][A-Za-z0-9/%.\-]{0,12}$');
final _rangeLineRe = RegExp(
  r'^(?:(\d+(?:\.\d+)?)\s*[-–to]+\s*(\d+(?:\.\d+)?)|up\s*to\s*(\d+(?:\.\d+)?)|<\s*(\d+(?:\.\d+)?))\s*$',
  caseSensitive: false,
);
final _headerNoise = RegExp(
  r'^(test description|value\(s\)|unit\(s\)|reference range|patient|barcode|'
  r'sample|report|laboratory|redcliffe|fib\b|liver function|package|'
  r'speciali[sz]ed chemistry|diagnostic report|biological reference|'
  r'test report status|results?|units?)\b',
  caseSensitive: false,
);

/// Agilus (and similar) section banners / panel titles — not analytes.
bool isLabSectionOrPanelTitle(String line) {
  final t = line.trim();
  if (t.isEmpty) return false;
  if (_headerNoise.hasMatch(t)) return true;
  // Package / complete-care marketing lines on Agilus chrome.
  if (RegExp(
    r'^(complete\s*care|possible\s*conditions|view\s*details|view\s*report)\b',
    caseSensitive: false,
  ).hasMatch(t)) {
    return true;
  }
  // Department banners (single token).
  if (RegExp(
    r'^(haematology|hematology|biochemistry|immunology|serology|'
    r'microbiology|endocrinology|cytology|histopathology)\b',
    caseSensitive: false,
  ).hasMatch(t)) {
    return true;
  }
  // CBC / named panels without result digits.
  if (RegExp(
    r'^complete\s+blood\s+count\b',
    caseSensitive: false,
  ).hasMatch(t)) {
    return true;
  }
  // "THYROID PANEL…", "LIPID PROFILE", "LIVER FUNCTION TEST(S)"
  // Digits inside parentheticals (T3,T4) still count as a panel title.
  // Do not treat "CHOLESTEROL, TOTAL" as a profile — requires panel/profile word.
  if (RegExp(
        r'\b(panel|profile|package|function\s*tests?)\b',
        caseSensitive: false,
      ).hasMatch(t) &&
      t.length >= 8 &&
      !RegExp(
        r'\b\d+(?:\.\d+)?\s*(?:mg|g|u|iu|ng|pg|%|ratio)\b',
        caseSensitive: false,
      ).hasMatch(t)) {
    return true;
  }
  // ALL-CAPS dashed banners: "SPECIALISED CHEMISTRY - HORMONE / LIPIDS"
  final lettersOnly = t.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (lettersOnly.length >= 10 &&
      t == t.toUpperCase() &&
      t.contains('-') &&
      !RegExp(r'\d').hasMatch(t) &&
      !RegExp(
        r'\b(serum|plasma|blood|urine|fasting|random)\b',
        caseSensitive: false,
      ).hasMatch(t)) {
    return true;
  }
  return false;
}

bool looksLikeAnalyteLabelLine(String line) {
  final t = line.trim();
  if (t.isEmpty || t.length > 70) return false;
  if (isEducationalProse(t)) return false;
  if (_methodNoiseLine.hasMatch(t)) return false;
  if (isLabSectionOrPanelTitle(t)) return false;
  // Biological-ref band captions are not analytes.
  if (_refBandLabelLine.hasMatch(t)) return false;
  if (RegExp(
    r'^(non[-\s]?pregnant|pregnant|adult|male|female|trimester)\b',
    caseSensitive: false,
  ).hasMatch(t)) {
    return false;
  }
  if (_valueLineRe.hasMatch(t) || _valueUnitLineRe.hasMatch(t)) return false;
  if (_rangeLineRe.hasMatch(t)) return false;
  if (_unitLineRe.hasMatch(t) && t.length <= 12 && !t.contains(' ')) {
    // "Ratio" as unit word after a value — not a label here.
    if (RegExp(r'^(mg/?dl|g/?dl|u/?l|iu/?l|ratio|%|ng/?ml)$', caseSensitive: false)
        .hasMatch(t)) {
      return false;
    }
  }
  // Letter present; allow short codes like T3 / T4 / Hb.
  if (!RegExp(r'[A-Za-z]').hasMatch(t)) return false;
  if (!RegExp(r'[A-Za-z]{2,}').hasMatch(t) &&
      !RegExp(r'^[A-Za-z]\d{1,2}$').hasMatch(t)) {
    return false;
  }
  // Avoid pure sentences.
  if (t.split(RegExp(r'\s+')).length >= 10) return false;
  return true;
}



bool _enzymeName(String label) => RegExp(
      r'\b(ggt|sgot|sgpt|ast|alt|alkaline\s*phosphatase|alp)\b',
      caseSensitive: false,
    ).hasMatch(label);

bool _bilirubinName(String label) =>
    RegExp(r'bilirubin', caseSensitive: false).hasMatch(label);

bool _zipUnitsPlausible(List<String> labels, List<String> groups) {
  for (var i = 0; i < labels.length; i++) {
    final g = groups[i].toLowerCase();
    final hasUl = RegExp(r'\bu/?l\b').hasMatch(g);
    final hasMg = RegExp(r'\bmg/?dl\b').hasMatch(g);
    final hasGd = RegExp(r'\bg/?dl\b').hasMatch(g);
    if (_enzymeName(labels[i]) && (hasMg || hasGd)) return false;
    if (_bilirubinName(labels[i]) && hasUl) return false;
  }
  return true;
}


/// Max lines to look back from an orphan value+unit line for a bare label.
const int kOrphanLabelLookback = 6;

final _orphanValueUnitRe = RegExp(
  r'^([<>]?\d+(?:\.\d+)?)\s*(?:[HL]\*?)?\s+'
  r'([A-Za-z/%µμ][A-Za-z0-9/%µμ^.\-]*)'
  r'(?:\s+(?:'
  r'(\d+(?:\.\d+)?)\s*[-–to]+\s*(\d+(?:\.\d+)?)|'
  r'up\s*to\s*(\d+(?:\.\d+)?)|'
  r'<\s*(\d+(?:\.\d+)?)'
  r'))?\s*$',
  caseSensitive: false,
);

bool _lineAlreadyHasLabValue(String line) =>
    matchSameLineLabRow(line) != null ||
    matchSameLineRangeUnitLabRow(line) != null ||
    matchDottedLabRow(line) != null;

bool _orphanUnitsPlausible(String label, String unit) {
  final u = unit.toLowerCase();
  final hasUl = RegExp(r'\bu/?l\b').hasMatch(u) || u == 'uil';
  final hasMg = RegExp(r'\bmg/?dl\b').hasMatch(u) || u == 'mgidl';
  final hasGd = RegExp(r'\bg/?dl\b').hasMatch(u) || u == 'gidl';
  if (_enzymeName(label) && (hasMg || hasGd)) return false;
  if (_bilirubinName(label) && hasUl) return false;
  // Protein / albumin / globulin expect g/dL family.
  if (RegExp(r'\b(albumin|globulin|total\s*protein|protein)\b', caseSensitive: false)
          .hasMatch(label) &&
      hasUl) {
    return false;
  }
  return true;
}

/// Attach orphan `65 U/L 5-40` lines to the nearest prior bare analyte label.
///
/// Android ML Kit often separates the name column from value+unit+range, or
/// drops the name from that row after geometry stitch. Never invents values —
/// only joins an existing label within [kOrphanLabelLookback] lines when units
/// are plausible.
String attachOrphanLabValueLines(String raw) {
  final lines = [
    for (final l in raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.length < 2) return raw;

  final usedLabels = <int>{};
  final out = List<String>.from(lines);

  for (var i = 0; i < out.length; i++) {
    final m = _orphanValueUnitRe.firstMatch(out[i]);
    if (m == null) continue;
    final unit = (m.group(2) ?? '').trim();
    if (unit.isEmpty) continue;
    // Skip accession-looking magnitudes.
    final value = (m.group(1) ?? '').trim();
    if (isAccessionLikeValue(value, unit: unit)) continue;

    int? labelAt;
    for (var back = 1; back <= kOrphanLabelLookback && i - back >= 0; back++) {
      final li = i - back;
      if (usedLabels.contains(li)) continue;
      final cand = out[li];
      if (_lineAlreadyHasLabValue(cand)) continue;
      if (!looksLikeAnalyteLabelLine(cand)) continue;
      // Stop if we hit another orphan/value row — label must be contiguous-ish.
      if (back > 1) {
        final between = out[i - back + 1];
        if (_orphanValueUnitRe.hasMatch(between) ||
            _valueLineRe.hasMatch(between) ||
            _valueUnitLineRe.hasMatch(between)) {
          break;
        }
        // Allow short method noise between label and value.
        if (!looksLikeAnalyteLabelLine(between) &&
            !_methodNoiseLine.hasMatch(between) &&
            between.length > 40) {
          break;
        }
      }
      if (!_orphanUnitsPlausible(cand, unit)) continue;
      labelAt = li;
      break;
    }
    if (labelAt == null) continue;

    // Prefer closest label (search already goes nearest-first).
    usedLabels.add(labelAt);
    // Keep full orphan text after the label (value unit range).
    out[labelAt] = '${out[labelAt]} ${out[i]}';
    out[i] = ''; // drop orphan line
  }

  return out.where((l) => l.trim().isNotEmpty).join('\n');
}

/// Reflow Syncfusion word-per-line / column-broken PDF extracts into lab rows.
///
/// Agilus-style tables often arrive as:
/// `INSULIN,` / `FASTING` / `SERUM` / `14.7` / `2.6` / `-` / `24.9` / `mU/L`
/// → `INSULIN, FASTING SERUM` + `14.7` + `2.6 - 24.9` + `mU/L`
String reflowBrokenPdfLabText(String raw) {
  var lines = [
    for (final l in raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.length < 4) return raw;

  // Merge lone dash between two numeric lines into a reference range.
  final mergedRange = <String>[];
  var i = 0;
  while (i < lines.length) {
    if (i + 2 < lines.length &&
        RegExp(r'^\d+(?:\.\d+)?$').hasMatch(lines[i]) &&
        RegExp(r'^[-–—]$').hasMatch(lines[i + 1]) &&
        RegExp(r'^\d+(?:\.\d+)?$').hasMatch(lines[i + 2])) {
      mergedRange.add('${lines[i]} - ${lines[i + 2]}');
      i += 3;
      continue;
    }
    mergedRange.add(lines[i]);
    i++;
  }
  lines = mergedRange;

  final shortFrac = lines
          .where((l) => !l.contains(' ') && l.length <= 20)
          .length /
      lines.length;
  // Only reflow when the page looks column-broken (many one-token lines).
  if (shortFrac < 0.45) return lines.join('\n');

  final pageMarker = RegExp(r'^--- page \d+', caseSensitive: false);
  final out = <String>[];
  final buf = <String>[];

  bool isValueish(String t) =>
      RegExp(r'^[<>]?\d+(?:\.\d+)?(?:\s*(?:[HL]\*?))?$', caseSensitive: false)
          .hasMatch(t) ||
      RegExp(
        r'^\d+(?:\.\d+)?\s*[-–to]+\s*\d+(?:\.\d+)?$',
        caseSensitive: false,
      ).hasMatch(t) ||
      (_labUnitToken.hasMatch(t) && t.length <= 12 && !t.contains(' '));

  bool isLabelFrag(String t) {
    if (pageMarker.hasMatch(t)) return false;
    if (isValueish(t)) return false;
    if (_methodNoiseLine.hasMatch(t)) return false;
    if (isLabSectionOrPanelTitle(t)) return false;
    if (_headerNoise.hasMatch(t)) return false;
    if (_refBandLabelLine.hasMatch(t)) return false;
    // Single token or comma-tailed analyte fragment.
    if (RegExp(r'^[A-Za-z][A-Za-z0-9,\-]{0,28},?$').hasMatch(t)) return true;
    if (t.length <= 28 &&
        RegExp(r'^[A-Za-z(]').hasMatch(t) &&
        !RegExp(r'\d').hasMatch(t) &&
        t.split(RegExp(r'\s+')).length <= 3) {
      return true;
    }
    return false;
  }

  void flushBuf() {
    if (buf.isEmpty) return;
    out.add(buf.join(' '));
    buf.clear();
  }

  for (final line in lines) {
    if (pageMarker.hasMatch(line)) {
      flushBuf();
      out.add(line);
      continue;
    }
    if (isLabelFrag(line)) {
      buf.add(line.replaceAll(RegExp(r',$'), ',').replaceAll(RegExp(r',\s*$'), ','));
      final joined = buf.join(' ');
      // Agilus prints the analyte twice (section header + row). Flush when a
      // specimen word closes the name so soft-alias length stays honest.
      if (RegExp(
            r'\b(serum|plasma|blood|urine|whole\s*blood)\s*$',
            caseSensitive: false,
          ).hasMatch(joined) ||
          buf.length >= 6) {
        flushBuf();
      }
      continue;
    }
    flushBuf();
    out.add(line);
  }
  flushBuf();
  return out.join('\n');
}

/// Drop Agilus / Redcliffe admin footer lines when result rows are also present.
String stripOcrFooterNoise(String raw) {
  final lines = [
    for (final l in raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.isEmpty) return raw;
  // Import late to avoid circular deps — footer detector lives in ocr_layout.
  // Inline the same patterns used by isOcrFooterNoiseText for pure-Dart tests.
  bool footerish(String t) {
    if (RegExp(r'page\s*\d+\s*of\s*\d+', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    if (RegExp(
      r'^(performed\s*at|view\s*details|view\s*report|possible\s*conditions|'
      r'consultant\s*pathologist|end\s*of\s*report)\b',
      caseSensitive: false,
    ).hasMatch(t)) {
      return true;
    }
    if (RegExp(
      r'\b(ulr\s*no\.?|cin\s*-|agilus\s*diagnostics|'
      r'diagnostic\s*&\s*health|nabl|cap\s*accredited)\b',
      caseSensitive: false,
    ).hasMatch(t)) {
      return true;
    }
    // Address / PIN lines without lab units (lab-agnostic).
    if (RegExp(r'\b\d{5,6}\b').hasMatch(t) &&
        RegExp(
          r'\b(india|uttar\s*pradesh|maharashtra|karnataka|delhi|'
          r'civil\s*lines|pin(?:code)?\s*:?)\b',
          caseSensitive: false,
        ).hasMatch(t) &&
        !_labUnitToken.hasMatch(t)) {
      return true;
    }
    if (RegExp(r'\b(tel|fax|email)\s*[:.]', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    if (RegExp(
      r'[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}',
      caseSensitive: false,
    ).hasMatch(t)) {
      return true;
    }
    if (RegExp(r'\bdr\.?\s+\w+', caseSensitive: false).hasMatch(t) &&
        RegExp(r'\b(md|pathologist)\b', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    return false;
  }

  // Require a real lab unit / decimal result — address lines with PIN codes
  // must not count as "results" or we strip the footer and lose the signal.
  final hasResult = lines.any(
        (l) => _looksLikeResultRow(l) && _labUnitToken.hasMatch(l),
      ) ||
      lines.any((l) => RegExp(
            r'\b(t3|t4|tsh|sgot|sgpt|bilirubin|albumin|ggt|hdl|ldl|'
            r'cholesterol|triglyceride|hemoglobin|wbc|insulin)\b',
            caseSensitive: false,
          ).hasMatch(l) &&
          RegExp(r'\d+(?:\.\d+)?').hasMatch(l));
  if (!hasResult) {
    // Keep text intact so UI can detect footer-only dumps.
    return lines.join('\n');
  }
  return [
    for (final l in lines)
      if (!footerish(l)) l,
  ].join('\n');
}

final _refBandLabelLine = RegExp(
  r'^(non[-\s]?pregnant(?:\s+women)?|pregnant(?:\s+women)?(?:\s*\(.*)?|'
  r'\d+(?:st|nd|rd|th)\s*trimester.*|'
  r'american\s+thyroid\s+association.*|'
  r'adult(?:\s+(?:male|female|men|women))?|'
  r'(?:adult\s+)?(?:male|female|men|women)|'
  r'child(?:ren)?|pediatric|neonatal|newborn|'
  r'desirable|optimal|borderline(?:\s*high)?|high\s*risk|normal|'
  r'\d+\s*[-–]\s*\d+\s*(?:yr|yrs|year|years|mo|mos|month|months)?\b.*|'
  r'(?:age|ages)\s*:?\s*\d+.*)\s*:?\s*$',
  caseSensitive: false,
);

final _labUnitOnlyLine = RegExp(
  r'^(ng/?dL|ug/?dL|µg/?dL|mcg/?dL|uIU/?mL|µIU/?mL|mIU/?mL|mIU/?L|mU/?L|'
  r'mg/?dL|g/?dL|U/?L|IU/?L|mmol/?L|umol/?L|µmol/?L|pg/?mL|ng/?mL|'
  r'%|ratio|/?(?:cu)?mm|/cumm|cells?/?[uµ]?L|10\^?[36]/?[uµ]?L)$',
  caseSensitive: false,
);

final _tableColHeaderLine = RegExp(
  r'biological\s*reference\s*interval|test\s*report\s*status|'
  r'^(?:results?|units?)\s*$|'
  r'results?\s+biological|'
  r'test\s*report\s*status\s+results',
  caseSensitive: false,
);

final _tableWindowEndLine = RegExp(
  r'^(interpretation(?:\(s\))?|performed\s*at|page\s*\d+\s*of\s*\d+|'
  r'view\s*details|view\s*report|end\s*of\s*report|consultant\s*pathologist|'
  r'possible\s*conditions)\b',
  caseSensitive: false,
);

final _patientMetaLine = RegExp(
  r'^(patient|name|age\s*/?\s*sex|sex|gender|dob|drawn|collected|received|'
  r'referred|barcode|lab\s*no\.?|sample\s*(?:id|type)?|registered|'
  r'report\s*(?:date|id)|client|ref\s*\.?|dr\.?\s)\b',
  caseSensitive: false,
);

/// Keep the results table; drop Agilus-style header chrome and footer.
///
/// Window starts after column headers (Results / Biological Reference / Units)
/// or after the last section/panel banner before analytes. Ends at
/// Interpretation(s), PERFORMED AT, or Page N Of M. Lab-agnostic markers;
/// Agilus wording is a booster, not a hard dependency. Never invents values.
String extractLabResultsTableWindow(String raw) {
  final lines = [
    for (final l in raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.length < 4) return raw;

  int? endIdx;
  for (var i = 0; i < lines.length; i++) {
    if (_tableWindowEndLine.hasMatch(lines[i])) {
      endIdx = i;
      break;
    }
  }

  final scanTo = endIdx ?? lines.length;
  int? startIdx;

  for (var i = 0; i < scanTo; i++) {
    if (_tableColHeaderLine.hasMatch(lines[i])) {
      startIdx = i + 1;
    }
  }

  // Prefer first analyte / result line — not "after last banner" (banners can
  // appear mid-table after an analyte name on some OCR dumps).
  if (startIdx == null) {
    for (var i = 0; i < scanTo; i++) {
      final l = lines[i];
      if (isLabSectionOrPanelTitle(l)) continue;
      if (_patientMetaLine.hasMatch(l)) continue;
      if (_refBandLabelLine.hasMatch(l)) continue;
      if (RegExp(r'^diagnostic\s*report\b', caseSensitive: false).hasMatch(l)) {
        continue;
      }
      if (RegExp(r'^---\s*page', caseSensitive: false).hasMatch(l)) continue;
      if (RegExp(r'^agilus\b', caseSensitive: false).hasMatch(l)) continue;
      if (RegExp(r'^nabl', caseSensitive: false).hasMatch(l)) continue;
      if (RegExp(r'^(iso|uhid|patient\s*id)\b', caseSensitive: false)
          .hasMatch(l)) {
        continue;
      }
      if (looksLikeAnalyteLabelLine(l) ||
          _valueLineRe.hasMatch(l) ||
          looksLikeSameLineLabRow(l)) {
        startIdx = i;
        break;
      }
    }
  } else {
    // Column header found — skip leading section banners inside the window.
    while (startIdx! < scanTo && isLabSectionOrPanelTitle(lines[startIdx])) {
      startIdx++;
    }
  }

  if (startIdx == null && endIdx == null) return raw;
  final from = startIdx ?? 0;
  final to = endIdx ?? lines.length;
  if (to <= from) return raw;
  final sliced = lines.sublist(from, to);
  if (sliced.isEmpty) return raw;
  return sliced.join('\n');
}

/// Strip / join biological-band labels stuck between value and unit on one line.
///
/// Agilus photo OCR often emits:
///   `T3 110.00 Non-Pregnant Women ng/dL`
///   `TSH … 2.720 Non` + next line `Pregnant Women pIU/mL`
/// Leave those labels mid-row and [matchSameLineLabRow] treats `Non-Pregnant`
/// as the unit → 0 catalogue hits. Never invents values — only removes chrome.
String stripInlineBiologicalRefLabels(String raw) {
  final lines = [
    for (final l in raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.isEmpty) return raw;

  // Join split "Non" + "Pregnant Women …" (TSH ULTRASENSITIVE OCR wrap).
  final joined = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final t = lines[i];
    if (i + 1 < lines.length &&
        RegExp(r'\bNon\s*$', caseSensitive: false).hasMatch(t) &&
        RegExp(r'^Pregnant\b', caseSensitive: false).hasMatch(lines[i + 1])) {
      joined.add('$t ${lines[i + 1]}'.replaceAll(RegExp(r'[ \t]+'), ' '));
      i++;
      continue;
    }
    joined.add(t);
  }

  // Mid-row band labels between a numeric value and a unit token.
  final midBand = RegExp(
    r'(\d+(?:\.\d+)?)\s+'
    r'(?:Non[-\s]?Pregnant(?:\s+Women)?|Pregnant(?:\s+Women)?|'
    r'Adult(?:\s+(?:Male|Female|Men|Women))?|'
    r'(?:Male|Female|Men|Women))\s+'
    r'(?=(?:ng|ug|µg|mcg|uIU|µIU|mIU|mU|mg|g|U|IU|mmol|umol|µmol|pg|pIU|P)[A-Za-z0-9/%µμ.\-]*)',
    caseSensitive: false,
  );

  final out = <String>[];
  for (final line in joined) {
    var t = line.replaceAllMapped(midBand, (m) => '${m.group(1)} ');
    t = t.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    // Drop pure band / trimester label lines (unit already captured elsewhere).
    if (_refBandLabelLine.hasMatch(t)) continue;
    if (RegExp(
      r'^(\d+(?:st|nd|rd|th)\s*trimester|pregnant\s+women|non[-\s]?pregnant)\b',
      caseSensitive: false,
    ).hasMatch(t) &&
        !_labUnitToken.hasMatch(t) &&
        !RegExp(r'\d+(?:\.\d+)?\s*[-–to]+\s*\d+', caseSensitive: false)
            .hasMatch(t)) {
      continue;
    }
    out.add(t);
  }
  return out.join('\n');
}

/// Collapse multi-line Biological Reference Interval blobs (any analyte).
///
/// Agilus often prints:
///   NAME / value / Non-Pregnant|Adult|Male… / low-high / more bands… / unit
/// → NAME / value / low-high / unit
/// Prefers the first numeric band (Non-Pregnant / Adult usually print first).
/// Never invents values — only keeps an existing range + unit near the analyte.
String collapseBiologicalRefBlobs(String raw) {
  final lines = [
    for (final l in raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.length < 3) return raw;

  final out = <String>[];
  var i = 0;
  while (i < lines.length) {
    final t = lines[i];

    // Skip section banners — do not treat as analytes.
    if (isLabSectionOrPanelTitle(t)) {
      // Drop from stream (chrome); callers already extracted table window.
      i++;
      continue;
    }

    final tokens = t.split(RegExp(r'\s+'));
    final lastTok = tokens.isEmpty ? '' : tokens.last;
    final hasValueTok = RegExp(
      r'^[A-Za-z(][A-Za-z0-9 /:\-\(\),%\.]{0,60}?\s+[<>]?\d+(?:\.\d+)?\b',
    ).hasMatch(t);
    final hasEmbeddedRange = RegExp(r'\d+\s*[-–to]+\s*\d+').hasMatch(t);
    // Bare value on same line (unit may follow on later lines) OR already
    // compact NAME VALUE UNIT waiting for a following range line.
    final sameLineValue = hasValueTok && !hasEmbeddedRange;
    final sameLineWithUnit = hasValueTok &&
        _labUnitToken.hasMatch(lastTok) &&
        !hasEmbeddedRange;

    final isLabel =
        looksLikeAnalyteLabelLine(t) || sameLineValue || sameLineWithUnit;
    if (!isLabel) {
      out.add(t);
      i++;
      continue;
    }

    // Peek: only collapse when a ref-band or multi-line range follows.
    final nextIsRefish = i + 1 < lines.length &&
        (_refBandLabelLine.hasMatch(lines[i + 1]) ||
            _rangeLineRe.hasMatch(lines[i + 1]) ||
            (RegExp(r'^[<>]?\d+(?:\.\d+)?\s*(?:[HL]\*?)?\s*$',
                        caseSensitive: false)
                    .hasMatch(lines[i + 1]) &&
                i + 2 < lines.length &&
                (_refBandLabelLine.hasMatch(lines[i + 2]) ||
                    _rangeLineRe.hasMatch(lines[i + 2]))));

    if (!nextIsRefish && !sameLineValue && !sameLineWithUnit) {
      // Still allow: label, bare value, then ref band.
      if (!(i + 1 < lines.length &&
          RegExp(r'^[<>]?\d+(?:\.\d+)?\s*(?:[HL]\*?)?\s*$',
                  caseSensitive: false)
              .hasMatch(lines[i + 1]))) {
        out.add(t);
        i++;
        continue;
      }
    }

    out.add(t);
    i++;
    // Optional bare value line.
    if (i < lines.length &&
        RegExp(r'^[<>]?\d+(?:\.\d+)?\s*(?:[HL]\*?)?\s*$', caseSensitive: false)
            .hasMatch(lines[i]) &&
        !sameLineValue) {
      out.add(lines[i]);
      i++;
    }

    String? keptRange;
    String? unit;
    while (i < lines.length) {
      final peek = lines[i];
      if (_refBandLabelLine.hasMatch(peek)) {
        i++;
        continue;
      }
      // "Pregnant Women pIU/mL" / "Non-Pregnant Women ng/dL" — band + unit.
      final bandPlusUnit = RegExp(
        r'^(?:non[\-\s]?pregnant(?:\s+women)?|pregnant(?:\s+women)?)\s+'
        r'([A-Za-z/%µμ][A-Za-z0-9/%µμ^.\-]*)\s*$',
        caseSensitive: false,
      ).firstMatch(peek);
      if (bandPlusUnit != null) {
        unit ??= bandPlusUnit.group(1);
        i++;
        continue;
      }
      // "1st Trimester:105.0 - 230.0" or "Desirable <200" on one line
      if (RegExp(
        r'^(\d+(?:st|nd|rd|th)\s*trimester|desirable|optimal|borderline|normal|'
        r'high\s*risk).*\d',
        caseSensitive: false,
      ).hasMatch(peek)) {
        // Prefer first plain numeric range; skip trimester/desirable extras
        // unless we have no range yet and this embeds one.
        final embedded = RegExp(
          r'(\d+(?:\.\d+)?)\s*[-–to]+\s*(\d+(?:\.\d+)?)',
          caseSensitive: false,
        ).firstMatch(peek);
        final upTo = RegExp(
          r'(?:<\s*|up\s*to\s*)(\d+(?:\.\d+)?)',
          caseSensitive: false,
        ).firstMatch(peek);
        if (keptRange == null && embedded != null) {
          keptRange = '${embedded.group(1)} - ${embedded.group(2)}';
        } else if (keptRange == null && upTo != null) {
          keptRange = '<${upTo.group(1)}';
        }
        i++;
        continue;
      }
      final range = _rangeLineRe.firstMatch(peek);
      if (range != null) {
        keptRange ??= peek;
        i++;
        continue;
      }
      if (_labUnitOnlyLine.hasMatch(peek) ||
          (_labUnitToken.hasMatch(peek) &&
              peek.length <= 16 &&
              !peek.contains(' '))) {
        unit = peek;
        i++;
        break;
      }
      // Next analyte / section / interpretation → stop.
      if (isLabSectionOrPanelTitle(peek) ||
          looksLikeAnalyteLabelLine(peek) ||
          _tableWindowEndLine.hasMatch(peek) ||
          RegExp(r'^interpretation\b', caseSensitive: false).hasMatch(peek)) {
        break;
      }
      // Skip leftover pregnancy / sex-band / association prose fragments.
      if (RegExp(
        r'pregnant|trimester|non[-\s]?pregnant|women|male|female|adult|'
        r'desirable|optimal|borderline|american\s+thyroid|association|'
        r'as\s+per\b',
        caseSensitive: false,
      ).hasMatch(peek)) {
        i++;
        continue;
      }
      break;
    }
    // Prefer one compact Agilus row: LABEL VALUE RANGE UNIT (unit after range).
    if (keptRange != null || unit != null) {
      final head = out.isNotEmpty ? out.removeLast() : null;
      String? valuePart;
      String labelPart;
      if (head != null &&
          RegExp(r'^[<>]?\d+(?:\.\d+)?\s*(?:[HL]\*?)?\s*$',
                  caseSensitive: false)
              .hasMatch(head) &&
          out.isNotEmpty) {
        valuePart = head;
        labelPart = out.removeLast();
      } else if (head != null &&
          RegExp(
            r'^[A-Za-z(].{0,60}?\s+[<>]?\d+(?:\.\d+)?\b',
          ).hasMatch(head)) {
        // NAME VALUE [UNIT] + following range → NAME VALUE RANGE UNIT
        final vu = RegExp(
          r'^(.+?)\s+([<>]?\d+(?:\.\d+)?)\s+([A-Za-z/%µμ][A-Za-z0-9/%µμ^.\-]*)$',
        ).firstMatch(head);
        if (vu != null) {
          labelPart = vu.group(1)!.trim();
          valuePart = vu.group(2);
          unit ??= vu.group(3);
        } else {
          final nv = RegExp(
            r'^(.+?)\s+([<>]?\d+(?:\.\d+)?)$',
          ).firstMatch(head);
          if (nv != null) {
            labelPart = nv.group(1)!.trim();
            valuePart = nv.group(2);
          } else {
            labelPart = head;
            valuePart = null;
          }
        }
      } else {
        if (head != null) out.add(head);
        if (keptRange != null) out.add(keptRange);
        if (unit != null) out.add(unit);
        continue;
      }
      if (unit != null && keptRange != null) {
        if (valuePart != null) {
          out.add('$labelPart $valuePart $keptRange $unit');
        } else {
          out.add('$labelPart $keptRange $unit');
        }
      } else {
        // Incomplete pair — keep pieces (never invent).
        if (valuePart != null) {
          out.add(unit != null
              ? '$labelPart $valuePart $unit'
              : '$labelPart $valuePart');
        } else {
          out.add(labelPart);
        }
        if (keptRange != null) out.add(keptRange);
        if (unit != null && valuePart == null) out.add(unit);
      }
    }
  }
  return out.join('\n');
}

/// @Deprecated — use [collapseBiologicalRefBlobs] (pregnancy is one band family).
String collapsePregnancyRefBlobs(String raw) => collapseBiologicalRefBlobs(raw);

/// Merge Vision/ML Kit stacked rows: label(+label…) then value/unit/range groups
/// become same-line rows so pairing cannot cross-borrow values.
String stitchStackedLabRows(String raw) {
  final lines = [
    for (final l in raw.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.isEmpty) return raw;

  final out = <String>[];
  var i = 0;
  while (i < lines.length) {
    if (!looksLikeAnalyteLabelLine(lines[i])) {
      out.add(lines[i]);
      i++;
      continue;
    }

    final runStart = i;
    final labels = <String>[];
    while (i < lines.length && looksLikeAnalyteLabelLine(lines[i])) {
      labels.add(lines[i]);
      i++;
    }
    final afterLabels = i;

    final groups = <String>[];
    var cursor = afterLabels;
    while (cursor < lines.length && groups.length < labels.length) {
      final t = lines[cursor];
      if (looksLikeAnalyteLabelLine(t)) break;

      String? value;
      var unit = '';
      var range = '';

      final vu = _valueUnitLineRe.firstMatch(t);
      final vo = _valueLineRe.firstMatch(t);
      if (vu != null) {
        value = vu.group(1);
        unit = vu.group(2) ?? '';
        // Same-line range / up-to captured by expanded _valueUnitLineRe.
        if (vu.groupCount >= 4 && vu.group(3) != null && vu.group(4) != null) {
          range = '${vu.group(3)}-${vu.group(4)}';
        } else if (vu.groupCount >= 5 && vu.group(5) != null) {
          range = 'up to ${vu.group(5)}';
        } else if (vu.groupCount >= 6 && vu.group(6) != null) {
          range = '<${vu.group(6)}';
        }
        cursor++;
      } else if (vo != null) {
        value = vo.group(1);
        cursor++;
        if (cursor < lines.length &&
            _unitLineRe.hasMatch(lines[cursor]) &&
            !_valueLineRe.hasMatch(lines[cursor]) &&
            !looksLikeAnalyteLabelLine(lines[cursor])) {
          unit = lines[cursor];
          cursor++;
        }
      } else {
        break;
      }

      // Redcliffe puts "-" in the units column for ratios — skip before range.
      if (cursor < lines.length &&
          RegExp(r'^[-–—−]$').hasMatch(lines[cursor].trim())) {
        cursor++;
      }

      if (range.isEmpty &&
          cursor < lines.length &&
          _rangeLineRe.hasMatch(lines[cursor])) {
        range = lines[cursor];
        cursor++;
      }

      final buf = StringBuffer(value!);
      if (unit.isNotEmpty) buf.write(' $unit');
      if (range.isNotEmpty) buf.write(' $range');
      groups.add(buf.toString());
    }

    if (labels.length == groups.length &&
        labels.isNotEmpty &&
        _zipUnitsPlausible(labels, groups)) {
      for (var k = 0; k < labels.length; k++) {
        out.add('${labels[k]} ${groups[k]}');
      }
      i = cursor;
    } else {
      // Keep original lines — do not invent cross-paired rows.
      out.add(lines[runStart]);
      i = runStart + 1;
    }
  }
  return out.join('\n');
}

/// Same-line lab row (name · value · optional unit · optional range).
class SameLineLabMatch {
  const SameLineLabMatch({
    required this.label,
    required this.value,
    this.unit = '',
    this.refLow,
    this.refHigh,
    this.rangeBeforeUnit = false,
  });

  final String label;
  final String value;
  final String unit;
  final double? refLow;
  final double? refHigh;

  /// True when layout is name · value · range · unit (Agilus).
  final bool rangeBeforeUnit;
}

/// Label charset includes `:` so Redcliffe `Albumin :Globulin Ratio` matches
/// (slash forms like `SGOT/SGPT Ratio` already worked).
final _sameLineRangeUnitRe = RegExp(
  r'^([A-Za-z(][A-Za-z0-9 /:\-\(\),%\.]{0,80}?)\s*(?:[:=]|\s)\s*'
  r'([<>]?\d+(?:\.\d+)?)\s*(?:[HL]\*?)?\s+'
  r'(\d+(?:\.\d+)?)\s*[-–to]+\s*(\d+(?:\.\d+)?)\s+'
  r'([A-Za-z/%µμ\-][A-Za-z0-9/%µμ^.\-]*)\s*$',
  caseSensitive: false,
);

final _sameLineLabRe = RegExp(
  r'^([A-Za-z(][A-Za-z0-9 /:\-\(\),%\.]{0,80}?)\s*(?:[:=]|\s)\s*'
  r'([<>]?\d+(?:\.\d+)?)\s*(?:[HL]\*?)?\s*'
  r'([A-Za-z/%µμ\-][A-Za-z0-9/%µμ^.\-]*)?'
  r'(?:\s*(?:\(|\[)?\s*(\d+(?:\.\d+)?)\s*[-–to]+\s*(\d+(?:\.\d+)?))?',
  caseSensitive: false,
);

final _dottedLabRe = RegExp(
  r'^([A-Za-z(][A-Za-z0-9 /:\-\(\),%\.]{1,80}?)\s*[\.·…]{2,}\s*([<>]?\d+(?:\.\d+)?)\s*(?:[HL]\*?)?\s*([A-Za-z/%µμ\-^0-9\.\-]*)?',
  caseSensitive: false,
);

/// Collapse PDF placeholders (`-`, em-dash) and flag letters mistaken for units.
String sanitizeReportedLabUnit(String unit) {
  final t = unit.trim();
  if (t.isEmpty) return '';
  if (t == '-' || t == '–' || t == '—' || t == '−' || t == '.') return '';
  if (t == 'H' || t == 'L' || t == 'h' || t == 'l') return '';
  return t;
}

/// Agilus layout: name · value · [optional ref-band prose] · range · unit
/// (unit after range). Works for any analyte after biological-ref collapse.
final _agilusLayoutRowRe = RegExp(
  r'^([A-Za-z(][A-Za-z0-9 /:\-\(\),%\.]{0,80}?)\s+'
  r'([<>]?\d+(?:\.\d+)?)\s+'
  r'(?:.*?\s+)?'
  r'(\d+(?:\.\d+)?)\s*[-–to]+\s*(\d+(?:\.\d+)?)\s+'
  r'([A-Za-z/%µμ\-][A-Za-z0-9/%µμ^.\-]*)\s*$',
  caseSensitive: false,
);

/// Also: name · value · <N or up-to N · unit (triglycerides-style).
final _agilusLayoutUpToRowRe = RegExp(
  r'^([A-Za-z(][A-Za-z0-9 /:\-\(\),%\.]{0,80}?)\s+'
  r'([<>]?\d+(?:\.\d+)?)\s+'
  r'(?:.*?\s+)?'
  r'(?:<\s*|up\s*to\s*)(\d+(?:\.\d+)?)\s+'
  r'([A-Za-z/%µμ\-][A-Za-z0-9/%µμ^.\-]*)\s*$',
  caseSensitive: false,
);

SameLineLabMatch? matchAgilusLayoutRow(String line) {
  final t = line.trim();
  final m = _agilusLayoutRowRe.firstMatch(t);
  if (m != null) {
    return SameLineLabMatch(
      label: m.group(1)!.trim(),
      value: m.group(2)!.replaceAll(RegExp(r'\s'), ''),
      unit: sanitizeReportedLabUnit(m.group(5) ?? ''),
      refLow: double.tryParse(m.group(3) ?? ''),
      refHigh: double.tryParse(m.group(4) ?? ''),
      rangeBeforeUnit: true,
    );
  }
  final u = _agilusLayoutUpToRowRe.firstMatch(t);
  if (u != null) {
    return SameLineLabMatch(
      label: u.group(1)!.trim(),
      value: u.group(2)!.replaceAll(RegExp(r'\s'), ''),
      unit: sanitizeReportedLabUnit(u.group(4) ?? ''),
      refHigh: double.tryParse(u.group(3) ?? ''),
      rangeBeforeUnit: true,
    );
  }
  return null;
}

/// Back-compat alias for thyroid-era call sites / tests.
SameLineLabMatch? matchAgilusThyroidRow(String line) =>
    matchAgilusLayoutRow(line);

SameLineLabMatch? matchSameLineRangeUnitLabRow(String line) {
  final ag = matchAgilusLayoutRow(line);
  if (ag != null) return ag;
  final m = _sameLineRangeUnitRe.firstMatch(line.trim());
  if (m == null) return null;
  return SameLineLabMatch(
    label: m.group(1)!.trim(),
    value: m.group(2)!.replaceAll(RegExp(r'\s'), ''),
    unit: sanitizeReportedLabUnit(m.group(5) ?? ''),
    refLow: double.tryParse(m.group(3) ?? ''),
    refHigh: double.tryParse(m.group(4) ?? ''),
    rangeBeforeUnit: true,
  );
}

SameLineLabMatch? matchSameLineLabRow(String line) {
  final m = _sameLineLabRe.firstMatch(line.trim());
  if (m == null) return null;
  var unit = sanitizeReportedLabUnit(m.group(3) ?? '');
  // Biological-band words are not units (Agilus Non-Pregnant mid-row).
  if (unit.isNotEmpty &&
      RegExp(
        r'^(non|pregnant|women|adult|male|female|men|trimester)',
        caseSensitive: false,
      ).hasMatch(unit)) {
    unit = '';
  }
  // If capture grabbed mid-row prose, look for a real unit only in the
  // unmatched suffix — never rescans the label (A/G "Ratio" is part of name).
  final hasRange = m.group(4) != null || m.group(5) != null;
  if (unit.isEmpty && !hasRange) {
    final rest = line.trim().substring(m.end).trim();
    if (rest.isNotEmpty) {
      final um = _labUnitToken.firstMatch(rest);
      if (um != null) {
        unit = sanitizeReportedLabUnit(um.group(0)!);
      }
    }
  } else if (unit.isNotEmpty &&
      !_labUnitToken.hasMatch(unit) &&
      RegExp(r'[A-Za-z]{4,}').hasMatch(unit) &&
      !RegExp(r'[/µμ%]').hasMatch(unit)) {
    // Drop long prose tokens; keep OCR units like Pg/dL / pIU/mL for fold.
    final rest = line.trim().substring(m.end).trim();
    final um = rest.isNotEmpty ? _labUnitToken.firstMatch(rest) : null;
    unit = um != null ? sanitizeReportedLabUnit(um.group(0)!) : '';
  }
  return SameLineLabMatch(
    label: m.group(1)!.trim(),
    value: m.group(2)!.replaceAll(RegExp(r'\s'), ''),
    unit: unit,
    refLow: double.tryParse(m.group(4) ?? ''),
    refHigh: double.tryParse(m.group(5) ?? ''),
  );
}

SameLineLabMatch? matchDottedLabRow(String line) {
  final m = _dottedLabRe.firstMatch(line.trim());
  if (m == null) return null;
  return SameLineLabMatch(
    label: m.group(1)!.trim(),
    value: m.group(2)!.replaceAll(RegExp(r'\s'), ''),
    unit: sanitizeReportedLabUnit(m.group(3) ?? ''),
  );
}

bool looksLikeSameLineLabRow(String line) =>
    matchAgilusLayoutRow(line) != null ||
    matchSameLineRangeUnitLabRow(line) != null ||
    matchSameLineLabRow(line) != null ||
    matchDottedLabRow(line) != null;


/// Light prep for multi-band extract — table window + chrome strip, **no** collapse
/// and **no** stripInlineBiologicalRefLabels (that drops standalone stage captions).
String prepTextForBiologicalBandExtract(String raw) {
  var t = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  t = stripInterpretationBlocks(t);
  t = stripOcrFooterNoise(t);
  t = extractLabResultsTableWindow(t);
  t = reflowBrokenPdfLabText(t);
  return t;
}

final _embeddedLabeledRange = RegExp(
  r'^(.+?)[:\s]+(\d+(?:\.\d+)?)\s*[-–to]+\s*(\d+(?:\.\d+)?)\s*$',
  caseSensitive: false,
);
final _embeddedLabeledUpTo = RegExp(
  r'^(.+?)[:\s]+(?:<\s*|up\s*to\s*|≥\s*|>=\s*)(\d+(?:\.\d+)?)\s*$',
  caseSensitive: false,
);
final _plainRangeCapture = RegExp(
  r'^(?:(\d+(?:\.\d+)?)\s*[-–to]+\s*(\d+(?:\.\d+)?)|up\s*to\s*(\d+(?:\.\d+)?)|<\s*(\d+(?:\.\d+)?))\s*$',
  caseSensitive: false,
);

/// Walk Agilus-style biological-ref blobs and collect labeled stages per analyte.
///
/// Keyed by normalized analyte label (letters/digits only). Empty when the slip
/// only has a single unlabeled range.
Map<String, List<RefBand>> extractBiologicalRefBandsByLabel(String raw) {
  final lines = [
    for (final l in raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  final out = <String, List<RefBand>>{};
  if (lines.length < 3) return out;

  var i = 0;
  while (i < lines.length) {
    final t = lines[i];
    if (isLabSectionOrPanelTitle(t)) {
      i++;
      continue;
    }
    final tokens = t.split(RegExp(r'\s+'));
    final lastTok = tokens.isEmpty ? '' : tokens.last;
    final hasValueTok = RegExp(
      r'^[A-Za-z(][A-Za-z0-9 /:\-\(\),%\.]{0,60}?\s+[<>]?\d+(?:\.\d+)?\b',
    ).hasMatch(t);
    final hasEmbeddedRange = RegExp(r'\d+\s*[-–to]+\s*\d+').hasMatch(t);
    final sameLineValue = hasValueTok && !hasEmbeddedRange;
    final sameLineWithUnit = hasValueTok &&
        _labUnitToken.hasMatch(lastTok) &&
        !hasEmbeddedRange;
    final isLabel =
        looksLikeAnalyteLabelLine(t) || sameLineValue || sameLineWithUnit;
    if (!isLabel) {
      i++;
      continue;
    }

    final nextIsRefish = i + 1 < lines.length &&
        (_refBandLabelLine.hasMatch(lines[i + 1]) ||
            _rangeLineRe.hasMatch(lines[i + 1]) ||
            (RegExp(r'^[<>]?\d+(?:\.\d+)?\s*(?:[HL]\*?)?\s*$',
                        caseSensitive: false)
                    .hasMatch(lines[i + 1]) &&
                i + 2 < lines.length &&
                (_refBandLabelLine.hasMatch(lines[i + 2]) ||
                    _rangeLineRe.hasMatch(lines[i + 2]))));
    if (!nextIsRefish && !sameLineValue && !sameLineWithUnit) {
      if (!(i + 1 < lines.length &&
          RegExp(r'^[<>]?\d+(?:\.\d+)?\s*(?:[HL]\*?)?\s*$',
                  caseSensitive: false)
              .hasMatch(lines[i + 1]))) {
        i++;
        continue;
      }
    }

    // Analyte key from head line.
    String labelPart = t;
    if (sameLineValue || sameLineWithUnit) {
      final vu = RegExp(
        r'^(.+?)\s+([<>]?\d+(?:\.\d+)?)\s+([A-Za-z/%µμ][A-Za-z0-9/%µμ^.\-]*)$',
      ).firstMatch(t);
      final nv = RegExp(r'^(.+?)\s+([<>]?\d+(?:\.\d+)?)$').firstMatch(t);
      if (vu != null) {
        labelPart = vu.group(1)!.trim();
      } else if (nv != null) {
        labelPart = nv.group(1)!.trim();
      }
    }
    i++;
    // Optional bare value.
    if (i < lines.length &&
        RegExp(r'^[<>]?\d+(?:\.\d+)?\s*(?:[HL]\*?)?\s*$', caseSensitive: false)
            .hasMatch(lines[i]) &&
        !sameLineValue) {
      i++;
    }

    final bands = <RefBand>[];
    String? pendingLabel;
    while (i < lines.length) {
      final peek = lines[i];
      // Embedded "1st Trimester:105.0 - 230.0" before band-label regex
      // (trimester.* label pattern would swallow the numbers).
      final embedded = _embeddedLabeledRange.firstMatch(peek);
      if (embedded != null &&
          RegExp(
            r'trimester|desirable|optimal|borderline|normal|high\s*risk|'
            r'pregnant|adult|male|female|diabetic|non',
            caseSensitive: false,
          ).hasMatch(embedded.group(1)!)) {
        bands.add(RefBand(
          label: embedded.group(1)!.trim(),
          low: double.tryParse(embedded.group(2)!),
          high: double.tryParse(embedded.group(3)!),
        ));
        pendingLabel = null;
        i++;
        continue;
      }
      final upEmb = _embeddedLabeledUpTo.firstMatch(peek);
      if (upEmb != null &&
          RegExp(
            r'trimester|desirable|optimal|borderline|normal|high\s*risk|'
            r'diabetic|non',
            caseSensitive: false,
          ).hasMatch(upEmb.group(1)!)) {
        bands.add(RefBand(
          label: upEmb.group(1)!.trim(),
          high: double.tryParse(upEmb.group(2)!),
        ));
        pendingLabel = null;
        i++;
        continue;
      }
      if (_refBandLabelLine.hasMatch(peek) && !RegExp(r'\d').hasMatch(peek)) {
        pendingLabel = peek.replaceAll(RegExp(r':\s*$'), '').trim();
        i++;
        continue;
      }
      final bandPlusUnit = RegExp(
        r'^(?:non[\-\s]?pregnant(?:\s+women)?|pregnant(?:\s+women)?)\s+'
        r'([A-Za-z/%µμ][A-Za-z0-9/%µμ^.\-]*)\s*$',
        caseSensitive: false,
      ).firstMatch(peek);
      if (bandPlusUnit != null) {
        i++;
        break;
      }
      final range = _plainRangeCapture.firstMatch(peek);
      if (range != null) {
        final low = double.tryParse(range.group(1) ?? '');
        final high = double.tryParse(
          range.group(2) ?? range.group(3) ?? range.group(4) ?? '',
        );
        bands.add(RefBand(
          label: pendingLabel,
          low: low,
          high: high,
        ));
        pendingLabel = null;
        i++;
        continue;
      }
      if (_labUnitOnlyLine.hasMatch(peek) ||
          (_labUnitToken.hasMatch(peek) &&
              peek.length <= 16 &&
              !peek.contains(' '))) {
        i++;
        break;
      }
      if (isLabSectionOrPanelTitle(peek) ||
          looksLikeAnalyteLabelLine(peek) ||
          _tableWindowEndLine.hasMatch(peek) ||
          RegExp(r'^interpretation\b', caseSensitive: false).hasMatch(peek)) {
        break;
      }
      if (RegExp(
        r'pregnant|trimester|non[-\s]?pregnant|women|male|female|adult|'
        r'desirable|optimal|borderline|american\s+thyroid|association|'
        r'as\s+per\b',
        caseSensitive: false,
      ).hasMatch(peek)) {
        // Soft label continuation (e.g. "Pregnant Women (As per")
        pendingLabel = [
          if (pendingLabel != null) pendingLabel,
          peek,
        ].join(' ').trim();
        i++;
        continue;
      }
      break;
    }

    final key = _normAnalyteKey(labelPart);
    if (key.length >= 2 && bands.length >= 2) {
      out[key] = bands;
    }
  }
  return out;
}

String _normAnalyteKey(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Match extracted bands onto a parsed catalogue hit.
List<RefBand>? lookupBiologicalRefBands(
  Map<String, List<RefBand>> byLabel, {
  required String parameterName,
  required String parameterCode,
  String? sourceLine,
}) {
  if (byLabel.isEmpty) return null;
  final keys = <String>{
    _normAnalyteKey(parameterName),
    _normAnalyteKey(parameterCode),
  };
  if (sourceLine != null && sourceLine.trim().isNotEmpty) {
    // First token group before a number.
    final m = RegExp(
      r'^([A-Za-z(][A-Za-z0-9 /:\-\(\),%\.]{0,60}?)(?=\s+[<>]?\d)',
    ).firstMatch(sourceLine.trim());
    if (m != null) keys.add(_normAnalyteKey(m.group(1)!));
    keys.add(_normAnalyteKey(sourceLine));
  }
  for (final k in keys) {
    if (k.isEmpty) continue;
    final hit = byLabel[k];
    if (hit != null && hit.length >= 2) return hit;
  }
  // Soft: prefix/contains (allow short codes like t3 / t4)
  for (final k in keys) {
    if (k.length < 2) continue;
    for (final e in byLabel.entries) {
      if (e.key == k || e.key.startsWith(k) || k.startsWith(e.key)) {
        if (e.value.length >= 2) return e.value;
      }
    }
  }
  return null;
}
