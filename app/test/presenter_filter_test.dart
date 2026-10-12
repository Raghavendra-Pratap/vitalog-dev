import 'package:flutter_test/flutter_test.dart';
import 'package:bodyline/features/presenter/presenter_filter.dart';

void main() {
  PresenterFilter base({
    Set<String> systems = const {'liver', 'thyroid'},
    bool all = false,
    DateTime? from,
    DateTime? to,
  }) =>
      PresenterFilter(
        profileId: 'p1',
        systemCodes: systems,
        includeLabs: true,
        includeVisits: false,
        includeProcedures: false,
        includeAttachments: false,
        from: from,
        to: to,
        allSystemsSelected: all,
      );

  test('date range inclusive of end day', () {
    final f = base(
      from: DateTime(2024, 1, 1),
      to: DateTime(2024, 1, 31),
    );
    expect(f.includesDate(DateTime(2024, 1, 1, 8)), isTrue);
    expect(f.includesDate(DateTime(2024, 1, 31, 18)), isTrue);
    expect(f.includesDate(DateTime(2023, 12, 31)), isFalse);
    expect(f.includesDate(DateTime(2024, 2, 1)), isFalse);
  });

  test('unknown system only when all selected', () {
    expect(base(all: false).includesSystem(null), isFalse);
    expect(base(all: true).includesSystem(null), isTrue);
    expect(base().includesSystem('liver'), isTrue);
    expect(base().includesSystem('heart'), isFalse);
  });

  test('isValid needs systems and a kind', () {
    final emptySystems = PresenterFilter(
      profileId: 'p1',
      systemCodes: {},
      includeLabs: true,
      includeVisits: true,
      includeProcedures: true,
      includeAttachments: true,
    );
    expect(emptySystems.isValid, isFalse);
    expect(base().isValid, isTrue);
  });
}
