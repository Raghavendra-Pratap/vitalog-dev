import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../widgets/drug_name_field.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../notifications/reminder_notifications.dart';
import '../../theme/tokens.dart';
import 'dose_wait_header_chip.dart';
import '../../theme/desktop_layout.dart';
import '../../desktop.dart';
import 'medicine_editor_dialog.dart';
import 'medicine_month_track.dart';

enum _MedLeftMode { active, visit }

/// Current medicines & remedies (dose Taken/Skip lives on Reminders).
class MedicinesScreen extends StatefulWidget {
  const MedicinesScreen({
    super.key,
    required this.store,
    required this.onChanged,
    this.embedded = false,
  });

  final LocalStore store;
  final VoidCallback onChanged;
  final bool embedded;

  @override
  MedicinesScreenState createState() => MedicinesScreenState();
}

class MedicinesScreenState extends State<MedicinesScreen> {
  Future<void> promptAdd() => _addMedicine();

  Future<void> _applyScheduleFromResult(
    String medId,
    Map<String, Object?> result,
  ) async {
    final rawSlots = result['slots'];
    final slots = <({String hm, double amount})>[];
    if (rawSlots is List) {
      for (final e in rawSlots) {
        if (e is! Map) continue;
        final hm = '${e['hm'] ?? ''}'.trim();
        if (!hm.contains(':')) continue;
        final a = e['amount'];
        final amount = a is num
            ? a.toDouble()
            : double.tryParse('$a') ?? 1.0;
        slots.add((hm: hm, amount: amount <= 0 ? 1.0 : amount));
      }
    }
    await widget.store.softDeleteMedicationSchedules(medId);
    if (slots.isEmpty) return;
    final daysMask = (result['daysMask'] as String?) ?? '1111111';
    final interval = result['intervalDays'] as int?;
    final unit = result['doseUnit'] as String?;
    await widget.store.addMedicationSchedule(
      medicationId: medId,
      times: [for (final s in slots) s.hm],
      slots: slots,
      daysMask: daysMask,
      intervalDays: interval,
      doseUnit: unit,
    );
    try {
      await ReminderNotifications.instance.ensurePermission();
      final schedules = await widget.store.listAllMedicationSchedules();
      await ReminderNotifications.instance.rescheduleAllDoses(schedules);
    } catch (_) {}
  }


