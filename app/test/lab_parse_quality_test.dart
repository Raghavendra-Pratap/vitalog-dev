import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bodyline/features/import/lab_parse_quality.dart';
import 'package:bodyline/features/import/ocr_layout.dart';
import 'package:bodyline/features/import/ocr_normalize.dart';

void main() {
  group('detachHlFlags', () {
    test('strips H* / L* glued to values', () {
      expect(detachHlFlags('SGOT/AST\n69.3 H*\nU/L'), contains('69.3'));
      expect(detachHlFlags('69.3 H*'), isNot(contains('H*')));
      expect(detachHlFlags('158.6H*'), equals('158.6'));
      expect(detachHlFlags('12.0 L*'), equals('12.0'));
    });
  });

  group('isEducationalProse', () {
    test('flags Redcliffe interpretation lines', () {
      expect(
        isEducationalProse(
          '1. AST (SGOT): may indicate tissue injury / damage in muscles or liver.',
        ),
        isTrue,
      );
      expect(
        isEducationalProse(
          '2. ALT (SGPT): Primarily in the liver. Elevated ALT and AST Suggest liver damage.',
        ),
        isTrue,
      );
      expect(
        isEducationalProse(
          'Blood proteins, albumin and globulin, are essential for growth, development, and health.',
        ),
        isTrue,
      );
    });

    test('flags OCR typo variants from real ML Kit / Vision', () {
      expect(
        isEducationalProse(
          '1. AST (SGOT): may indicate tissue injury / darmage in muscles or liver.',
        ),
        isTrue,
      );
      expect(
        isEducationalProse(
          '2. ALT (SGPT): Primarily in the liver. Elevated ALT and AST SUggest liver damage.',
        ),
        isTrue,
      );
      expect(
        isEducationalProse(
          'Blood proteins, albumin and globulin, areessential for growth, development, and heath.',
        ),
        isTrue,
      );
      expect(
        isEducationalProse(
          '2. ALT (SGPT): Primarty in the lver. Elevated ALT ond AST suggestliver damage.',
        ),
        isTrue,
      );
    });

    test('allows real result rows', () {
      expect(isEducationalProse('SGPT/ALT 158.6 U/L up to 41'), isFalse);
      expect(isEducationalProse('Globulin'), isFalse);
      expect(isEducationalProse('ALT (SGPT)'), isFalse);
      expect(
        isEducationalProse('Gamma Glutamyl Transferase (GGT)'),
        isFalse,
      );
    });
  });

  group('isAccessionLikeValue', () {
    test('rejects patient / barcode IDs', () {
      expect(isAccessionLikeValue('18945041'), isTrue);
      expect(isAccessionLikeValue('18945041', unit: '/RCL18588087'), isTrue);
      expect(isAccessionLikeValue('18945041/RCL18588087'), isTrue);
      expect(isAccessionLikeValue('RL17494011'), isTrue);
    });

    test('allows normal lab magnitudes', () {
      expect(isAccessionLikeValue('158.6'), isFalse);
      expect(isAccessionLikeValue('2.6', unit: 'g/dL'), isFalse);
      expect(isAccessionLikeValue('65', unit: 'U/L'), isFalse);
      expect(isAccessionLikeValue('0.5'), isFalse);
    });
  });

  group('labUnitsCompatible', () {
    test('rejects GGT mg/dL vs U/L', () {
      expect(labUnitsCompatible('mg/dL', 'U/L'), isFalse);
      expect(labUnitsCompatible('U/L', 'U/L'), isTrue);
      expect(labUnitsCompatible('IU/L', 'U/L'), isTrue);
      expect(labUnitsCompatible('', 'U/L'), isTrue);
    });
  });

  group('isAmbiguousUrineBloodHit', () {
    test('blocks blood proteins glossary', () {
      expect(
        isAmbiguousUrineBloodHit(
          parameterCode: 'u_blood',
          sourceLine:
              'Blood proteins, albumin and globulin, are essential for growth',
        ),
        isTrue,
      );
    });
  });

  group('softAliasLengthOk', () {
    test('blocks blood → blood proteins sentence', () {
      final prose = 'bloodproteinsalbuminandglobulinareessentialforgrowth';
      expect(softAliasLengthOk(prose, 'blood'), isFalse);
    });

    test('allows short method suffixes', () {
      expect(softAliasLengthOk('haemoglobinedta', 'haemoglobin'), isTrue);
    });
  });

  group('labHitScore', () {
    test('prefers table row over interpretation prose', () {
      final table = labHitScore(
        sourceLine: 'SGPT/ALT 158.6 U/L up to 41',
        value: '158.6',
        unit: 'U/L',
      );
      final prose = labHitScore(
        sourceLine:
            '2. ALT (SGPT): Primarily in the liver. Elevated ALT and AST Suggest liver damage.',
        value: '0.5',
        unit: 'U/L',
      );
      expect(table, greaterThan(prose));
    });

    test('accession ID scores below usable threshold', () {
      final score = labHitScore(
        sourceLine: 'Globulin*',
        value: '18945041',
        unit: '/RCL18588087',
      );
      expect(score, lessThan(-40));
    });

    test('unit mismatch scores very low', () {
      final score = labHitScore(
        sourceLine: 'Gamma Glutamyl Transferase (GGT)',
        value: '0.7',
        unit: 'mg/dL',
        catalogUnit: 'U/L',
      );
      expect(score, lessThan(0));
      expect(labUnitsCompatible('mg/dL', 'U/L'), isFalse);
    });
  });

  group('stitchStackedLabRows', () {
    test('zips dual SGOT/SGPT labels to correct values', () {
      final raw = File(
        'test/fixtures/lab_ocr/redcliffe_lft_dual_labels.txt',
      ).readAsStringSync();
      final out = stitchStackedLabRows(detachHlFlags(raw));
      expect(out, contains(RegExp(r'SGOT/AST\s+69\.3')));
      expect(out, contains(RegExp(r'SGPT/ALT\s+158\.6')));
      expect(out, contains(RegExp(r'GGT\)?\s+65|GGT\s+65')));
      expect(out, contains(RegExp(r'Bilirubin Total\s+0\.7')));
      // Must not cross-pair
      expect(out, isNot(contains(RegExp(r'GGT\)?[^\n]*0\.7'))));
      expect(out, isNot(contains(RegExp(r'SGOT/AST\s+158'))));
    });

    test('refuses enzyme + mg/dL zip from unsorted Vision shape', () {
      final raw = '''
Gamma Glutamyl Transferase (GGT)
Bilirubin Total
0.7
mg/dL
0.0-1.2
65
U/L
5-40
''';
      final out = stitchStackedLabRows(raw);
      expect(out, isNot(contains(RegExp(r'GGT\)?[^\n]*0\.7'))));
    });
  });

  group('normalizeOcrLabText Redcliffe fixture', () {
    test('strips interpretation and detaches H*', () {
      final raw = File(
        'test/fixtures/lab_ocr/redcliffe_lft_interpretation.txt',
      ).readAsStringSync();
      final out = normalizeOcrLabText(raw);

      expect(out.toLowerCase(), isNot(contains('may indicate')));
      expect(out.toLowerCase(), isNot(contains('primarily in the')));
      expect(out.toLowerCase(), isNot(contains('essential for')));
      expect(out, isNot(contains('H*')));
      expect(out, contains('69.3'));
      expect(out, contains('158.6'));
      expect(out, contains('SGOT'));
      expect(out, contains('SGPT'));
      expect(out, contains('2.6'));
    });

    test('prose-first fixture loses glossary block', () {
      final raw = File(
        'test/fixtures/lab_ocr/redcliffe_lft_prose_first.txt',
      ).readAsStringSync();
      final out = normalizeOcrLabText(raw);
      expect(out.toLowerCase(), isNot(contains('may indicate')));
      expect(out, contains('69.3'));
      expect(out, contains('158.6'));
    });

    test('ML Kit typo fixture drops glossary and keeps LFT values', () {
      final raw = File(
        'test/fixtures/lab_ocr/redcliffe_lft_mlkit_typos.txt',
      ).readAsStringSync();
      final out = normalizeOcrLabText(raw);
      expect(out.toLowerCase(), isNot(contains('darmage')));
      expect(out.toLowerCase(), isNot(contains('suggest')));
      expect(out.toLowerCase(), isNot(contains('blood proteins')));
      expect(out, contains('69.3'));
      expect(out, contains('158.6'));
      expect(out, contains('65'));
      expect(out, contains('2.6'));
      expect(out, isNot(contains('^')));
      // GGT must stay near 65, not bilirubin 0.7
      final ggtIdx = out.indexOf('GGT');
      final sixtyFive = out.indexOf('65', ggtIdx >= 0 ? ggtIdx : 0);
      expect(ggtIdx, greaterThanOrEqualTo(0));
      expect(sixtyFive, greaterThan(ggtIdx));
    });

    test('real Vision macOS dump strips interpretation, keeps table', () {
      final raw = File(
        'test/fixtures/lab_ocr/redcliffe_lft_vision_macos.txt',
      ).readAsStringSync();
      final out = normalizeOcrLabText(raw);
      expect(out.toLowerCase(), isNot(contains('may indicate')));
      expect(out.toLowerCase(), isNot(contains('key enzymes')));
      expect(out.toLowerCase(), isNot(contains('blood proteins')));
      expect(out, contains('69.3'));
      expect(out, contains('158.6'));
      expect(out, contains('65'));
      expect(out, contains('0.7'));
      expect(out, contains('2.6'));
      // Stitched GGT should carry 65 not 0.7
      expect(
        out,
        anyOf(
          contains(RegExp(r'GGT\)?\s+65')),
          contains(RegExp(r'Gamma Glutamyl Transferase \(GGT\)\s+65')),
        ),
      );
      expect(out, isNot(contains(RegExp(r'GGT\)?[^\n]{0,40}0\.7'))));
    });
  });

  group('shouldReplaceLabHit', () {
    test('keeps higher-scoring table hit over later prose', () {
      expect(
        shouldReplaceLabHit(
          existingScore: 50,
          candidateScore: -60,
          candidateHasUnitOrRange: true,
          existingHasUnitOrRange: true,
        ),
        isFalse,
      );
      expect(
        shouldReplaceLabHit(
          existingScore: -60,
          candidateScore: 50,
          candidateHasUnitOrRange: true,
          existingHasUnitOrRange: false,
        ),
        isTrue,
      );
    });
  });

  group('labUnitsCompatible hormone units', () {
    test('mU/L matches catalogue µIU/mL (insulin)', () {
      expect(labUnitsCompatible('mU/L', 'µIU/mL'), isTrue);
      expect(labUnitsCompatible('uIU/mL', 'µIU/mL'), isTrue);
      expect(labUnitsCompatible('mIU/L', 'µIU/mL'), isTrue);
      expect(labUnitsCompatible('mg/dL', 'µIU/mL'), isFalse);
    });
  });

  group('reflowBrokenPdfLabText Agilus', () {
    test('stitches column-broken insulin row', () {
      final raw = File('test/fixtures/lab_ocr/agilus_insulin_column_broken.txt')
          .readAsStringSync();
      final out = normalizeOcrLabText(raw);
      expect(
        RegExp(
          r'INSULIN,\s*FASTING\s*SERUM',
          caseSensitive: false,
        ).hasMatch(out),
        isTrue,
      );
      expect(out, contains('14.7'));
      expect(out, contains('2.6 - 24.9'));
      expect(RegExp(r'mU/?L', caseSensitive: false).hasMatch(out), isTrue);
      final compact = out.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        RegExp(
          r'INSULIN,\s*FASTING\s*SERUM.{0,80}14\.7',
          caseSensitive: false,
        ).hasMatch(compact),
        isTrue,
      );
    });

    test('layout line keeps Agilus value range unit order', () {
      final raw = File('test/fixtures/lab_ocr/agilus_insulin_layout.txt')
          .readAsStringSync();
      final out = normalizeOcrLabText(raw);
      expect(
        RegExp(
          r'INSULIN,\s*FASTING\s*SERUM\s+14\.7\s+2\.6\s*-\s*24\.9\s+mU/?L',
          caseSensitive: false,
        ).hasMatch(out.replaceAll(RegExp(r'\s+'), ' ')),
        isTrue,
      );
    });

    test('expects Insulin 14.7 via Agilus same-line shape', () {
      final raw = File('test/fixtures/lab_ocr/agilus_insulin_layout.txt')
          .readAsStringSync();
      final out = normalizeOcrLabText(raw);
      final sameLineRangeUnit = RegExp(
        r'^([A-Za-z(][A-Za-z0-9 /\-\(\),%\.]{0,80}?)\s*(?:[:=]|\s)\s*'
        r'([<>]?\d+(?:\.\d+)?)\s*(?:[HL]\*?)?\s+'
        r'(\d+(?:\.\d+)?)\s*[-–to]+\s*(\d+(?:\.\d+)?)\s+'
        r'([A-Za-z/%µμ][A-Za-z0-9/%µμ^.\-]*)\s*$',
        caseSensitive: false,
      );
      RegExpMatch? hit;
      for (final line in out.split('\n')) {
        final m = sameLineRangeUnit.firstMatch(line.trim());
        if (m != null && m.group(1)!.toLowerCase().contains('insulin')) {
          hit = m;
          break;
        }
      }
      expect(hit, isNotNull);
      expect(hit!.group(2), '14.7');
      expect(hit.group(3), '2.6');
      expect(hit.group(4), '24.9');
      expect(
        hit.group(5)!.toLowerCase().replaceAll('/', ''),
        contains('mul'),
      );
      expect(labUnitsCompatible(hit.group(5)!, 'µIU/mL'), isTrue);
    });
  });


  group('matchSameLineLabRow A/G ratio', () {
    test('parses Redcliffe Albumin :Globulin Ratio with dash unit', () {
      final m = matchSameLineLabRow(
        'Albumin :Globulin Ratio 1.92 - 1.0-2.1',
      );
      expect(m, isNotNull);
      expect(m!.label.toLowerCase(), contains('globulin'));
      expect(m.value, '1.92');
      expect(m.unit, ''); // "-" sanitized
      expect(m.refLow, 1.0);
      expect(m.refHigh, 2.1);
    });

    test('parses Albumin:Globulin and Albumin Globulin forms', () {
      for (final line in [
        'Albumin:Globulin Ratio 1.92 1.0 - 2.1',
        'Albumin Globulin Ratio 1.92 1.0-2.1',
        'A/G Ratio 1.92 - 1.0-2.1',
      ]) {
        final m = matchSameLineLabRow(line);
        expect(m, isNotNull, reason: line);
        expect(m!.value, '1.92');
        expect(m.refLow, 1.0);
        expect(m.refHigh, 2.1);
      }
    });

    test('still parses SGOT/SGPT Ratio', () {
      final m = matchSameLineLabRow('SGOT/SGPT Ratio 0.44 Ratio');
      expect(m, isNotNull);
      expect(m!.value, '0.44');
      expect(m.unit.toLowerCase(), 'ratio');
    });
  });

  group('normalizeOcrLabText A/G ratio fixture', () {
    test('stitches Albumin :Globulin Ratio with 1.92', () {
      final raw = File(
        'test/fixtures/lab_ocr/redcliffe_lft_ag_ratio.txt',
      ).readAsStringSync();
      final out = normalizeOcrLabText(raw);
      expect(out, contains('1.92'));
      expect(
        out,
        contains(RegExp(r'Albumin\s*:?\s*Globulin\s+Ratio[^\n]*1\.92')),
      );
      final row = matchSameLineLabRow(
        out.split('\n').firstWhere((l) => l.contains('1.92')),
      );
      expect(row, isNotNull);
      expect(row!.value, '1.92');
      expect(row.refLow, 1.0);
      expect(row.refHigh, 2.1);
    });

    test('vision macos dump keeps A/G 1.92 as same-line row', () {
      final raw = File(
        'test/fixtures/lab_ocr/redcliffe_lft_vision_macos.txt',
      ).readAsStringSync();
      final out = normalizeOcrLabText(raw);
      final agLine = out.split('\n').firstWhere(
        (l) => l.contains('1.92'),
        orElse: () => '',
      );
      expect(agLine, isNot(isEmpty));
      final row = matchSameLineLabRow(agLine);
      expect(row, isNotNull, reason: agLine);
      expect(row!.value, '1.92');
      expect(row.label.toLowerCase(), contains('globulin ratio'));
    });
  });

  group('layoutOcrByGeometry', () {
    test('stitches name + value columns on same row band', () {
      // Left column names, right column values (separate ML Kit blocks).
      final boxes = <OcrBox>[
        const OcrBox(text: 'Bilirubin Total', left: 10, top: 100, right: 120, bottom: 118),
        const OcrBox(text: 'Bilirubin Direct', left: 10, top: 130, right: 120, bottom: 148),
        const OcrBox(text: '0.7', left: 200, top: 102, right: 230, bottom: 118),
        const OcrBox(text: 'mg/dL', left: 240, top: 102, right: 290, bottom: 118),
        const OcrBox(text: '0.2', left: 200, top: 132, right: 230, bottom: 148),
        const OcrBox(text: 'mg/dL', left: 240, top: 132, right: 290, bottom: 148),
        const OcrBox(text: 'SGOTIAST', left: 10, top: 160, right: 100, bottom: 178),
        const OcrBox(text: '69.3', left: 200, top: 162, right: 240, bottom: 178),
        const OcrBox(text: 'U/L', left: 250, top: 162, right: 280, bottom: 178),
      ];
      final laid = layoutOcrByGeometry(boxes);
      expect(laid, contains(RegExp(r'Bilirubin Total\s+0\.7\s+mg/dL')));
      expect(laid, contains(RegExp(r'Bilirubin Direct\s+0\.2\s+mg/dL')));
      expect(laid, contains(RegExp(r'SGOTIAST\s+69\.3\s+U/L')));
      final norm = normalizeOcrLabText(laid);
      expect(norm, contains('SGOT/AST'));
      expect(ocrLooksLikeLabelsWithoutValues(norm), isFalse);
    });
  });

  group('ocrLooksLikeLabelsWithoutValues', () {
    test('true for screenshot names-only fixture', () {
      final raw = File(
        'test/fixtures/lab_ocr/redcliffe_lft_mlkit_names_only.txt',
      ).readAsStringSync();
      expect(ocrLooksLikeLabelsWithoutValues(normalizeOcrLabText(raw)), isTrue);
    });

    test('false when stacked LFT values present', () {
      final raw = File(
        'test/fixtures/lab_ocr/redcliffe_lft_mlkit_typos.txt',
      ).readAsStringSync();
      expect(ocrLooksLikeLabelsWithoutValues(normalizeOcrLabText(raw)), isFalse);
    });
  });

  group('repairOcrLabUnits', () {
    test('Pg/dL and pIU/mL micro OCR confusions', () {
      expect(repairOcrLabUnits('T4 9.57 Pg/dL'), contains('ug/dL'));
      expect(repairOcrLabUnits('TSH 2.720 pIU/mL'), contains('uIU/mL'));
      expect(labUnitsCompatible('ug/dL', 'µg/dL'), isTrue);
      expect(labUnitsCompatible('uIU/mL', 'µIU/mL'), isTrue);
      expect(labUnitsCompatible('Pg/dL', 'µg/dL'), isTrue); // fold alias
      expect(labUnitsCompatible('pIU/mL', 'µIU/mL'), isTrue);
    });

    test('repairs UIL mgIdL gIdL', () {
      expect(repairOcrLabUnits('65 UIL 5-40'), contains('U/L'));
      expect(repairOcrLabUnits('0.2 mgIdL'), contains('mg/dL'));
      expect(repairOcrLabUnits('2.6 gIdL'), contains('g/dL'));
      expect(repairOcrLabUnits('90 UIL 40-129'), contains('U/L'));
    });
  });

  group('attachOrphanLabValueLines', () {
    test('joins GGT label to orphan value+unit+range', () {
      const raw = '''
Gamma Glutamyl Transferase (GGT)
65 U/L 5-40
''';
      final out = attachOrphanLabValueLines(raw);
      expect(out, contains(RegExp(r'GGT\)?\s+65\s+U/L')));
      expect(out.split('\n').where((l) => l.trim().startsWith('65')), isEmpty);
    });

    test('refuses enzyme + mg/dL orphan', () {
      const raw = '''
Gamma Glutamyl Transferase (GGT)
0.7 mg/dL 0-1.2
''';
      final out = attachOrphanLabValueLines(raw);
      expect(out, isNot(contains(RegExp(r'GGT\)?[^\n]*0\.7'))));
    });
  });

  group('Android partial Redcliffe LFT fixture', () {
    final lftAliases = <String, String>{
      'bilirubintotal': 'tbil',
      'bilirubindirect': 'dbil',
      'bilirubinindirect': 'ibil',
      'sgot': 'ast',
      'ast': 'ast',
      'sgpt': 'alt',
      'alt': 'alt',
      'alkalinephosphatase': 'alp',
      'alp': 'alp',
      'totalprotein': 'tp',
      'albumin': 'alb',
      'globulin': 'glob',
      'albuminglobulinratio': 'ag_ratio',
      'agratio': 'ag_ratio',
      'sgotsgptratio': 'ast_alt_ratio',
      'ggt': 'ggt',
      'gammaglutamyltransferase': 'ggt',
      'gammaglutamyltransferaseggt': 'ggt',
    };

    String fold(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    /// Catalogue canonical units (subset) — mirrors LocalStore unit gate.
    final catalogUnits = <String, String>{
      'tbil': 'mg/dL',
      'dbil': 'mg/dL',
      'ibil': 'mg/dL',
      'ast': 'U/L',
      'alt': 'U/L',
      'alp': 'U/L',
      'tp': 'g/dL',
      'alb': 'g/dL',
      'glob': 'g/dL',
      'ag_ratio': '',
      'ast_alt_ratio': 'ratio',
      'ggt': 'U/L',
    };

    Set<String> codesFromNormalized(String out, {bool applyUnitGate = true}) {
      final codes = <String>{};
      for (final line in out.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        final m = matchSameLineRangeUnitLabRow(t) ??
            matchSameLineLabRow(t) ??
            matchDottedLabRow(t);
        if (m == null) continue;
        final labelFold = fold(m.label);
        String? code;
        final keys = lftAliases.keys.toList()
          ..sort((a, b) => b.length.compareTo(a.length));
        for (final k in keys) {
          if (labelFold == k ||
              labelFold.contains(k) ||
              labelFold.endsWith(k) ||
              labelFold.startsWith(k)) {
            if (k == 'albumin' && labelFold.contains('globulin')) continue;
            if (k == 'globulin' && labelFold.contains('ratio')) continue;
            code = lftAliases[k];
            break;
          }
        }
        if (code == null) continue;
        if (applyUnitGate) {
          final cu = catalogUnits[code] ?? '';
          if (m.unit.isNotEmpty &&
              cu.isNotEmpty &&
              !labUnitsCompatible(m.unit, cu)) {
            continue;
          }
        }
        codes.add(code);
      }
      return codes;
    }

    test('unit repair + orphan attach yields ≥10 LFT same-line hits', () {
      final raw = File(
        'test/fixtures/lab_ocr/redcliffe_lft_android_partial.txt',
      ).readAsStringSync();

      // Legacy path: stitch only — no unit repair / orphan attach.
      // Disable OCR unit-fold aliases by checking raw unit tokens that
      // production rejected before repair (UIL / mgIdL / gIdL).
      var before = raw.replaceAll('\r\n', '\n');
      before = repairOcrEnzymeSlashLabels(before);
      before = detachHlFlags(before);
      before = stripOcrLabelArtifacts(before);
      before = stripInterpretationBlocks(before);
      before = stitchStackedLabRows(before);

      bool legacyUnitOk(String reported, String catalog) {
        final r = reported.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        final c = catalog.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (reported.trim().isEmpty || catalog.trim().isEmpty) return true;
        if (r == c) return true;
        if ((r == 'ul' || r == 'iul') && (c == 'ul' || c == 'iul')) return true;
        if (r.contains(c) || c.contains(r)) return true;
        return false; // no UIL→ul alias
      }

      final beforeCodes = <String>{};
      for (final line in before.split('\n')) {
        final m = matchSameLineRangeUnitLabRow(line.trim()) ??
            matchSameLineLabRow(line.trim());
        if (m == null) continue;
        final labelFold = fold(m.label);
        String? code;
        final keys = lftAliases.keys.toList()
          ..sort((a, b) => b.length.compareTo(a.length));
        for (final k in keys) {
          if (labelFold.contains(k) || labelFold == k) {
            if (k == 'albumin' && labelFold.contains('globulin')) continue;
            if (k == 'globulin' && labelFold.contains('ratio')) continue;
            code = lftAliases[k];
            break;
          }
        }
        if (code == null) continue;
        final cu = catalogUnits[code] ?? '';
        if (m.unit.isNotEmpty &&
            cu.isNotEmpty &&
            !legacyUnitOk(m.unit, cu)) {
          continue;
        }
        beforeCodes.add(code);
      }

      final after = normalizeOcrLabText(raw);
      final afterCodes = codesFromNormalized(after);

      // Screenshot showed 4 kept; this richer fixture still loses UIL rows
      // (AST/ALP/GGT) under the legacy unit gate — that is the Android gap.
      expect(beforeCodes.containsAll({'ast', 'alp', 'ggt'}), isFalse,
          reason: 'before should miss UIL enzymes: $beforeCodes');
      expect(beforeCodes.length, lessThan(afterCodes.length),
          reason: 'before=$beforeCodes after=$afterCodes');
      expect(afterCodes.length, greaterThanOrEqualTo(10),
          reason: 'after=$afterCodes\n---\n$after');
      expect(afterCodes.length, equals(12),
          reason: 'full LFT panel when OCR has numbers: $afterCodes');
      expect(
        afterCodes,
        containsAll(['alt', 'alb', 'tbil', 'tp', 'ggt', 'ast', 'alp', 'glob']),
      );
      expect(after, contains('U/L'));
      expect(after, isNot(contains(RegExp(r'\bUIL\b'))));
      expect(after, isNot(contains(RegExp(r'\bmgIdL\b'))));
      expect(after, isNot(contains(RegExp(r'\bgIdL\b'))));
      expect(after, contains(RegExp(r'GGT\)?\s+65|Gamma Glutamyl[^\n]*65')));
      expect(after, contains(RegExp(r'SGOT/AST\s+69\.3')));
    });
  });

  group('labUnitsCompatible OCR unit aliases', () {
    test('UIL folds like U/L', () {
      expect(labUnitsCompatible('UIL', 'U/L'), isTrue);
      expect(labUnitsCompatible('gIdL', 'g/dL'), isTrue);
      expect(labUnitsCompatible('mgIdL', 'mg/dL'), isTrue);
    });
  });



  group('Agilus layout (thyroid + footer) OCR', () {
    test('footer-only dump detected; no invented values', () {
      final raw = File(
        'test/fixtures/lab_ocr/agilus_thyroid_footer_only.txt',
      ).readAsStringSync();
      final out = normalizeOcrLabText(raw);
      expect(ocrLooksLikeFooterWithoutResults(out), isTrue);
      expect(ocrLabValueSignal(out), 0);
      expect(out.toLowerCase(), isNot(contains('110.00')));
    });

    test('table with pregnancy refs yields T3 T4 TSH same-line rows', () {
      final raw = File(
        'test/fixtures/lab_ocr/agilus_thyroid_table.txt',
      ).readAsStringSync();
      final out = normalizeOcrLabText(raw);
      expect(ocrLooksLikeFooterWithoutResults(out), isFalse);
      expect(out, contains('110.00'));
      expect(out, contains('9.57'));
      expect(out, contains('2.720'));
      // Footer chrome stripped when results present.
      expect(out.toLowerCase(), isNot(contains('srlbly2002')));
      expect(out.toLowerCase(), isNot(contains('performed at')));

      final codes = <String>{};
      for (final line in out.split('\n')) {
        final m = matchSameLineRangeUnitLabRow(line.trim()) ??
            matchSameLineLabRow(line.trim()) ??
            matchAgilusLayoutRow(line.trim());
        if (m == null) continue;
        final f = m.label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (f.startsWith('t3') || f == 't3') codes.add('t3');
        if (f.startsWith('t4') || f == 't4') codes.add('t4');
        if (f.startsWith('tsh')) codes.add('tsh');
        if (m.value == '110.00') {
          expect(labUnitsCompatible(m.unit, 'ng/dL'), isTrue);
        }
        if (m.value == '9.57') {
          expect(labUnitsCompatible(m.unit, 'µg/dL'), isTrue);
        }
        if (m.value == '2.720') {
          expect(labUnitsCompatible(m.unit, 'µIU/mL'), isTrue);
        }
      }
      expect(codes, containsAll(['t3', 't4', 'tsh']), reason: out);
      expect(codes.length, equals(3));
    });

    test('inline Non-Pregnant + Pg/pIU device dump yields T3 T4 TSH', () {
      final raw = File(
        'test/fixtures/lab_ocr/agilus_thyroid_inline_pregnant.txt',
      ).readAsStringSync();
      final out = normalizeOcrLabText(raw);
      expect(out.toLowerCase(), isNot(contains('non-pregnant')));
      expect(out.toLowerCase(), isNot(contains('non pregnant')));
      // Unit OCR repaired before parse.
      expect(out.toLowerCase(), isNot(contains('pg/dl')));
      expect(out.toLowerCase(), isNot(contains('piu')));

      final found = <String, String>{};
      for (final line in out.split('\n')) {
        final m = matchSameLineRangeUnitLabRow(line.trim()) ??
            matchSameLineLabRow(line.trim()) ??
            matchAgilusLayoutRow(line.trim());
        if (m == null) continue;
        final f = m.label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (f == 't3' || f.startsWith('t3')) {
          found['t3'] = m.value;
          expect(labUnitsCompatible(m.unit, 'ng/dL'), isTrue, reason: line);
        }
        if (f == 't4' || f.startsWith('t4')) {
          found['t4'] = m.value;
          expect(labUnitsCompatible(m.unit, 'µg/dL'), isTrue, reason: line);
        }
        if (f.startsWith('tsh')) {
          found['tsh'] = m.value;
          expect(labUnitsCompatible(m.unit, 'µIU/mL'), isTrue, reason: line);
        }
      }
      expect(found['t3'], isNotNull, reason: out);
      expect(double.parse(found['t3']!), closeTo(110.0, 0.01));
      expect(found['t4'], isNotNull, reason: out);
      expect(double.parse(found['t4']!), closeTo(9.57, 0.01));
      expect(found['tsh'], isNotNull, reason: out);
      expect(double.parse(found['tsh']!), closeTo(2.72, 0.01));
      expect(found.length, equals(3), reason: out);
    });

    test('geometry prefers lab signal over footer boxes', () {
      final boxes = <OcrBox>[
        const OcrBox(text: 'T3', left: 10, top: 100, right: 40, bottom: 118),
        const OcrBox(text: '110.00', left: 120, top: 100, right: 180, bottom: 118),
        const OcrBox(text: 'ng/dL', left: 300, top: 100, right: 360, bottom: 118),
        const OcrBox(text: 'Page 12 Of 15', left: 200, top: 400, right: 320, bottom: 418),
        const OcrBox(
          text: 'PERFORMED AT :',
          left: 10,
          top: 420,
          right: 140,
          bottom: 438,
        ),
        const OcrBox(
          text: 'srlbly2002@yahoo.com',
          left: 10,
          top: 440,
          right: 200,
          bottom: 458,
        ),
      ];
      final laid = layoutOcrByGeometry(boxes);
      expect(laid, contains(RegExp(r'T3\s+110\.00')));
      // Footer deferred after results, not interleaved as the only content.
      final firstLab = laid.indexOf('T3');
      final firstFooter = laid.toLowerCase().indexOf('performed');
      expect(firstLab, greaterThanOrEqualTo(0));
      if (firstFooter >= 0) {
        expect(firstFooter, greaterThan(firstLab));
      }
    });
  });


  group('Agilus layout generic panels', () {
    test('lipid table window yields cholesterol HDL LDL triglycerides', () {
      final raw = File(
        'test/fixtures/lab_ocr/agilus_lipid_table.txt',
      ).readAsStringSync();
      final out = normalizeOcrLabText(raw);
      expect(ocrLooksLikeFooterWithoutResults(out), isFalse);
      expect(out.toLowerCase(), isNot(contains('lab.noreply')));
      expect(out.toLowerCase(), isNot(contains('performed at')));
      expect(out.toLowerCase(), isNot(contains('interpretation')));
      // Section banners should not remain as fake analytes.
      expect(out.toUpperCase(), isNot(contains('SPECIALISED CHEMISTRY')));
      expect(out.toUpperCase(), isNot(contains('LIPID PROFILE')));

      final found = <String, String>{};
      for (final line in out.split('\n')) {
        final m = matchSameLineRangeUnitLabRow(line.trim()) ??
            matchSameLineLabRow(line.trim()) ??
            matchAgilusLayoutRow(line.trim());
        if (m == null) continue;
        final f = m.label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if ((f.contains('cholesterol') && f.contains('total')) ||
            f == 'cholesteroltotal' ||
            (f.startsWith('cholesterol') &&
                !f.contains('hdl') &&
                !f.contains('ldl'))) {
          found['tc'] = m.value;
        }
        if (f.contains('triglyceride')) found['tg'] = m.value;
        if (f.contains('hdl')) found['hdl'] = m.value;
        if (f.contains('ldl')) found['ldl'] = m.value;
      }
      expect(found['tc'], equals('182.00'), reason: out);
      expect(found['tg'], equals('145.00'), reason: out);
      expect(found['hdl'], equals('48.00'), reason: out);
      expect(found['ldl'], equals('98.00'), reason: out);
      expect(found.length, equals(4), reason: out);
    });

    test('cbc-like table yields hemoglobin + WBC without inventing', () {
      final raw = File(
        'test/fixtures/lab_ocr/agilus_cbc_like_table.txt',
      ).readAsStringSync();
      final out = normalizeOcrLabText(raw);
      expect(ocrLooksLikeFooterWithoutResults(out), isFalse);
      expect(out.toUpperCase(), isNot(contains('COMPLETE BLOOD COUNT')));

      final found = <String, String>{};
      for (final line in out.split('\n')) {
        final m = matchSameLineRangeUnitLabRow(line.trim()) ??
            matchSameLineLabRow(line.trim()) ??
            matchAgilusLayoutRow(line.trim());
        if (m == null) continue;
        final f = m.label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (f.contains('hemoglobin') || f.contains('haemoglobin')) {
          found['hb'] = m.value;
        }
        if (f.contains('leucocyte') || f.contains('leukocyte') || f == 'wbc') {
          found['wbc'] = m.value;
        }
      }
      expect(found['hb'], equals('13.5'), reason: out);
      expect(found['wbc'], equals('7.5'), reason: out);
    });

    test('table window with chrome but no numbers stays honest', () {
      final raw = [
        'DIAGNOSTIC REPORT',
        'SPECIALISED CHEMISTRY - LIPIDS',
        'LIPID PROFILE',
        'Interpretation(s)',
        'Some prose without results.',
        'Page 2 Of 3',
        'PERFORMED AT :',
        'Agilus Diagnostics Ltd',
        'Email : lab.noreply@example.com',
      ].join('\n');
      final out = normalizeOcrLabText(raw);
      expect(ocrLabValueSignal(out), equals(0));
      expect(out, isNot(contains(RegExp(r'\b182\b'))));
      expect(
        ocrLooksLikeFooterWithoutResults(out) ||
            ocrLooksLikeLabelsWithoutValues(out) ||
            out.trim().isEmpty ||
            !RegExp(r'\b\d{1,4}(?:\.\d+)?\b').hasMatch(out),
        isTrue,
        reason: out,
      );
    });
  });

  group('Redcliffe LFT device same-line six only', () {
    test('device same-line six only stays at 6 (no invent)', () {
      const raw = '''
Liver Function Test (LFT)
SGPT/ALT 158.6 U/L up to 41
SGOT/AST 69.3 U/L up to 40
Albumin 5 g/dL 3.5 -5.2
Alkaline Phosphatase 90 U/L 40 - 129
Bilirubin Total 0.7 mg/dL 0-1.2
Total Protein 7.6 g/dL 6.4- 8.3
''';
      final out = normalizeOcrLabText(raw);
      final codes = <String>{};
      for (final line in out.split('\n')) {
        final m = matchSameLineRangeUnitLabRow(line.trim()) ??
            matchSameLineLabRow(line.trim());
        if (m == null) continue;
        codes.add(m.label.toLowerCase());
      }
      expect(codes.length, equals(6), reason: out);
      expect(out.toLowerCase(), isNot(contains('direct')));
      expect(out.toLowerCase(), isNot(contains('ggt')));
    });
  });

  group('Redcliffe LFT android six-plus fixture', () {
    final lftAliases = <String, String>{
      'bilirubintotal': 'bil_t',
      'bilirubindirect': 'bil_d',
      'bilirubinindirect': 'bil_i',
      'sgot': 'ast',
      'ast': 'ast',
      'sgpt': 'alt',
      'alt': 'alt',
      'alkalinephosphatase': 'alp',
      'alp': 'alp',
      'totalprotein': 'tp',
      'albumin': 'alb',
      'globulin': 'glob',
      'albuminglobulinratio': 'ag_ratio',
      'agratio': 'ag_ratio',
      'sgotsgptratio': 'ast_alt',
      'ggt': 'ggt',
      'gammaglutamyltransferase': 'ggt',
      'gammaglutamyltransferaseggt': 'ggt',
    };

    String fold(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    final catalogUnits = <String, String>{
      'bil_t': 'mg/dL',
      'bil_d': 'mg/dL',
      'bil_i': 'mg/dL',
      'ast': 'U/L',
      'alt': 'U/L',
      'alp': 'U/L',
      'tp': 'g/dL',
      'alb': 'g/dL',
      'glob': 'g/dL',
      'ag_ratio': '',
      'ast_alt': 'ratio',
      'ggt': 'U/L',
    };

    Set<String> codesFromNormalized(String out) {
      final codes = <String>{};
      for (final line in out.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        final m = matchSameLineRangeUnitLabRow(t) ??
            matchSameLineLabRow(t) ??
            matchDottedLabRow(t);
        if (m == null) continue;
        final labelFold = fold(m.label);
        String? code;
        final keys = lftAliases.keys.toList()
          ..sort((a, b) => b.length.compareTo(a.length));
        for (final k in keys) {
          if (labelFold == k ||
              labelFold.contains(k) ||
              labelFold.endsWith(k) ||
              labelFold.startsWith(k)) {
            if (k == 'albumin' && labelFold.contains('globulin')) continue;
            if (k == 'globulin' && labelFold.contains('ratio')) continue;
            code = lftAliases[k];
            break;
          }
        }
        if (code == null) continue;
        final cu = catalogUnits[code] ?? '';
        if (m.unit.isNotEmpty &&
            cu.isNotEmpty &&
            !labUnitsCompatible(m.unit, cu)) {
          continue;
        }
        codes.add(code);
      }
      return codes;
    }

    test('6 same-line + stacked/orphan remaining → 12 LFT hits', () {
      final raw = File(
        'test/fixtures/lab_ocr/redcliffe_lft_android_six_plus.txt',
      ).readAsStringSync();
      final after = normalizeOcrLabText(raw);
      final codes = codesFromNormalized(after);
      expect(codes.length, equals(12), reason: 'codes=$codes\n---\n$after');
      expect(
        codes,
        containsAll([
          'alt',
          'ast',
          'alb',
          'alp',
          'bil_t',
          'tp',
          'bil_d',
          'bil_i',
          'glob',
          'ag_ratio',
          'ast_alt',
          'ggt',
        ]),
      );
    });
  });

  group('labUnitsCompatible microgram fold', () {
    test('µg/dL matches ug/dL', () {
      expect(labUnitsCompatible('ug/dL', 'µg/dL'), isTrue);
      expect(labUnitsCompatible('µg/dL', 'ug/dL'), isTrue);
      expect(labUnitsCompatible('mcg/dL', 'µg/dL'), isTrue);
    });
  });


  group('extractBiologicalRefBandsByLabel', () {
    test('Agilus T3 pregnancy blob yields multiple labeled stages', () {
      final raw = File(
        'test/fixtures/lab_ocr/agilus_thyroid_multiband_snippet.txt',
      ).readAsStringSync();
      final map = extractBiologicalRefBandsByLabel(
        prepTextForBiologicalBandExtract(raw),
      );
      expect(map.containsKey('t3'), isTrue);
      final bands = map['t3']!;
      expect(bands.length, greaterThanOrEqualTo(2));
      expect(bands.first.label, contains('Non-Pregnant'));
      expect(bands.first.low, 80);
      expect(bands.any((b) => (b.label ?? '').contains('Trimester')), isTrue);
    });
  });

}
