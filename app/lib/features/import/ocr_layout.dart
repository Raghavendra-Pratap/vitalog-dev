import 'package:bodyline_core/bodyline_core.dart';
/// Geometry-aware OCR line reconstruction (ML Kit / Vision-style).
///
/// ML Kit often returns left-column analyte names and right-column values as
/// separate [TextBlock]s. Dumping blocks in arrival order yields names then
/// values (or names only). Sorting by Y then X and joining same-row cells
/// restores `Bilirubin Total 0.7 mg/dL` the way macOS Vision bbox sort does.

class OcrBox {
  const OcrBox({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get midY => (top + bottom) / 2;
  double get midX => (left + right) / 2;
  double get height {
    final h = (bottom - top).abs();
    return h < 1 ? 1 : h;
  }
}

/// Admin / footer OCR tokens (Agilus PERFORMED AT, ULR, emails, page X of Y).


/// OCR output with optional WordBoxes for layout-first parse.
class OcrExtractResult {
  const OcrExtractResult({required this.text, this.boxes = const []});
  final String text;
  final List<WordBox> boxes;
}

/// Convert ML Kit / Vision-style [OcrBox]es to core [WordBox] (page coords).
List<WordBox> wordBoxesFromOcrBoxes(
  List<OcrBox> boxes, {
  int page = 1,
  WordBoxSource source = WordBoxSource.ocr,
}) {
  return [
    for (final b in boxes)
      if (b.text.trim().isNotEmpty)
        WordBox(
          text: b.text.trim(),
          x: b.left,
          y: b.top,
          w: (b.right - b.left).abs() < 1 ? 1.0 : (b.right - b.left).abs(),
          h: (b.bottom - b.top).abs() < 1 ? 1.0 : (b.bottom - b.top).abs(),
          conf: 90,
          page: page,
          source: source,
        ),
  ];
}

/// Prefer core layout rebuild; fall back to legacy stitch when sparse.
String layoutTextFromOcrBoxes(List<OcrBox> boxes) {
  final wb = wordBoxesFromOcrBoxes(boxes);
  if (wb.length >= 4) {
    final text = layoutRowsToText(rebuildLayout(wb));
    if (text.trim().isNotEmpty) return text;
  }
  return layoutOcrByGeometry(boxes);
}

bool isOcrFooterNoiseText(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return false;
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
    r'\b(ulr\s*no\.?|cin\s*-|agilus\s*diagnostics|diagnostic\s*&\s*health)\b',
    caseSensitive: false,
  ).hasMatch(t)) {
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
  // Dense address / CIN / PIN lines without lab units (lab-agnostic).
  if (RegExp(r'\b\d{5,6}\b').hasMatch(t) &&
      RegExp(
            r'\b(india|uttar\s*pradesh|maharashtra|karnataka|delhi|'
            r'civil\s*lines|bareilly|pin(?:code)?\s*:?)\b',
            caseSensitive: false,
          ).hasMatch(t) &&
      !RegExp(
        r'\b(mg|g|u|iu|ng|pg|mmol|%|ratio)\b',
        caseSensitive: false,
      ).hasMatch(t)) {
    return true;
  }
  return false;
}

bool _boxLooksLikeLabSignal(String text) {
  final t = text.trim();
  if (t.isEmpty || isOcrFooterNoiseText(t)) return false;
  if (RegExp(r'\b\d{1,4}(?:\.\d+)?\b').hasMatch(t) &&
      RegExp(
        r'\b(mg|g|u|iu|ng|pg|mmol|%|ratio|µ|uIU|mIU)\b',
        caseSensitive: false,
      ).hasMatch(t)) {
    return true;
  }
  // Compact result tokens: 110.00 / 9.57 / 2.720
  if (RegExp(r'^\d{1,4}\.\d{1,3}$').hasMatch(t)) return true;
  // Short analyte names common on Agilus / Redcliffe tables.
  if (RegExp(
        r'^(t3|t4|tsh|alt|ast|sgot|sgpt|ggt|alp|albumin|globulin|bilirubin|'
        r'hdl|ldl|vldl|cholesterol|triglyceride|hemoglobin|wbc|rbc|insulin)\b',
        caseSensitive: false,
      ).hasMatch(t) &&
      t.length <= 48) {
    return true;
  }
  return false;
}

/// Sort boxes top→bottom, left→right; join cells that share a horizontal band.
///
/// When the page has clear lab-result signals, footer/admin boxes are omitted
/// from the primary stitch so Agilus PERFORMED AT / emails do not drown T3/T4.
String layoutOcrByGeometry(
  List<OcrBox> boxes, {
  double rowBandFactor = 0.55,
}) {
  var items = [
    for (final b in boxes)
      if (b.text.trim().isNotEmpty)
        OcrBox(
          text: b.text.trim(),
          left: b.left,
          top: b.top,
          right: b.right,
          bottom: b.bottom,
        ),
  ];
  if (items.isEmpty) return '';

  final hasLabSignal = items.any((b) => _boxLooksLikeLabSignal(b.text));
  final footerItems = <OcrBox>[];
  if (hasLabSignal) {
    final kept = <OcrBox>[];
    for (final b in items) {
      if (isOcrFooterNoiseText(b.text)) {
        footerItems.add(b);
      } else {
        kept.add(b);
      }
    }
    // Only drop footers when enough lab signal remains.
    if (kept.any((b) => _boxLooksLikeLabSignal(b.text))) {
      items = kept;
    }
  }

  items.sort((a, b) {
    final dy = a.midY - b.midY;
    // Loose pre-sort; row clustering decides same-line membership.
    if (dy.abs() > 4) return dy < 0 ? -1 : 1;
    return a.left.compareTo(b.left);
  });

  final rows = <List<OcrBox>>[];
  for (final box in items) {
    if (rows.isEmpty) {
      rows.add([box]);
      continue;
    }
    final row = rows.last;
    final rowMid =
        row.fold<double>(0, (s, b) => s + b.midY) / row.length;
    final rowH =
        row.fold<double>(0, (s, b) => s + b.height) / row.length;
    final thresh = (rowH * rowBandFactor).clamp(8.0, 48.0);
    if ((box.midY - rowMid).abs() <= thresh) {
      row.add(box);
    } else {
      rows.add([box]);
    }
  }

  final out = StringBuffer();
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i]..sort((a, b) => a.left.compareTo(b.left));
    out.write(row.map((b) => b.text).join(' '));
    if (i < rows.length - 1) out.writeln();
  }
  // Append deferred footer at the end (never invents result values).
  if (footerItems.isNotEmpty && out.isNotEmpty) {
    out.writeln();
    footerItems.sort((a, b) {
      final dy = a.midY - b.midY;
      if (dy.abs() > 4) return dy < 0 ? -1 : 1;
      return a.left.compareTo(b.left);
    });
    for (final b in footerItems) {
      out.writeln(b.text);
    }
  }
  return out.toString().trim();
}

