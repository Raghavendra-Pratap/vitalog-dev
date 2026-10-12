import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bodyline/features/import/ocr_layout.dart';
import 'package:bodyline/features/import/ocr_normalize.dart';

void main() {
  test('collapses HbA1c / TSH OCR splits and units', () {
    final out = normalizeOcrLabText(
      'Hb A 1 c  5.6  %\nT S H  2.4  m g / d L',
    );
    expect(out, contains('HbA1c'));
    expect(out, contains('TSH'));
    expect(out, contains('mg/dL'));
  });

  test('joins hyphenated line breaks', () {
    final out = normalizeOcrLabText('Haemo-\nglobin 13.2');
    expect(out, contains('Haemoglobin'));
    expect(out, isNot(contains('Haemo-\n')));
  });

  test('fixes Cholestrol OCR misspelling', () {
    final out = normalizeOcrLabText('Total Cholestrol\n182\nmg / dL');
    expect(out, contains('Cholesterol'));
    expect(out, contains('mg/dL'));
  });

  test('lipid fixture still has key labels after normalize', () {
    final raw =
        File('test/fixtures/lab_ocr/lipid_messy_ocr.txt').readAsStringSync();
    final out = normalizeOcrLabText(raw);
    expect(out.toLowerCase(), contains('hdl'));
    expect(out.toLowerCase(), contains('ldl'));
    expect(out, contains('Cholesterol'));
    expect(out, contains('mg/dL'));
  });

  test('repairs slash-as-I enzyme dual labels', () {
    final out = normalizeOcrLabText(
      'SGOTIAST\n69.3\nU/L\nSGPTIALT\n158.6\nU/L',
    );
    expect(out, contains('SGOT/AST'));
    expect(out, contains('SGPT/ALT'));
    expect(out, isNot(contains('SGOTIAST')));
    expect(out, isNot(contains('SGPTIALT')));
  });

  test('screenshot names-only dump: no values + slash repair + clear signal',
      () {
    final raw = File(
      'test/fixtures/lab_ocr/redcliffe_lft_mlkit_names_only.txt',
    ).readAsStringSync();
    final out = normalizeOcrLabText(raw);
    expect(out, contains('SGOT/AST'));
    expect(out, contains('SGPT/ALT'));
    expect(out, contains('Bilirubin Total'));
    // Must not invent result numbers.
    expect(out, isNot(contains(RegExp(r'Bilirubin Total\s+\d'))));
    expect(ocrLooksLikeLabelsWithoutValues(out), isTrue);
    expect(ocrLabValueSignal(out), equals(0));
  });

  test('Android partial fixture repairs units and attaches GGT orphan', () {
    final raw = File(
      'test/fixtures/lab_ocr/redcliffe_lft_android_partial.txt',
    ).readAsStringSync();
    final out = normalizeOcrLabText(raw);
    expect(out, isNot(contains(RegExp(r'\bUIL\b'))));
    expect(out, contains(RegExp(r'69\.3\s+U/L')));
    expect(out, contains(RegExp(r'GGT\)?\s+65|Gamma Glutamyl[^\n]*\s+65')));
    expect(out, contains('2.6'));
    expect(out, contains('mg/dL'));
  });
}
