import 'package:bodyline_core/bodyline_core.dart';
import 'package:test/test.dart';

void main() {
  group('computeNumericFlag', () {
    test('in range', () {
      expect(
        computeNumericFlag(value: 100, refLow: 70, refHigh: 110),
        ObservationFlag.normal,
      );
    });

    test('high', () {
      expect(
        computeNumericFlag(value: 200, refLow: 70, refHigh: 110),
        ObservationFlag.high,
      );
    });

    test('low', () {
      expect(
        computeNumericFlag(value: 50, refLow: 70, refHigh: 110),
        ObservationFlag.low,
      );
    });

    test('one-sided high only', () {
      expect(
        computeNumericFlag(value: 5, refHigh: 3),
        ObservationFlag.high,
      );
    });

    test('missing range → null', () {
      expect(computeNumericFlag(value: 1), isNull);
    });
  });

  group('flagLabel', () {
    test('never diagnoses', () {
      expect(flagLabel(ObservationFlag.high), contains("lab's range"));
      expect(flagLabel(ObservationFlag.low), contains("lab's range"));
      expect(flagLabel(ObservationFlag.normal), 'In range');
    });
  });

  group('parseReportedValue', () {
    test('plain number', () {
      final p = parseReportedValue('12.4');
      expect(p.numeric, 12.4);
      expect(p.comparator, isNull);
    });

    test('comparator', () {
      final p = parseReportedValue('<0.01');
      expect(p.comparator, '<');
      expect(p.numeric, 0.01);
    });
  });
}