/// Slash in `SGOT/AST` often OCR’s as capital I / l / 1 → `SGOTIAST`.
String repairOcrEnzymeSlashLabels(String raw) {
  const pairs = <List<String>>[
    ['SGOT', 'AST'],
    ['SGPT', 'ALT'],
    ['AST', 'SGOT'],
    ['ALT', 'SGPT'],
  ];
  var t = raw;
  for (final p in pairs) {
    final a = p[0];
    final b = p[1];
    // Spaced or single bogus separator: SGOT I AST / SGOTIAST / SGOT|AST
    t = t.replaceAllMapped(
      RegExp(
        '\\b$a\\s*[Il1|/\\\\]\\s*$b\\b',
        caseSensitive: false,
      ),
      (_) => '$a/$b',
    );
    // Fully glued with no separator: SGOTAST (rare)
    t = t.replaceAllMapped(
      RegExp('\\b$a$b\\b', caseSensitive: false),
      (_) => '$a/$b',
    );
  }
  return t;
}

/// Repair slash→I/l/1 OCR junk inside lab units (`UIL`→`U/L`, `mgIdL`→`mg/dL`).
///
/// ML Kit often reads `/` as `I`/`l`/`1` in compact units. Without this,
/// [labUnitsCompatible] rejects real rows (GGT `65 UIL`, Globulin `gIdL`).
String repairOcrLabUnits(String raw) {
  var t = raw;
  // Longer / more specific first.
  const pairs = <List<String>>[
    ['uIUImL', 'uIU/mL'],
    ['uIUlmL', 'uIU/mL'],
    ['µIUImL', 'µIU/mL'],
    ['mIUImL', 'mIU/mL'],
    ['mIUlmL', 'mIU/mL'],
    ['mmolIL', 'mmol/L'],
    ['mmol1L', 'mmol/L'],
    ['umolIL', 'umol/L'],
    ['µmolIL', 'µmol/L'],
    ['mEqIL', 'mEq/L'],
    ['ngImL', 'ng/mL'],
    ['nglmL', 'ng/mL'],
    ['ngIdL', 'ng/dL'],
    ['ngldL', 'ng/dL'],
    ['pgImL', 'pg/mL'],
    ['pglmL', 'pg/mL'],
    ['ugIdL', 'ug/dL'],
    ['ugldL', 'ug/dL'],
    ['ug1dL', 'ug/dL'],
    ['mcgIdL', 'ug/dL'],
    ['mcgldL', 'ug/dL'],
    ['mgIdL', 'mg/dL'],
    ['mgldL', 'mg/dL'],
    ['mg1dL', 'mg/dL'],
    ['mgIdl', 'mg/dL'],
    ['gIdL', 'g/dL'],
    ['gldL', 'g/dL'],
    ['g1dL', 'g/dL'],
    ['gIdl', 'g/dL'],
    ['UIDL', 'U/dL'],
    ['UldL', 'U/dL'],
    ['U1dL', 'U/dL'],
    ['IUIL', 'IU/L'],
    ['IUlL', 'IU/L'],
    ['mUIL', 'mU/L'],
    ['mUlL', 'mU/L'],
    ['UIL', 'U/L'],
    ['UlL', 'U/L'],
    ['U1L', 'U/L'],
    ['UlL', 'U/L'],
  ];
  for (final p in pairs) {
    t = t.replaceAllMapped(
      RegExp('\\b${p[0]}\\b', caseSensitive: false),
      (_) => p[1],
    );
  }
  // Spaced slash-as-I: "U I L" / "mg I dL"
  t = t.replaceAllMapped(
    RegExp(r'\bU\s*[Il1]\s*L\b', caseSensitive: false),
    (_) => 'U/L',
  );
  t = t.replaceAllMapped(
    RegExp(r'\bIU\s*[Il1]\s*L\b', caseSensitive: false),
    (_) => 'IU/L',
  );
  t = t.replaceAllMapped(
    RegExp(r'\bm\s*g\s*[Il1]\s*d\s*[lL]\b'),
    (_) => 'mg/dL',
  );
  t = t.replaceAllMapped(
    RegExp(r'\bg\s*[Il1]\s*d\s*[lL]\b'),
    (_) => 'g/dL',
  );

  // µ misread as P/p (Agilus photo): Pg/dL → ug/dL, pIU/mL → uIU/mL.
  // Keep real pg/mL (picogram) — only repair dL / IU forms.
  t = t.replaceAllMapped(
    RegExp(r'\bP\s*g\s*/\s*d\s*[lL]\b'),
    (_) => 'ug/dL',
  );
  t = t.replaceAllMapped(
    RegExp(r'\bp\s*IU\s*/\s*m\s*[lL]\b', caseSensitive: false),
    (_) => 'uIU/mL',
  );
  t = t.replaceAllMapped(
    RegExp(r'\bP\s*IU\s*/\s*m\s*[lL]\b'),
    (_) => 'uIU/mL',
  );
  t = t.replaceAllMapped(
    RegExp(r'\bp\s*g\s*/\s*d\s*[lL]\b'),
    (_) => 'ug/dL',
  );
  return t;
}

