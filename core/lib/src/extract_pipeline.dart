import 'evidence.dart';
import 'layout.dart';
import 'token_parse.dart';
import 'word_box.dart';
import 'zoning.dart';

export 'evidence.dart';
export 'token_parse.dart';
export 'zoning.dart';

/// Full layout → classify → parse → match pipeline (FR-013…016).
class ExtractionPipelineResult {
  const ExtractionPipelineResult({
    required this.layoutRows,
    required this.classified,
    required this.parsed,
    required this.scored,
  });

  final List<LayoutRow> layoutRows;
  final List<ClassifiedRow> classified;
  final List<ParsedExtractionRow> parsed;
  final List<ScoredExtractionRow> scored;
}

ExtractionPipelineResult runExtractionPipeline(
  List<WordBox> boxes,
  MatchCatalog catalog, {
  LayoutRebuildOptions? layoutOptions,
}) {
  final layoutRows = rebuildLayout(boxes, options: layoutOptions);
  final knownUnits = catalog.unitAliases.keys.toSet()
    ..addAll(catalog.paramUnits.values);
  final classified = classifyRows(layoutRows, knownUnits: knownUnits);
  final parsed = parseResultTokens(
    classified,
    unitAliases: catalog.unitAliases,
  );
  final scored = matchAndScore(parsed, catalog);
  return ExtractionPipelineResult(
    layoutRows: layoutRows,
    classified: classified,
    parsed: parsed,
    scored: scored,
  );
}

/// Serialize scored rows to corpus ExtractionResult JSON shape (spec §11 / score.py).
Map<String, dynamic> scoredToExtractionJson(
  List<ScoredExtractionRow> scored, {
  String? labKey,
}) {
  return {
    'pages': scored.isEmpty
        ? 1
        : scored.map((s) => s.parsed.page).reduce((a, b) => a > b ? a : b),
    if (labKey != null) 'labKey': labKey,
    'rows': [
      for (final s in scored)
        {
          'page': s.parsed.page,
          'zone': 'results',
          'rowType': 'result',
          'parsed': {
            'nameRaw': s.parsed.nameRaw,
            'valueRaw': s.parsed.valueRaw,
            if (s.parsed.unitRaw != null) 'unitRaw': s.parsed.unitRaw,
          },
          'candidates': [
            for (final c in s.candidates)
              {'parameterCode': c.parameterCode, 'score': c.score},
          ],
          'outcome': switch (s.outcome) {
            ExtractionOutcome.autoAccept => 'autoAccept',
            ExtractionOutcome.review => 'review',
            ExtractionOutcome.unrecognised => 'unrecognised',
          },
        },
    ],
  };
}
