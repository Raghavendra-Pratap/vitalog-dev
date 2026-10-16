import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

/// Habit-style month track for one medicine (taken / partial / skipped / off).
///
/// Later day-tap: dose take/skip only for **today and yesterday**;
/// notes may be added for older days.
class MedicineMonthTrack extends StatefulWidget {
  const MedicineMonthTrack({
    super.key,
    required this.store,
    required this.medication,
    this.showHeader = true,
  });

  final LocalStore store;
  final MedicalItem medication;
  /// When false (Layout B rail), skip the large title row.
  final bool showHeader;

  @override
  State<MedicineMonthTrack> createState() => _MedicineMonthTrackState();
}

class _MedicineMonthTrackState extends State<MedicineMonthTrack> {
  late DateTime _month;
  Map<String, String> _days = {};
  var _loading = true;
  int _done = 0;
  int _scheduled = 0;
  int _partial = 0;
  int _skipped = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  @override
  void didUpdateWidget(covariant MedicineMonthTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.medication.id != widget.medication.id) {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final map = await widget.store.medicationMonthDayStates(
      medicationId: widget.medication.id,
      month: _month,
    );
    var done = 0;
    var scheduled = 0;
    var partial = 0;
    var skipped = 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final e in map.entries) {
      final day = DateTime.tryParse(e.key);
      if (day == null) continue;
      if (day.isAfter(today)) continue;
      switch (e.value) {
        case 'off':
        case 'future':
          break;
        case 'done':
          scheduled++;
          done++;
          break;
        case 'partial':
          scheduled++;
          partial++;
          break;
        case 'skipped':
          scheduled++;
          skipped++;
          break;
        case 'none':
          scheduled++;
          break;
        default:
          break;
      }
    }
    if (!mounted) return;
    setState(() {
      _days = map;
      _done = done;
      _scheduled = scheduled;
      _partial = partial;
      _skipped = skipped;
      _loading = false;
    });
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.medication;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (widget.showHeader) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: BodylineColors.tealTint,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.medication_outlined,
                          color: BodylineColors.tealDark,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontFamily: 'Fraunces',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 26,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (m.kind != null && m.kind!.isNotEmpty) m.kind,
                                if (m.strength != null && m.strength!.isNotEmpty)
                                  m.strength,
                                m.courseStatus == 'active'
                                    ? 'Active course'
                                    : 'Completed',
                              ].whereType<String>().join(' · '),
                              style: TextStyle(
                                color: BodylineColors.inkSubtle,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        label: 'This month',
                        value: _scheduled == 0
                            ? '—'
                            : '$_done of $_scheduled',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatChip(
                        label: 'Partial days',
                        value: '$_partial',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatChip(
                        label: 'Skipped',
                        value: '$_skipped',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _shiftMonth(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        DateFormat.yMMMM().format(_month),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _shiftMonth(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'X = not scheduled that day',
                  style: TextStyle(
                    fontSize: 12,
                    color: BodylineColors.inkSubtle,
                  ),
                ),
                const SizedBox(height: 12),
                _MonthGrid(month: _month, days: _days),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    _legend(BodylineColors.teal, 'Taken'),
                    _legend(
                      BodylineColors.teal.withValues(alpha: 0.38),
                      'Partial',
                    ),
                    _legend(BodylineColors.orangeTint, 'Skipped'),
                    _legend(BodylineColors.border.withValues(alpha: 0.5), 'Missed'),
                    _legendX(),
                  ],
                ),
                if (m.instructions != null &&
                    m.instructions!.trim().isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    'Instructions',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    m.instructions!,
                    style: TextStyle(
                      fontSize: 13,
                      color: BodylineColors.inkSubtle,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _legend(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: BodylineColors.inkSubtle),
          ),
        ],
      );

  Widget _legendX() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: Center(
              child: Text(
                '×',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: BodylineColors.inkMuted,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Not scheduled',
            style: TextStyle(fontSize: 12, color: BodylineColors.inkSubtle),
          ),
        ],
      );
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: BodylineColors.chip,
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: BodylineColors.inkSubtle),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.days});
  final DateTime month;
  final Map<String, String> days;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1; // Mon=0
    final cells = <Widget>[
      for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
        Center(
          child: Text(
            d,
            style: TextStyle(fontSize: 11, color: BodylineColors.inkSubtle),
          ),
        ),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++)
        _dayCell(
          DateTime(month.year, month.month, d),
          days[DateFormat('yyyy-MM-dd')
                  .format(DateTime(month.year, month.month, d))] ??
              'none',
        ),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      childAspectRatio: 1,
      children: cells,
    );
  }

  Widget _dayCell(DateTime day, String st) {
    final label = '${day.day}';
    switch (st) {
      case 'off':
        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BodylineColors.chip,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '×',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: BodylineColors.inkMuted,
            ),
          ),
        );
      case 'done':
        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BodylineColors.teal,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        );
      case 'partial':
        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BodylineColors.teal.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: BodylineColors.ink,
            ),
          ),
        );
      case 'skipped':
        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BodylineColors.orangeTint,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: BodylineColors.orangeText,
            ),
          ),
        );
      case 'future':
        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: BodylineColors.inkSubtle.withValues(alpha: 0.45),
            ),
          ),
        );
      default: // none / missed
        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BodylineColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: BodylineColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: BodylineColors.ink,
            ),
          ),
        );
    }
  }
}

/// Right-rail settings for a selected medicine.
class MedicineSettingsCard extends StatelessWidget {
  const MedicineSettingsCard({
    super.key,
    required this.medication,
    this.timesLabel,
    this.onEdit,
  });

  final MedicalItem medication;
  final String? timesLabel;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Type', medication.kind ?? '—'),
      if (medication.strength != null && medication.strength!.isNotEmpty)
        ('Strength', medication.strength!),
      ('Times', timesLabel?.isNotEmpty == true ? timesLabel! : 'Not set'),
      ('Course', medication.courseStatus == 'active' ? 'Active' : 'Completed'),
      if (medication.prescribedAs != null &&
          medication.prescribedAs!.trim().isNotEmpty)
        ('Prescribed as', medication.prescribedAs!),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Settings',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          for (final r in rows) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.$1,
                    style: TextStyle(
                      fontSize: 13,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    r.$2,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (onEdit != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  foregroundColor: BodylineColors.tealDark,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Edit medicine',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