final _labResultValueLine = RegExp(
  r'^([<>]?\d{1,4}(?:\.\d+)?)\s*(?:[HL]\*?)?\s*'
  r'([A-Za-z/%][A-Za-z0-9/%.\-]*)?\s*$',
  caseSensitive: false,
);

final _sameLineHasValue = RegExp(
  r'[A-Za-z]{2,}.*\b\d{1,4}(?:\.\d+)?\b',
);

/// Accession / date-like longs are not lab results.
final _longIdish = RegExp(r'\b\d{6,}\b');

/// True when the dump looks like analyte **names** without result numbers.
///
/// Used for honest UI copy and Android OCR multi-pass — never invent values.
bool ocrLooksLikeLabelsWithoutValues(String text) {
  final lines = [
    for (final l in text.split(RegExp(r'[\r\n]+')))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.length < 2) return false;

  var labelish = 0;
  var valueish = 0;
  for (final line in lines) {
    if (_labResultValueLine.hasMatch(line)) {
      final n = RegExp(r'\d{1,4}(?:\.\d+)?').firstMatch(line)?.group(0);
      if (n != null && !_longIdish.hasMatch(n) && n.length <= 6) {
        valueish++;
      }
      continue;
    }
    if (_sameLineHasValue.hasMatch(line) &&
        !_longIdish.hasMatch(line) &&
        line.length < 90) {
      // "Bilirubin Total 0.7 mg/dL" or stitched row
      if (RegExp(r'\b\d{1,4}\.\d+\b').hasMatch(line) ||
          RegExp(r'\b\d{1,3}\b').hasMatch(line) &&
              RegExp(
                r'\b(mg|g|u|iu|ng|pg|mmol|%|ratio)\b',
                caseSensitive: false,
              ).hasMatch(line)) {
        valueish++;
        continue;
      }
    }
    // Short analyte-like name lines (no digits).
    if (!RegExp(r'\d').hasMatch(line) &&
        RegExp(r'[A-Za-z]{3,}').hasMatch(line) &&
        line.length <= 70 &&
        line.split(RegExp(r'\s+')).length <= 8 &&
        !RegExp(
          r'^(patient|sample|referred|report|test description|iso|dob)\b',
          caseSensitive: false,
        ).hasMatch(line)) {
      labelish++;
    }
  }
  return labelish >= 2 && valueish == 0;
}

