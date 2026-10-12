import 'package:flutter/material.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

/// On-device pattern hints — ADR-003 safe copy (no disease labels).
class PatternsScreen extends StatelessWidget {
  const PatternsScreen({super.key, required this.store});

  final LocalStore store;

  List<String> _clinicBiasHints(String profileId) {
    // Compare mean value per facility (visit providerClinic / report title heuristic)
    // vs overall mean for same parameter — neutral wording only.
    final byParamClinic = <String, Map<String, List<double>>>{};
    // We only have in-memory observations + reports; clinic from nearby visits is best-effort.
    final obs = store.observations.where((o) => o.profileId == profileId && o.valueNum != null);
    for (final o in obs) {
      final clinic = _clinicForObservation(o) ?? 'Unknown lab';
      byParamClinic
          .putIfAbsent(o.parameterCode, () => {})
          .putIfAbsent(clinic, () => [])
          .add(o.valueNum!);
    }
    final hints = <String>[];
    for (final e in byParamClinic.entries) {
      final clinics = e.value;
      if (clinics.length < 2) continue;
      final name = store.observations
          .firstWhere(
            (o) => o.parameterCode == e.key,
            orElse: () => store.observations.first,
          )
          .parameterName;
      final means = {
        for (final c in clinics.entries)
          if (c.value.length >= 2)
            c.key: c.value.reduce((a, b) => a + b) / c.value.length,
      };
      if (means.length < 2) continue;
      final sorted = means.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final high = sorted.first;
      final low = sorted.last;
      if ((high.value - low.value).abs() < 1e-6) continue;
      hints.add(
        'Often higher at ${high.key} than at ${low.key} for $name '
        '(from your saved readings — not a diagnosis).',
      );
      if (hints.length >= 8) break;
    }
    return hints;
  }

  String? _clinicForObservation(ObservationRecord o) {
    // Prefer report title as lab/package label when no visit clinic linked.
    for (final r in store.reports) {
      if (r.id == o.reportId) {
        final t = r.title.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return null;
  }

  List<String> _doseVisitHints(String profileId) {
    // Honest sparse pattern: many missed-dose style flags aren't stored;
    // surface a gentle habit↔visit note when both exist.
    final hints = <String>[];
    final hasMeds = store.observations.isNotEmpty; // placeholder signal
    // Count visits via care would be async; keep sync-friendly empty unless we have reports.
    if (store.reports.where((r) => r.profileId == profileId).length >= 2 &&
        hasMeds) {
      hints.add(
        'You have several saved packages and readings. When you log doses and visits on the same weeks, patterns about timing can show here — still not medical advice.',
      );
    }
    return hints;
  }

  @override
  Widget build(BuildContext context) {
    final pid = store.activeProfileId;
    final hints = <String>[
      if (pid != null) ..._clinicBiasHints(pid),
      if (pid != null) ..._doseVisitHints(pid),
    ];
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(title: const Text('Patterns')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text(
            'Hints from your on-device logs only. Vitalog does not diagnose.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (hints.isEmpty)
            Text(
              'Not enough overlapping lab or visit history yet for a fair comparison.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            for (final h in hints)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: BodylineColors.surface,
                  borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(h),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
