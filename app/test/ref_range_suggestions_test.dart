import 'package:bodyline/data/ref_range_suggestions.dart';
import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildRefRangeSuggestions', () {
    test('most frequent pair is first; order stable', () {
      final rows = <RefRangeHistoryRow>[
        const RefRangeHistoryRow(refLow: 70, refHigh: 110, unit: 'mg/dL'),
        const RefRangeHistoryRow(refLow: 65, refHigh: 99, unit: 'mg/dL'),
        const RefRangeHistoryRow(refLow: 70, refHigh: 110, unit: 'mg/dL'),
        const RefRangeHistoryRow(refLow: 70, refHigh: 110, unit: 'mg/dL'),
      ];
      final out = buildRefRangeSuggestions(rows);
      expect(out.length, 2);
      expect(out.first.low, 70);
      expect(out.first.high, 110);
      expect(out.first.count, 3);
      expect(out.first.unit, 'mg/dL');
      expect(out[1].low, 65);
      expect(out[1].high, 99);
      expect(out[1].count, 1);
    });

    test('skips rows with both refs null', () {
      final out = buildRefRangeSuggestions([
        const RefRangeHistoryRow(refLow: null, refHigh: null, unit: 'x'),
        const RefRangeHistoryRow(refLow: 1, refHigh: 2),
        const RefRangeHistoryRow(),
      ]);
      expect(out.length, 1);
      expect(out.first.count, 1);
      expect(out.first.low, 1);
      expect(out.first.high, 2);
    });

    test('open-ended high-only range counts', () {
      final out = buildRefRangeSuggestions([
        const RefRangeHistoryRow(refHigh: 40),
        const RefRangeHistoryRow(refHigh: 40),
        const RefRangeHistoryRow(refLow: 0, refHigh: 40),
      ]);
      expect(out.length, 2);
      expect(out.first.low, isNull);
      expect(out.first.high, 40);
      expect(out.first.count, 2);
    });

    test('tie on count sorts by low then high', () {
      final out = buildRefRangeSuggestions([
        const RefRangeHistoryRow(refLow: 10, refHigh: 20),
        const RefRangeHistoryRow(refLow: 1, refHigh: 5),
      ]);
      expect(out.length, 2);
      expect(out[0].count, 1);
      expect(out[1].count, 1);
      expect(out[0].low, 1);
      expect(out[1].low, 10);
    });

    test('refsBothEmpty / refsBothNull for ADR-006 gate', () {
      expect(refsBothEmpty('', ''), isTrue);
      expect(refsBothEmpty('  ', null), isTrue);
      expect(refsBothEmpty('1', ''), isFalse);
      expect(refsBothNull(null, null), isTrue);
      expect(refsBothNull(1, null), isFalse);
    });
  });

  group('buildRefBandSetSuggestions', () {
    test('most frequent identical band set is first', () {
      const setA = [
        RefBand(label: 'Non-Pregnant', low: 80, high: 200),
        RefBand(label: '1st Trimester', low: 105, high: 230),
      ];
      const setB = [
        RefBand(label: 'Adult', low: 70, high: 180),
        RefBand(label: 'Child', low: 60, high: 160),
      ];
      final out = buildRefBandSetSuggestions([
        const RefBandSetHistoryRow(refBands: setA, unit: 'ng/dL'),
        const RefBandSetHistoryRow(refBands: setB, unit: 'ng/dL'),
        const RefBandSetHistoryRow(refBands: setA, unit: 'ng/dL'),
        const RefBandSetHistoryRow(refBands: setA),
        const RefBandSetHistoryRow(refBands: null),
        const RefBandSetHistoryRow(refBands: []),
      ]);
      expect(out.length, 2);
      expect(out.first.count, 3);
      expect(out.first.bands.length, 2);
      expect(out.first.unit, 'ng/dL');
      expect(out[1].count, 1);
    });

    test('refsAndBandsEmpty gate', () {
      expect(
        refsAndBandsEmpty(lowText: '', highText: '', bands: null),
        isTrue,
      );
      expect(
        refsAndBandsEmpty(
          lowText: '',
          highText: '',
          bands: const [RefBand(low: 1, high: 2)],
        ),
        isFalse,
      );
      expect(
        refsAndBandsEmpty(lowText: '1', highText: '', bands: null),
        isFalse,
      );
    });
  });
}
