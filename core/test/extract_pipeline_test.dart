import 'dart:convert';
import 'dart:io';

import 'package:bodyline_core/bodyline_core.dart';
import 'package:test/test.dart';

MatchCatalog _thyroidCatalog() {
  return MatchCatalog(
    aliasToCodes: {
      't3': ['t3'],
      't4': ['t4'],
      'tsh': ['tsh'],
      'tsh ultrasensitive': ['tsh'],
      'haemoglobin': ['hb'],
      'hemoglobin': ['hb'],
    },
    paramNames: {
      't3': 'T3',
      't4': 'T4',
      'tsh': 'TSH',
      'hb': 'Haemoglobin',
    },
    paramUnits: {
      't3': 'ng/dL',
      't4': 'µg/dL',
      'tsh': 'µIU/mL',
      'hb': 'g/dL',
    },
    physicalLimits: {
      't3': (10.0, 1000.0, 'ng/dL'),
      't4': (0.1, 40.0, 'µg/dL'),
      'tsh': (0.0, 500.0, 'µIU/mL'),
      'hb': (2.0, 25.0, 'g/dL'),
    },
    unitAliases: {
      'ng/dl': 'ng/dL',
      'ug/dl': 'µg/dL',
      'µg/dl': 'µg/dL',
      'uiu/ml': 'µIU/mL',
      'µiu/ml': 'µIU/mL',
      'g/dl': 'g/dL',
    },
  );
}

void main() {
  late List<WordBox> fixture;

  setUpAll(() {
    final raw = jsonDecode(
      File('test/fixtures/thyroid_wordboxes.json').readAsStringSync(),
    ) as List<dynamic>;
    fixture = [
      for (final e in raw)
        WordBox.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
  });

  test('classify marks thyroid value rows as result', () {
    final rows = rebuildLayout(fixture);
    final classified = classifyRows(rows);
    final results =
        classified.where((c) => c.rowType == RowType.result).toList();
    expect(results.length, greaterThanOrEqualTo(3));
  });

  test('token parse extracts T3/T4/TSH values', () {
    final rows = rebuildLayout(fixture);
    final classified = classifyRows(rows);
    final parsed = parseResultTokens(classified);
    final values = {for (final p in parsed) p.nameNorm: p.valueRaw};
    expect(values.keys.any((k) => k.contains('t3')), isTrue);
    expect(parsed.any((p) => p.valueRaw.contains('110')), isTrue);
    expect(parsed.any((p) => p.valueRaw.contains('2.720') || p.valueRaw.contains('2.72')), isTrue);
  });

  test('pipeline scores TSH autoAccept or review with candidate tsh', () {
    final result = runExtractionPipeline(fixture, _thyroidCatalog());
    expect(result.scored.length, greaterThanOrEqualTo(3));
    final tsh = result.scored.where(
      (s) => s.best?.parameterCode == 'tsh',
    );
    expect(tsh.isNotEmpty, isTrue);
    expect(
      tsh.first.outcome,
      anyOf(ExtractionOutcome.autoAccept, ExtractionOutcome.review),
    );
  });

  test('scoredToExtractionJson shape works with score.py fields', () {
    final result = runExtractionPipeline(fixture, _thyroidCatalog());
    final json = scoredToExtractionJson(result.scored, labKey: 'agilus_v1');
    expect(json['rows'], isA<List>());
    final rows = json['rows'] as List;
    expect(rows.first['outcome'], isNotNull);
    expect(rows.first['candidates'], isNotEmpty);
  });
}
