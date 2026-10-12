import 'package:bodyline_core/bodyline_core.dart';
import 'package:test/test.dart';

void main() {
  group('ref bands json', () {
    test('round-trip encode/decode', () {
      const bands = [
        RefBand(label: 'Non-Pregnant Women', low: 80, high: 200),
        RefBand(label: '1st Trimester', low: 105, high: 230),
      ];
      final json = encodeRefBandsJson(bands);
      expect(json, isNotNull);
      final back = decodeRefBandsJson(json);
      expect(back, isNotNull);
      expect(back!.length, 2);
      expect(back[0].label, 'Non-Pregnant Women');
      expect(back[0].low, 80);
      expect(back[1].high, 230);
    });

    test('empty / junk → null', () {
      expect(decodeRefBandsJson(null), isNull);
      expect(decodeRefBandsJson('[]'), isNull);
      expect(decodeRefBandsJson('not-json'), isNull);
      expect(encodeRefBandsJson(const []), isNull);
    });

    test('normalize key stable', () {
      const a = [
        RefBand(label: 'A', low: 1, high: 2),
        RefBand(label: 'B', low: 3, high: 4),
      ];
      const b = [
        RefBand(label: 'a', low: 1, high: 2),
        RefBand(label: 'B', low: 3, high: 4),
      ];
      expect(normalizeRefBandsKey(a), normalizeRefBandsKey(b));
    });
  });

  group('computeFlagWithBands', () {
    test('value inside a stage → normal', () {
      expect(
        computeFlagWithBands(
          value: 5.5,
          refBands: const [
            RefBand(label: 'Stage', low: 4, high: 5.6),
            RefBand(label: 'Stage', low: 5.7, high: 6.4),
          ],
        ),
        ObservationFlag.normal,
      );
    });

    test('below all → low; above all → high; gap → abnormal', () {
      const bands = [
        RefBand(label: 'Low band', low: 4, high: 5),
        RefBand(label: 'High band', low: 7, high: 8),
      ];
      expect(computeFlagWithBands(value: 3, refBands: bands), ObservationFlag.low);
      expect(computeFlagWithBands(value: 9, refBands: bands), ObservationFlag.high);
      expect(
        computeFlagWithBands(value: 6, refBands: bands),
        ObservationFlag.abnormal,
      );
    });

    test('falls back to simple refs', () {
      expect(
        computeFlagWithBands(value: 200, refLow: 70, refHigh: 110),
        ObservationFlag.high,
      );
    });
  });
}