/// True when OCR dump is mostly lab footer / admin chrome with no result values.
///
/// Agilus photos often capture Page N Of M + PERFORMED AT + emails instead of
/// the results table — never invent values; ask the user to reframe or use PDF.
bool ocrLooksLikeFooterWithoutResults(String text) {
  final lines = [
    for (final l in text.split(RegExp(r'[\r\n]+')))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.isEmpty) return false;
  var footerish = 0;
  for (final line in lines) {
    if (isOcrFooterNoiseText(line)) footerish++;
  }
  if (footerish < 2) return false;
  // Decimal lab values with units — not footer chrome.
  final hasLabDecimal = RegExp(
        r'\b\d{1,4}\.\d+\b',
      ).hasMatch(text) &&
      RegExp(
        r'\b(mg|g|u|iu|ng|pg|mmol|ratio|µ|ug)/?',
        caseSensitive: false,
      ).hasMatch(text);
  if (hasLabDecimal) return false;
  if (RegExp(
        r'\b(t3|t4|tsh|sgot|sgpt|bilirubin|albumin|ggt|hdl|ldl|cholesterol|'
        r'triglyceride|hemoglobin|insulin)\b',
        caseSensitive: false,
      ).hasMatch(text) &&
      RegExp(r'\b\d{1,4}(?:\.\d+)?\b').hasMatch(text) &&
      RegExp(
        r'\b(mg|g|u/?l|iu|ng|pg|ratio)\b',
        caseSensitive: false,
      ).hasMatch(text)) {
    return false;
  }
  return footerish >= (lines.length / 2).ceil() || footerish >= 3;
}

/// Rough count of plausible lab result tokens (for multi-pass comparison).
int ocrLabValueSignal(String text) {
  var n = 0;
  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    final t = line.trim();
    if (t.isEmpty) continue;
    if (_labResultValueLine.hasMatch(t) && !_longIdish.hasMatch(t)) {
      n++;
      continue;
    }
    if (RegExp(r'\b\d{1,4}\.\d+\b').hasMatch(t) && t.length < 80) n++;
  }
  return n;
}
