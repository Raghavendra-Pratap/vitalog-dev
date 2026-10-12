/// Scoped slice of a profile's vault — Presenter today; sealed share later (ADR-009).
class PresenterFilter {
  const PresenterFilter({
    required this.profileId,
    required this.systemCodes,
    required this.includeLabs,
    required this.includeVisits,
    required this.includeProcedures,
    required this.includeAttachments,
    this.from,
    this.to,
    this.allSystemsSelected = false,
  });

  final String profileId;
  final Set<String> systemCodes;
  final bool includeLabs;
  final bool includeVisits;
  final bool includeProcedures;
  final bool includeAttachments;
  final DateTime? from;
  final DateTime? to;

  /// True when the user left every body system selected (unknown params OK).
  final bool allSystemsSelected;

  bool get hasAnyKind =>
      includeLabs || includeVisits || includeProcedures || includeAttachments;

  bool get isValid => systemCodes.isNotEmpty && hasAnyKind;

  bool includesDate(DateTime d) {
    if (from != null) {
      final start = DateTime(from!.year, from!.month, from!.day);
      if (d.isBefore(start)) return false;
    }
    if (to != null) {
      final end = DateTime(to!.year, to!.month, to!.day, 23, 59, 59);
      if (d.isAfter(end)) return false;
    }
    return true;
  }

  /// Labs: known system must be selected; unknown only if all systems selected.
  bool includesSystem(String? systemCode) {
    if (systemCode == null || systemCode.isEmpty) return allSystemsSelected;
    return systemCodes.contains(systemCode);
  }
}
