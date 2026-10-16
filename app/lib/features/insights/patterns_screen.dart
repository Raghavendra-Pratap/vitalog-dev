import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

/// On-device pattern hints — ADR-003 / 003a safe copy (no disease labels, no cause claims).
class PatternsScreen extends StatefulWidget {
  const PatternsScreen({super.key, required this.store});

  final LocalStore store;

  @override
  State<PatternsScreen> createState() => _PatternsScreenState();
}

class _PatternsScreenState extends State<PatternsScreen> {
  var _loading = true;
  List<Map<String, Object?>> _habits = [];
  Map<String, Map<String, Map<String, Object?>>> _habitLogs = {};
  List<MedicalItem> _meds = [];
  var _taken30 = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final habits = await widget.store.listHabits(pid);
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 30));
    final ymd = DateFormat('yyyy-MM-dd').format;
    final logs = await widget.store.habitLogsForRange(
      pid,
      ymd(start),
      ymd(end),
    );
    final meds = await widget.store.listMedications(pid);
    final outcomes = await widget.store.countDoseOutcomesLastDays(pid);
    if (!mounted) return;
    setState(() {
      _habits = habits;
      _habitLogs = logs;
      _meds = meds;
      _taken30 = outcomes.taken;
      _loading = false;
    });
  }

  List<String> _clinicBiasHints(String profileId) {
    final byParamClinic = <String, Map<String, List<double>>>{};
    final obs = widget.store.observations
        .where((o) => o.profileId == profileId && o.valueNum != null);
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
      final name = widget.store.observations
          .firstWhere(
            (o) => o.parameterCode == e.key,
            orElse: () => widget.store.observations.first,
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
        '(from your saved readings — for context only, not a diagnosis).',
      );
      if (hints.length >= 8) break;
    }
    return hints;
  }

  String? _clinicForObservation(ObservationRecord o) {
    for (final r in widget.store.reports) {
      if (r.id == o.reportId) {
        final title = r.title.trim();
        if (title.isNotEmpty) return title;
      }
    }
    return null;
  }

  List<String> _contextHints() {
    final hints = <String>[];
    var activeHabitDays = 0;
    for (final byHabit in _habitLogs.values) {
      for (final log in byHabit.values) {
        final done = (log['done'] as int? ?? 0) == 1;
        final v = (log['value'] as num?)?.toDouble() ?? 0;
        if (done || v > 0) activeHabitDays++;
      }
    }
    if (_habits.isNotEmpty) {
      hints.add(
        activeHabitDays == 0
            ? 'You have ${_habits.length} habits. Log check-ins so they can appear beside lab charts as timing context — not as cause and effect.'
            : 'Last 30 days: check-ins on about $activeHabitDays habit-days across ${_habits.length} habits. Open a lab trend to see habit periods alongside readings (context only).',
      );
    }
    if (_meds.isNotEmpty) {
      hints.add(
        _taken30 == 0
            ? 'You have ${_meds.length} medicines on file. Dose Taken / Skip on Reminders builds a timeline you can view beside reports — still not medical advice.'
            : 'Last 30 days: $_taken30 dose logs across ${_meds.length} medicines. Use Trends to place dose periods next to lab points for timing context only.',
      );
    }
    if (_habits.isNotEmpty && _meds.isNotEmpty) {
      hints.add(
        'Habits and medicines can sit on the same chart as your reports so you notice timing. Vitalog never claims one caused the other.',
      );
    }
    return hints;
  }

  @override
  Widget build(BuildContext context) {
    final pid = widget.store.activeProfileId;
    final hints = <String>[
      if (pid != null) ..._clinicBiasHints(pid),
      ..._contextHints(),
    ];
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(title: const Text('Patterns')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                Text(
                  'Hints from your on-device logs only. Shown for context — Vitalog does not diagnose or claim cause and effect.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Text(
                  'Alongside your reports',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                if (hints.isEmpty)
                  Text(
                    'Not enough overlapping habit, medicine, or lab history yet for a fair comparison.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  for (final h in hints)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: BodylineColors.surface,
                        borderRadius:
                            BorderRadius.circular(BodylineRadii.cardSmall),
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
