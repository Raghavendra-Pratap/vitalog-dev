import 'lab_parse_quality.dart';
import 'ocr_layout.dart';

/// Clean OCR / paste text before catalogue matching (on-device only).
String normalizeOcrLabText(String raw) {
  var t = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // Common OCR glyph mistakes on Indian lab PDFs / photos.
  const replacements = <String, String>{
    'µ': 'u',
    'μ': 'u',
    'Μ': 'M',
    '–': '-',
    '—': '-',
    '−': '-',
    '·': '.',
    '•': ' ',
    '\u00a0': ' ',
    '\u200b': '',
  };
  for (final e in replacements.entries) {
    t = t.replaceAll(e.key, e.value);
  }

  // Soft hyphens / broken words across lines: "Haemo-\nglobin" → "Haemoglobin"
  // Require a letter before '-' so PDF page markers (`---`) and ref ranges
  // (`2.6\n-\n24.9`) are not destroyed.
  t = t.replaceAll(RegExp(r'(?<=[A-Za-z])-\n\s*'), '');

  // Collapse spaces inside a line; keep newlines.
  t = t
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .join('\n');

  // Drop near-empty dotted leaders alone.
  t = t
      .split('\n')
      .where((line) => !RegExp(r'^[\.·…]{3,}$').hasMatch(line))
      .join('\n');

  // Fix frequent OCR splits for common analytes.
  t = t.replaceAllMapped(
    RegExp(r'\bHb\s*A\s*1\s*c\b', caseSensitive: false),
    (_) => 'HbA1c',
  );
  t = t.replaceAllMapped(
    RegExp(r'\bT\s*S\s*H\b', caseSensitive: false),
    (_) => 'TSH',
  );
  t = t.replaceAllMapped(
    RegExp(r'\bS\s*G\s*O\s*T\b', caseSensitive: false),
    (_) => 'SGOT',
  );
  t = t.replaceAllMapped(
    RegExp(r'\bS\s*G\s*P\s*T\b', caseSensitive: false),
    (_) => 'SGPT',
  );
  t = t.replaceAllMapped(
    RegExp(r'\bm\s*g\s*/\s*d\s*[lL]\b'),
    (_) => 'mg/dL',
  );
  t = t.replaceAllMapped(
    RegExp(r'\bm\s*g\s*/\s*[lL]\b'),
    (_) => 'mg/L',
  );

  // Frequent Indian-lab OCR misspellings.
  t = t.replaceAllMapped(
    RegExp(r'\bCholestrol\b', caseSensitive: false),
    (_) => 'Cholesterol',
  );

  // Slash in enzyme dual names OCR'd as I/l/1: SGOTIAST → SGOT/AST.
  t = repairOcrEnzymeSlashLabels(t);

  // Slash in units OCR'd as I/l/1: UIL → U/L, mgIdL → mg/dL.
  t = repairOcrLabUnits(t);

  // "69.3 H*" / "158.6H*" → bare number so stacked value lines parse.
  t = detachHlFlags(t);

  // Vision caret / star tails on analyte names.
  t = stripOcrLabelArtifacts(t);

  // Glossary / interpretation blocks must not feed catalogue matching.
  t = stripInterpretationBlocks(t);

  // Agilus photo OCR often appends PERFORMED AT / emails — drop when results exist.
  t = stripOcrFooterNoise(t);

  // Keep results table; drop header chrome / Interpretation / page footer.
  t = extractLabResultsTableWindow(t);

  // Column-broken PDF extracts (Agilus Syncfusion) → join fragments first.
  t = reflowBrokenPdfLabText(t);

  // Same-line / wrapped "Non-Pregnant Women" between value and unit (Agilus photo).
  // Must run before collapse so mid-row chrome is not left for parseLabText.
  t = stripInlineBiologicalRefLabels(t);

  // Multi-line Biological Reference Interval → compact low-high (any analyte).
  t = collapseBiologicalRefBlobs(t);

  // Vision/ML Kit often emits label rows then value rows; zip into same-line.
  t = stitchStackedLabRows(t);

  // Orphan `65 U/L 5-40` → attach to nearest prior bare label (GGT, ALP, …).
  t = attachOrphanLabValueLines(t);

  // Second pass: ref collapse can leave value+range+unit adjacent for stitch.
  t = stripInlineBiologicalRefLabels(t);
  t = collapseBiologicalRefBlobs(t);
  t = stitchStackedLabRows(t);
  t = attachOrphanLabValueLines(t);
  // Unit OCR repair again after joins expose Pg/dL / pIU forms.
  t = repairOcrLabUnits(t);

  // Footer may remain after window cut on odd OCR — strip again if results exist.
  t = stripOcrFooterNoise(t);

  // Drop leftover educational lines that slipped past block strip.
  t = t
      .split('\n')
      .where((line) {
        final s = line.trim();
        if (s.isEmpty) return true;
        return !isEducationalProse(s);
      })
      .join('\n');

  // Collapse 3+ blank lines.
  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t.trim();
}
