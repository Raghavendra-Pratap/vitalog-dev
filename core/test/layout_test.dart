import 'dart:convert';
import 'dart:io';

import 'package:bodyline_core/bodyline_core.dart';
import 'package:test/test.dart';

void main() {
  late List<WordBox> fixture;

  setUpAll(() {
    final path = 'test/fixtures/thyroid_wordboxes.json';
    final raw = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
    fixture = [
      for (final e in raw) WordBox.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
  });

  test('rebuildLayout groups thyroid name/value/unit into one row each', () {
    final rows = rebuildLayout(fixture);
    expect(rows.length, greaterThanOrEqualTo(3));
    final texts = rows.map((r) => r.text).toList();
    expect(texts.any((t) => t.contains('T3') && t.contains('110.00')), isTrue);
    expect(texts.any((t) => t.contains('T4') && t.contains('9.57')), isTrue);
    expect(texts.any((t) => t.contains('TSH') && t.contains('2.720')), isTrue);
  });

  test('cells split by horizontal gap', () {
    final rows = rebuildLayout(fixture);
    final t3 = rows.firstWhere((r) => r.text.contains('T3'));
    expect(t3.cells.length, greaterThanOrEqualTo(2));
    expect(t3.cells.first.text, contains('T3'));
  });

  test('multiline name+value merges into one row', () {
    final rows = rebuildLayout(fixture);
    expect(
      rows.any((r) => r.text.contains('Haemoglobin') && r.text.contains('13.2')),
      isTrue,
    );
  });

  test('layoutRowsToText is newline-separated', () {
    final text = layoutRowsToText(rebuildLayout(fixture));
    expect(text.split('\n').length, greaterThanOrEqualTo(3));
  });

  test('WordBox JSON round-trip', () {
    final b = fixture.first;
    final again = WordBox.fromJson(b.toJson());
    expect(again.text, b.text);
    expect(again.x, b.x);
    expect(again.source, b.source);
  });
}