  List<MedicalItem> _meds = [];
  List<MedicalItem> _allMeds = [];
  List<VisitRecord> _visits = [];
  _MedLeftMode _leftMode = _MedLeftMode.active;
  String? _selectedVisitId;
  var _loading = true;
  var _loadGen = 0;
  int _taken30 = 0;
  int _skipped30 = 0;
  Map<String, int> _takenByMed = {};
  List<MedicationDoseSlot> _todayDoses = [];
  String? _selectedMedId;
  final Map<String, String> _timesByMed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MedicinesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // IndexedStack keeps this State; reload after adds from elsewhere.
    _load();
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _meds = [];
        _allMeds = [];
        _visits = [];
        _taken30 = 0;
        _skipped30 = 0;
        _takenByMed = {};
        _todayDoses = [];
        _loading = false;
      });
      return;
    }
    final meds = await widget.store.listMedications(pid);
    final allMeds = await widget.store.listAllMedications(pid);
    final visits = await widget.store.listVisits(pid);
    final outcomes = await widget.store.countDoseOutcomesLastDays(pid);
    final takenBy = await widget.store.takenCountsLastDays(pid);
    final todayDoses = await widget.store.listTodaysDoses(pid);
    final allSchedules = await widget.store.listAllMedicationSchedules();
    final timesByMed = <String, String>{};
    final grouped = <String, List<String>>{};
    for (final s in allSchedules) {
      grouped.putIfAbsent(s.medicationId, () => []).addAll(s.times);
    }
    for (final e in grouped.entries) {
      timesByMed[e.key] = e.value.join(', ');
    }
    // Also schedules for completed meds in view — load per selected later if needed.
    for (final m in allMeds) {
      if (timesByMed.containsKey(m.id)) continue;
      final schedules = await widget.store.listMedicationSchedules(m.id);
      final times = <String>[];
      for (final s in schedules) {
        final raw = s.title.trim();
        if (raw.startsWith('[')) {
          try {
            // times_json stored in title by listMedicationSchedules
            final cleaned = raw
                .replaceAll('"', '')
                .replaceAll('[', '')
                .replaceAll(']', '');
            times.addAll(
              cleaned.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
            );
          } catch (_) {}
        }
      }
      if (times.isNotEmpty) timesByMed[m.id] = times.join(', ');
    }
    if (!mounted || gen != _loadGen) return;
    setState(() {
      _meds = meds;
      _allMeds = allMeds;
      _visits = visits;
      _taken30 = outcomes.taken;
      _skipped30 = outcomes.skipped;
      _takenByMed = takenBy;
      _todayDoses = todayDoses;
      _timesByMed
        ..clear()
        ..addAll(timesByMed);
      _loading = false;
      if (_selectedMedId != null &&
          !meds.any((x) => x.id == _selectedMedId) &&
          !allMeds.any((x) => x.id == _selectedMedId)) {
        _selectedMedId = meds.isEmpty ? null : meds.first.id;
      } else if (_selectedMedId == null && meds.isNotEmpty) {
        _selectedMedId = meds.first.id;
      }
      if (_selectedVisitId != null &&
          !allMeds.any((x) => x.visitId == _selectedVisitId)) {
        _selectedVisitId = null;
        if (_leftMode == _MedLeftMode.visit) {
          _leftMode = _MedLeftMode.active;
        }
      }
    });
  }

  Future<void> _addMedicine() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;

    final upcoming = await _upcomingFollowUps(pid);
    if (!mounted) return;

    final result = await showMedicineEditorDialog(
      context: context,
      store: widget.store,
      upcomingFollowUps: [
        for (final o in upcoming) (dateYmd: o.dateYmd, label: o.label),
      ],
    );
    if (result == null || !mounted) return;

    final name = '${result['name'] ?? ''}'.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a medicine name to save.')),
      );
      return;
    }

    final pillsRaw = result['pills'];
    final pillCount =
        pillsRaw == null ? null : int.tryParse('$pillsRaw');

    try {
      final medId = await widget.store.addMedication(
        profileId: pid,
        name: name,
        kind: '${result['kind'] ?? 'other'}',
        strength: result['strength'] as String?,
        instructions: result['instructions'] as String?,
        pillCount: pillCount,
        restockOn: result['restock'] as String?,
        dosageForm: result['dosageForm'] as String?,
        endDate: result['endDate'] as String?,
      );

      final restock = result['restock'] as String?;
      if (restock != null && restock.trim().isNotEmpty) {
        try {
          final parts = restock.trim().split('-');
          if (parts.length == 3) {
            final due = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
              9,
            );
            await ReminderNotifications.instance.scheduleReminder(
              ReminderRecord(
                id: 'restock-$medId',
                profileId: pid,
                kind: 'restock',
                title: 'Restock $name',
                dueAt: due,
              ),
            );
          }
        } catch (_) {}
      }

      await _applyScheduleFromResult(medId, result);

      if (mounted) {
        final note = result['stockNote'] as String?;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              note == null || note.isEmpty ? 'Saved $name.' : 'Saved $name. $note',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save this medicine. Try again.'),
          ),
        );
      }
    } finally {
      widget.onChanged();
      await _load();
    }
  }

  Future<void> _editMedicine(MedicalItem m) async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;
    final upcoming = await _upcomingFollowUps(pid);
    if (!mounted) return;
    final result = await showMedicineEditorDialog(
      context: context,
      store: widget.store,
      initial: m,
      upcomingFollowUps: [
        for (final o in upcoming) (dateYmd: o.dateYmd, label: o.label),
      ],
    );
    if (result == null || !mounted) return;
    final name = '${result['name'] ?? ''}'.trim();
    if (name.isEmpty) return;
    final pillsRaw = result['pills'];
    final pillCount =
        pillsRaw == null ? null : int.tryParse('$pillsRaw');
    try {
      await widget.store.updateMedication(
        id: m.id,
        name: name,
        kind: '${result['kind'] ?? m.kind ?? 'other'}',
        strength: result['strength'] as String?,
        instructions: result['instructions'] as String?,
        pillCount: pillCount,
        restockOn: result['restock'] as String?,
        prescribedAs:
            (result['prescribedAs'] as String?) ?? m.prescribedAs,
        dosageForm: result['dosageForm'] as String?,
        endDate: result['endDate'] as String?,
      );
      await _applyScheduleFromResult(m.id, result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated $name.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this medicine.')),
        );
      }
    } finally {
      widget.onChanged();
      await _load();
    }
  }

  Future<void> _markAlternative(MedicalItem m) async {
    final prescribed =
        m.prescribedAs?.isNotEmpty == true ? m.prescribedAs! : m.title;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _AlternativeNameDialog(prescribed: prescribed),
    );
    if (name == null || name.trim().isEmpty) return;
    final takenAs = name.trim();
    await widget.store.setMedicationAlternative(
      id: m.id,
      takenAs: takenAs,
      previousName: m.title,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Now listed as $takenAs.')),
    );
    widget.onChanged();
    await _load();
  }

  Future<void> _deleteMedicine(MedicalItem m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete medicine?'),
        content: Text(
          'Remove “${m.title}” from your current list? '
          'Dose history on this device stays; daily alerts for it stop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: BodylineColors.ink,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.softDeleteMedication(m.id);
    try {
      final schedules = await widget.store.listAllMedicationSchedules();
      await ReminderNotifications.instance.rescheduleAllDoses(schedules);
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted ${m.title}.')),
    );
    widget.onChanged();
    await _load();
  }

  Future<List<_FollowUpOption>> _upcomingFollowUps(String profileId) async {
    final visits = await widget.store.listVisits(profileId);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <_FollowUpOption>[];
    for (final v in visits) {
      final raw = v.followUpDate;
      if (raw == null || raw.trim().isEmpty) continue;
      DateTime? d;
      try {
        final parts = raw.trim().split('-');
        if (parts.length == 3) {
          d = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
        }
      } catch (_) {
        d = null;
      }
      if (d == null || d.isBefore(today)) continue;
      final who = (v.providerName != null && v.providerName!.trim().isNotEmpty)
          ? v.providerName!.trim()
          : 'Follow-up';
      out.add(
        _FollowUpOption(
          dateYmd: DateFormat('yyyy-MM-dd').format(d),
          label: '$who · ${DateFormat('d MMM yyyy').format(d)}',
        ),
      );
    }
    out.sort((a, b) => a.dateYmd.compareTo(b.dateYmd));
    // Dedupe same date label
    final seen = <String>{};
    return [
      for (final o in out)
        if (seen.add(o.dateYmd)) o,
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.embedded && useWideShell(context)) {
      return _buildDesktop(context);
    }
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: widget.embedded
          ? null
          : AppBar(
            title: const Text('Medicines & remedies'),
            actions: doseWaitActions(),
          ),
      floatingActionButton: FloatingActionButton(
        heroTag: widget.embedded ? 'care-tab-medicines-fab' : 'page-medicines-fab',
        onPressed: _addMedicine,
        tooltip: 'Add medicine',
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: _buildMobileBody(context),
    );
  }


  Widget _buildDesktop(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final monthFmt = DateFormat('MMMM yyyy');
    final visitsWithMeds = [
      for (final v in _visits)
        if (_allMeds.any((m) => m.visitId == v.id)) v,
    ];
    final groups = <String, List<VisitRecord>>{};
    for (final v in visitsWithMeds) {
      final key = monthFmt.format(v.visitedAt);
      groups.putIfAbsent(key, () => []).add(v);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesktopLayout.mainPaddingH,
        8,
        DesktopLayout.mainPaddingH,
        DesktopLayout.mainPaddingV,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _masterCard(
                  title: 'Active medication',
                  subtitle:
                      '${_meds.length} currently taking · prescription, ad-hoc, supplements',
                  selected: _leftMode == _MedLeftMode.active,
                  onTap: () => setState(() {
                    _leftMode = _MedLeftMode.active;
                    _selectedVisitId = null;
                    if (_meds.isNotEmpty) {
                      _selectedMedId = _meds.first.id;
                    }
                  }),
                ),
                const SizedBox(height: 16),
                Text(
                  'Visits',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Only visits that have linked medicines.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: BodylineColors.inkSubtle,
                      ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: visitsWithMeds.isEmpty
                      ? Text(
                          'No visit-linked medicines yet.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : ListView(
                          children: [
                            for (final entry in groups.entries) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                                child: Text(
                                  entry.key,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              for (final v in entry.value) ...[
                                _visitTitleCard(v, fmt),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DesktopLayout.mainGap),
          Expanded(child: _medicineCardsPane(context)),
          const SizedBox(width: DesktopLayout.mainGap),
          SizedBox(
            width: 260,
            child: _trackSettingsRail(context),
          ),
        ],
      ),
    );
  }

  /// Layout B col 3: settings + one-month track for the selected medicine.
  Widget _trackSettingsRail(BuildContext context) {
    final pool = _paneMeds;
    MedicalItem? selected;
    if (_selectedMedId != null) {
      for (final m in pool) {
        if (m.id == _selectedMedId) {
          selected = m;
          break;
        }
      }
    }
    if (selected == null && pool.isNotEmpty) {
      selected = pool.first;
    }
    if (selected == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: BodylineColors.surface,
          borderRadius: BorderRadius.circular(BodylineRadii.card),
          border: Border.all(color: BodylineColors.border),
        ),
        child: Text(
          pool.isEmpty
              ? 'Select Active or a visit, then a medicine.'
              : 'Select a medicine to see its month track.',
          style: TextStyle(color: BodylineColors.inkSubtle, fontSize: 13),
        ),
      );
    }
    return ListView(
      children: [
        MedicineSettingsCard(
          medication: selected,
          timesLabel: _timesByMed[selected.id],
          onEdit: () => _editMedicine(selected!),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 420,
          child: MedicineMonthTrack(
            key: ValueKey('track-b-${selected.id}'),
            store: widget.store,
            medication: selected,
            showHeader: false,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Mark taken or skipped under Reminders. '
          'Days marked × are outside this course or have no dose times.',
          style: TextStyle(
            fontSize: 12,
            color: BodylineColors.inkSubtle,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _masterCard({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? BodylineColors.selectedWash : BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BodylineRadii.card),
            border: Border.all(
              color: selected ? BodylineColors.teal : BodylineColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: selected
                      ? BodylineColors.tealDark
                      : BodylineColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _visitTitleCard(VisitRecord v, DateFormat fmt) {
    final selected =
        _leftMode == _MedLeftMode.visit && _selectedVisitId == v.id;
    return Material(
      color: selected ? BodylineColors.selectedWash : BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        onTap: () => setState(() {
          _leftMode = _MedLeftMode.visit;
          _selectedVisitId = v.id;
          final linked = [
            for (final m in _allMeds)
              if (m.visitId == v.id) m,
          ];
          _selectedMedId = linked.isEmpty ? null : linked.first.id;
        }),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BodylineRadii.card),
            border: Border.all(
              color: selected ? BodylineColors.teal : BodylineColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                v.reason?.isNotEmpty == true ? v.reason! : 'Visit',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? BodylineColors.tealDark
                      : BodylineColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  fmt.format(v.visitedAt),
                  if (v.providerName?.isNotEmpty == true) v.providerName!,
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<MedicalItem> get _paneMeds {
    if (_leftMode == _MedLeftMode.active) return _meds;
    final vid = _selectedVisitId;
    if (vid == null) return const [];
    return [for (final m in _allMeds) if (m.visitId == vid) m];
  }


  Widget _adherenceStrip(BuildContext context) {
    final pending = _todayDoses.where((d) => !d.isDone).length;
    var nextLabel = 'No doses left today';
    final upcoming = _todayDoses.where((d) => !d.isDone).toList()
      ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    if (upcoming.isNotEmpty) {
      final n = upcoming.first;
      nextLabel = 'Next · ${n.name} at ${n.timeHm}';
    }
    final refill = [
      for (final m in _meds)
        if (m.restockOn != null && m.restockOn!.isNotEmpty) m,
    ];
    var refillLabel = 'No refill dates set';
    if (refill.isNotEmpty) {
      refill.sort((a, b) => (a.restockOn!).compareTo(b.restockOn!));
      final r = refill.first;
      refillLabel = 'Refill · ${r.title} by ${r.restockOn}';
    }

    Widget cell(String k, String v) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: BodylineColors.chip,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: BodylineColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  k,
                  style: TextStyle(
                    fontSize: 11,
                    color: BodylineColors.inkSubtle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  v,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            cell('Last 30 days taken', '$_taken30'),
            const SizedBox(width: 8),
            cell('Skipped', '$_skipped30'),
            const SizedBox(width: 8),
            cell(
              'Today',
              pending == 0 ? 'All logged' : '$pending left',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '$nextLabel · $refillLabel',
          style: TextStyle(fontSize: 12, color: BodylineColors.inkSubtle),
        ),
      ],
    );
  }

  Widget _medicineCardsPane(BuildContext context) {
    final meds = _paneMeds;
    final title = _leftMode == _MedLeftMode.active
        ? 'Active medication'
        : () {
            for (final v in _visits) {
              if (v.id == _selectedVisitId) {
                return v.reason?.isNotEmpty == true ? v.reason! : 'Visit';
              }
            }
            return 'Visit medicines';
          }();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: ListView(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            _leftMode == _MedLeftMode.active
                ? 'Each card is one medicine. Menu for edit, alternative, or delete. Dose Taken / Skip is on Reminders.'
                : 'Medicines linked to this visit.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_leftMode == _MedLeftMode.active) ...[
            const SizedBox(height: 14),
            _adherenceStrip(context),
          ],
          const SizedBox(height: 16),
          if (meds.isEmpty)
            Text(
              _leftMode == _MedLeftMode.active
                  ? 'No active medicines yet. Tap Add medicine to start.'
                  : 'No medicines linked to this visit yet.',
              style: TextStyle(color: BodylineColors.inkSubtle),
            )
          else
            for (final m in meds) ...[
              _medicineCard(
                m,
                taken30: _takenByMed[m.id] ?? 0,
                selected: m.id == _selectedMedId,
                onSelect: () => setState(() => _selectedMedId = m.id),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _medicineCard(
    MedicalItem m, {
    int taken30 = 0,
    bool selected = false,
    VoidCallback? onSelect,
  }) {
    return Material(
      color: selected ? BodylineColors.selectedWash : BodylineColors.chip,
      borderRadius: BorderRadius.circular(BodylineRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        onTap: onSelect,
        child: Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(
          color: selected ? BodylineColors.teal : BodylineColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (taken30 > 0)
                  Text(
                    '$taken30 taken in last 30 days',
                    style: TextStyle(fontSize: 12, color: BodylineColors.inkSubtle),
                  ),
                if (m.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    m.subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                ],
                if (m.instructions != null &&
                    m.instructions!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    m.instructions!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                _statusPill(m.courseStatus, compact: true),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Medicine actions',
            onSelected: (action) {
              switch (action) {
                case 'edit':
                  _editMedicine(m);
                case 'alt':
                  _markAlternative(m);
                case 'delete':
                  _deleteMedicine(m);
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'alt',
                child: Text('Taking alternative / generic'),
              ),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _statusPill(String status, {bool compact = false}) {
    final label = switch (status) {
      'active' => 'Active',
      'completed' => 'Completed',
      'inactive' => 'Inactive',
      _ => status,
    };
    final bg = switch (status) {
      'active' => BodylineColors.tealTint,
      'completed' => BodylineColors.chip,
      'inactive' => BodylineColors.orangeTint,
      _ => BodylineColors.chip,
    };
    final fg = switch (status) {
      'active' => BodylineColors.tealDark,
      'completed' => BodylineColors.inkMuted,
      'inactive' => BodylineColors.orangeText,
      _ => BodylineColors.inkMuted,
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(BodylineRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildMobileBody(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final monthFmt = DateFormat('MMMM yyyy');
    final visitsWithMeds = [
      for (final v in _visits)
        if (_allMeds.any((m) => m.visitId == v.id)) v,
    ];
    final groups = <String, List<VisitRecord>>{};
    for (final v in visitsWithMeds) {
      final key = monthFmt.format(v.visitedAt);
      groups.putIfAbsent(key, () => []).add(v);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        Text(
          'Allopathic, Ayurvedic / AYUSH, homeopathic, or supplements — '
          'name is always free text. Optional times send a local alert. '
          'Mark taken or skipped under Reminders.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        _masterCard(
          title: 'Active medication',
          subtitle:
              '${_meds.length} currently taking · prescription, ad-hoc, supplements',
          selected: false,
          onTap: () => _openMobileDetail(
            mode: _MedLeftMode.active,
            title: 'Active medication',
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Visits',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Only visits that have linked medicines.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: BodylineColors.inkSubtle,
              ),
        ),
        const SizedBox(height: 8),
        if (visitsWithMeds.isEmpty)
          Text(
            'No visit-linked medicines yet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: BodylineColors.inkSubtle,
                ),
          )
        else
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Text(
                entry.key,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            for (final v in entry.value) ...[
              _masterCard(
                title: v.reason?.isNotEmpty == true ? v.reason! : 'Visit',
                subtitle: [
                  fmt.format(v.visitedAt),
                  if (v.providerName?.isNotEmpty == true) v.providerName!,
                ].join(' · '),
                selected: false,
                onTap: () => _openMobileDetail(
                  mode: _MedLeftMode.visit,
                  visitId: v.id,
                  title: v.reason?.isNotEmpty == true
                      ? v.reason!
                      : 'Visit medicines',
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
      ],
    );
  }

  Future<void> _openMobileDetail({
    required _MedLeftMode mode,
    String? visitId,
    required String title,
  }) async {
    setState(() {
      _leftMode = mode;
      _selectedVisitId = visitId;
    });
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MedsDetailPage(
          title: title,
          getMeds: () {
            if (mode == _MedLeftMode.active) return _meds;
            final vid = visitId;
            if (vid == null) return const <MedicalItem>[];
            return [for (final m in _allMeds) if (m.visitId == vid) m];
          },
          isActive: mode == _MedLeftMode.active,
          onEdit: _editMedicine,
          onAlt: _markAlternative,
          onDelete: _deleteMedicine,
        ),
      ),
    );
    if (mounted) await _load();
  }

}

class _MedsDetailPage extends StatefulWidget {
  const _MedsDetailPage({
    required this.title,
    required this.getMeds,
    required this.isActive,
    required this.onEdit,
    required this.onAlt,
    required this.onDelete,
  });

  final String title;
  final List<MedicalItem> Function() getMeds;
  final bool isActive;
  final Future<void> Function(MedicalItem m) onEdit;
  final Future<void> Function(MedicalItem m) onAlt;
  final Future<void> Function(MedicalItem m) onDelete;

  @override
  State<_MedsDetailPage> createState() => _MedsDetailPageState();
}

class _MedsDetailPageState extends State<_MedsDetailPage> {
  @override
  Widget build(BuildContext context) {
    final meds = widget.getMeds();
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(
            widget.isActive
                ? 'Each card is one medicine. Menu for edit, alternative, or delete. Dose Taken / Skip is on Reminders.'
                : 'Medicines linked to this visit.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (meds.isEmpty)
            Text(
              widget.isActive
                  ? 'No active medicines yet. Tap + to start.'
                  : 'No medicines linked to this visit yet.',
              style: TextStyle(color: BodylineColors.inkSubtle),
            )
          else
            for (final m in meds) ...[
              _detailMedCard(m),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _detailMedCard(MedicalItem m) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (m.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    m.subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                ],
                if (m.instructions != null &&
                    m.instructions!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    m.instructions!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Medicine actions',
            onSelected: (action) async {
              switch (action) {
                case 'edit':
                  await widget.onEdit(m);
                case 'alt':
                  await widget.onAlt(m);
                case 'delete':
                  await widget.onDelete(m);
              }
              if (mounted) setState(() {});
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'alt',
                child: Text('Taking alternative / generic'),
              ),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlternativeNameDialog extends StatefulWidget {
  const _AlternativeNameDialog({required this.prescribed});
  final String prescribed;

  @override
  State<_AlternativeNameDialog> createState() => _AlternativeNameDialogState();
}

class _AlternativeNameDialogState extends State<_AlternativeNameDialog> {
  final _taken = TextEditingController();

  @override
  void dispose() {
    _taken.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _taken.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Taking alternative / generic'),
      titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
      contentPadding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 28, 20),
      content: SizedBox(
        width: bodylineDialogWidth(context, 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Prescribed: ${widget.prescribed}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'What are you taking instead? Same salt / generic is fine — '
              'we keep the prescribed name for your records.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DrugNameField(
              controller: _taken,
              autofocus: true,
              showKindSubtitle: true,
              decoration: const InputDecoration(
                labelText: 'Bottle / brand name',
                hintText: 'e.g. Thyroxin',
                helperText: 'Suggestions are offline names only — not advice',
              ),
              onSelected: (_) => _submit(),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Update'),
        ),
      ],
    );
  }
}

class _FollowUpOption {
  const _FollowUpOption({required this.dateYmd, required this.label});
  final String dateYmd;
  final String label;
}

enum _RestockMode { none, date, fromStock, nextVisit }

/// Days of supply from stock ÷ daily dose slots (1 unit per scheduled time).
({int? days, DateTime? stockOut, DateTime? alertOn, String? analysis})
    _restockPlan({
  required int? pills,
  required int dosesPerDay,
  required int leadDays,
  DateTime? visitOn,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final lead = leadDays < 0 ? 0 : leadDays;
  final dpd = dosesPerDay <= 0 ? 1 : dosesPerDay;

  int? days;
  DateTime? stockOut;
  if (pills != null && pills > 0) {
    days = pills ~/ dpd;
    if (days < 1) days = 1;
    stockOut = today.add(Duration(days: days));
  }

  if (visitOn != null) {
    final visit = DateTime(visitOn.year, visitOn.month, visitOn.day);
    String analysis;
    if (stockOut == null) {
      analysis =
          'Reminder ${lead > 0 ? '$lead day${lead == 1 ? '' : 's'} before' : 'on'} this visit. Add stock + times to check supply.';
      final alert = visit.subtract(Duration(days: lead));
      return (
        days: days,
        stockOut: stockOut,
        alertOn: alert.isBefore(today) ? today : alert,
        analysis: analysis,
      );
    }
    final gap = stockOut.difference(visit).inDays;
    if (gap < 0) {
      analysis =
          'Stock runs out ${-gap} day${-gap == 1 ? '' : 's'} before this visit.';
    } else if (gap == 0) {
      analysis = 'Stock lasts about until this visit.';
    } else {
      analysis =
          'Stock looks fine through this visit (~$gap day${gap == 1 ? '' : 's'} spare).';
    }
    // Alert a few days before the earlier of stock-out or visit.
    final earlier = stockOut.isBefore(visit) ? stockOut : visit;
    final alert = earlier.subtract(Duration(days: lead));
    return (
      days: days,
      stockOut: stockOut,
      alertOn: alert.isBefore(today) ? today : alert,
      analysis: analysis,
    );
  }

  if (stockOut == null) {
    return (days: null, stockOut: null, alertOn: null, analysis: null);
  }
  final alert = stockOut.subtract(Duration(days: lead));
  final analysis = lead > 0
      ? 'About $days day${days == 1 ? '' : 's'} of supply · alert $lead day${lead == 1 ? '' : 's'} before.'
      : 'About $days day${days == 1 ? '' : 's'} of supply · alert on last day.';
  return (
    days: days,
    stockOut: stockOut,
    alertOn: alert.isBefore(today) ? today : alert,
    analysis: analysis,
  );
}

class _AddMedicineDialog extends StatefulWidget {
  const _AddMedicineDialog({
    this.upcomingFollowUps = const [],
    this.initial,
  });

  final List<_FollowUpOption> upcomingFollowUps;
  final MedicalItem? initial;

  @override
  State<_AddMedicineDialog> createState() => _AddMedicineDialogState();
}

class _AddMedicineDialogState extends State<_AddMedicineDialog> {
  late final TextEditingController _name;
  late final TextEditingController _strength;
  late final TextEditingController _instructions;
  final _times = TextEditingController();
  late final TextEditingController _pills;
  late final TextEditingController _restock;
  final _lead = TextEditingController(text: '3');
  late final TextEditingController _endDate;
  final _durationDays = TextEditingController();
  late String _kind;
  var _form = 'unset';
  var _restockMode = _RestockMode.none;
  String? _visitDateYmd;
  String? _nameError;
  String? _planNote;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.title ?? '');
    _strength = TextEditingController(text: i?.strength ?? '');
    _instructions = TextEditingController(text: i?.instructions ?? '');
    _endDate = TextEditingController(text: i?.endDate ?? '');
    _form = i?.dosageForm ?? 'unset';
    _pills = TextEditingController(
      text: i?.pillCount == null ? '' : '${i!.pillCount}',
    );
    _restock = TextEditingController(text: i?.restockOn ?? '');
    _kind = () {
      final k = i?.kind;
      if (k != null && kMedicationKinds.contains(k)) return k;
      return 'allopathic';
    }();
    if (i?.restockOn != null && i!.restockOn!.isNotEmpty) {
      _restockMode = _RestockMode.date;
    }
    _name.addListener(_onNameChanged);
    _times.addListener(_recalcRestock);
    _pills.addListener(_recalcRestock);
    _lead.addListener(_recalcRestock);
    if (widget.upcomingFollowUps.isNotEmpty) {
      _visitDateYmd = widget.upcomingFollowUps.first.dateYmd;
    }
  }

  void _onNameChanged() {
    if (_nameError != null && _name.text.trim().isNotEmpty) {
      setState(() => _nameError = null);
    }
  }

  int _dosesPerDay() {
    final raw = _times.text.trim();
    if (raw.isEmpty) return 1;
    final n = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .length;
    return n <= 0 ? 1 : n;
  }

  void _recalcRestock() {
    if (_restockMode == _RestockMode.none ||
        _restockMode == _RestockMode.date) {
      if (_planNote != null) setState(() => _planNote = null);
      return;
    }
    final pills = int.tryParse(_pills.text.trim());
    final lead = int.tryParse(_lead.text.trim()) ?? 3;
    DateTime? visitOn;
    if (_restockMode == _RestockMode.nextVisit && _visitDateYmd != null) {
      final p = _visitDateYmd!.split('-');
      if (p.length == 3) {
        visitOn = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
    }
    final plan = _restockPlan(
      pills: pills,
      dosesPerDay: _dosesPerDay(),
      leadDays: lead,
      visitOn: visitOn,
    );
    if (plan.alertOn != null &&
        (_restockMode == _RestockMode.fromStock ||
            _restockMode == _RestockMode.nextVisit)) {
      _restock.text = DateFormat('yyyy-MM-dd').format(plan.alertOn!);
    }
    setState(() => _planNote = plan.analysis);
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _times.removeListener(_recalcRestock);
    _pills.removeListener(_recalcRestock);
    _lead.removeListener(_recalcRestock);
    _name.dispose();
    _strength.dispose();
    _instructions.dispose();
    _times.dispose();
    _pills.dispose();
    _restock.dispose();
    _lead.dispose();
    _endDate.dispose();
    _durationDays.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter the name as on the bottle or prescription.');
      return;
    }
    if (_restockMode == _RestockMode.fromStock ||
        _restockMode == _RestockMode.nextVisit) {
      _recalcRestock();
    }
    Navigator.pop(context, {
      'name': name,
      'kind': _kind,
      if (_strength.text.trim().isNotEmpty) 'strength': _strength.text.trim(),
      if (_instructions.text.trim().isNotEmpty)
        'instructions': _instructions.text.trim(),
      if (_times.text.trim().isNotEmpty) 'times': _times.text.trim(),
      if (_pills.text.trim().isNotEmpty) 'pills': _pills.text.trim(),
      if (_restockMode != _RestockMode.none &&
          _restock.text.trim().isNotEmpty)
        'restock': _restock.text.trim(),
      if (_planNote != null && _planNote!.isNotEmpty) 'stockNote': _planNote!,
      if (widget.initial?.prescribedAs != null &&
          widget.initial!.prescribedAs!.isNotEmpty)
        'prescribedAs': widget.initial!.prescribedAs!,
      if (_form != 'unset') 'dosageForm': _form,
      if (_endDate.text.trim().isNotEmpty) 'endDate': _endDate.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
      contentPadding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 28, 20),
      insetPadding: bodylineDialogInset(context),
      title: Text(widget.initial == null ? 'Add medicine or remedy' : 'Edit medicine'),
      content: SizedBox(
        width: bodylineDialogWidth(context, 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(_kind),
                initialValue: _kind,
                items: [
                  for (final k in kMedicationKinds)
                    DropdownMenuItem(
                      value: k,
                      child: Text(medicationKindLabel(k)),
                    ),
                ],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              const SizedBox(height: 8),
              DrugNameField(
                controller: _name,
                autofocus: true,
                showKindSubtitle: true,
                preferredKind: _kind,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'As on the bottle or prescription',
                  helperText:
                      'Suggestions are offline names only — not advice',
                  errorText: _nameError,
                ),
                onSelected: (s) {
                  setState(() {
                    _kind = kMedicationKinds.contains(s.kind) ? s.kind : _kind;
                    _nameError = null;
                  });
                },
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _strength,
                decoration: const InputDecoration(
                  labelText: 'Strength (optional)',
                  hintText: '500 mg, 10 drops, 1 tsp…',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _form,
                items: const [
                  DropdownMenuItem(value: 'unset', child: Text('Form (optional)')),
                  DropdownMenuItem(value: 'tablet', child: Text('Tablet')),
                  DropdownMenuItem(value: 'capsule', child: Text('Capsule')),
                  DropdownMenuItem(value: 'syrup', child: Text('Syrup')),
                  DropdownMenuItem(value: 'tube', child: Text('Tube / cream')),
                  DropdownMenuItem(value: 'drops', child: Text('Drops')),
                  DropdownMenuItem(value: 'injection', child: Text('Injection')),
                  DropdownMenuItem(value: 'inhaler', child: Text('Inhaler')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _form = v ?? 'unset'),
                decoration: const InputDecoration(labelText: 'Form'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _durationDays,
                decoration: const InputDecoration(
                  labelText: 'Duration — days (optional)',
                  hintText: '7',
                  helperText: 'Sets an end date from today when you save',
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final n = int.tryParse(v.trim());
                  if (n != null && n > 0) {
                    final end = DateTime.now().add(Duration(days: n));
                    _endDate.text = DateFormat('yyyy-MM-dd').format(end);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _endDate,
                decoration: const InputDecoration(
                  labelText: 'Until / end date (optional)',
                  hintText: 'yyyy-MM-dd',
                  helperText: 'Leave blank while the course is active',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _instructions,
                decoration: const InputDecoration(
                  labelText: 'Instructions (optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _times,
                decoration: const InputDecoration(
                  labelText: 'Daily times (optional)',
                  hintText: '08:00, 20:00',
                  helperText: 'Local alerts at these times · used for stock days',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pills,
                decoration: const InputDecoration(
                  labelText: 'Pills / doses left (optional)',
                  hintText: '30',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              Text('Restock reminder', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('None'),
                    selected: _restockMode == _RestockMode.none,
                    onSelected: (_) => setState(() {
                      _restockMode = _RestockMode.none;
                      _restock.clear();
                      _planNote = null;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('From stock'),
                    selected: _restockMode == _RestockMode.fromStock,
                    onSelected: (_) {
                      setState(() => _restockMode = _RestockMode.fromStock);
                      _recalcRestock();
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Next visit'),
                    selected: _restockMode == _RestockMode.nextVisit,
                    onSelected: widget.upcomingFollowUps.isEmpty
                        ? null
                        : (_) {
                            setState(() {
                              _restockMode = _RestockMode.nextVisit;
                              _visitDateYmd ??=
                                  widget.upcomingFollowUps.first.dateYmd;
                            });
                            _recalcRestock();
                          },
                  ),
                  ChoiceChip(
                    label: const Text('Pick date'),
                    selected: _restockMode == _RestockMode.date,
                    onSelected: (_) => setState(() {
                      _restockMode = _RestockMode.date;
                      _planNote = null;
                    }),
                  ),
                ],
              ),
              if (_restockMode == _RestockMode.nextVisit) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey(_visitDateYmd),
                  initialValue: _visitDateYmd,
                  items: [
                    for (final o in widget.upcomingFollowUps)
                      DropdownMenuItem(
                        value: o.dateYmd,
                        child: Text(o.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _visitDateYmd = v);
                    _recalcRestock();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Follow-up visit',
                  ),
                ),
              ],
              if (_restockMode == _RestockMode.fromStock ||
                  _restockMode == _RestockMode.nextVisit) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _lead,
                  decoration: const InputDecoration(
                    labelText: 'Alert days before',
                    hintText: '3',
                    helperText: 'So you still have stock when you need it',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
              if (_restockMode == _RestockMode.date ||
                  _restockMode == _RestockMode.fromStock ||
                  _restockMode == _RestockMode.nextVisit) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _restock,
                  readOnly: _restockMode != _RestockMode.date,
                  decoration: InputDecoration(
                    labelText: _restockMode == _RestockMode.date
                        ? 'Restock by'
                        : 'Alert on',
                    hintText: 'YYYY-MM-DD',
                    helperText: _restockMode == _RestockMode.date
                        ? 'Local reminder on that morning'
                        : 'Calculated · edit mode “Pick date” to set manually',
                  ),
                ),
              ],
              if (_planNote != null && _planNote!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _planNote!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: BodylineColors.inkMuted,
                  ),
                ),
              ],
              if (_restockMode == _RestockMode.nextVisit &&
                  widget.upcomingFollowUps.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'No upcoming follow-up dates on Visits yet.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: BodylineColors.ink,
            foregroundColor: BodylineColors.paper,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

