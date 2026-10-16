import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/habits_notes_store.dart';
import '../../data/local_store.dart';
import '../../theme/tokens.dart';
import '../../notifications/reminder_notifications.dart';
import 'habit_day_log_dialog.dart';
import 'habit_editor.dart';

IconData habitIconFor(Map<String, Object?> h) {
  final key = ((h['template_key'] as String?) ?? '').toLowerCase();
  final title = ((h['title'] as String?) ?? '').toLowerCase();
  if (key == 'walk' || title.contains('walk')) return Icons.directions_walk;
  if (key == 'water' || title.contains('water')) {
    return Icons.water_drop_outlined;
  }
  if (title.contains('sugar') ||
      title.startsWith('no ') ||
      title.contains('avoid')) {
    return Icons.block;
  }
  if (key == 'sleep_early' || title.contains('sleep')) {
    return Icons.bedtime_outlined;
  }
  if (key == 'meditate' || title.contains('meditat')) {
    return Icons.self_improvement;
  }
  if (title.contains('stretch')) return Icons.accessibility_new;
  if (title.contains('pill') ||
      title.contains('tablet') ||
      title.contains('medicine') ||
      title.contains('statin') ||
      title.contains('thyroid')) {
    return Icons.medication_outlined;
  }
  return Icons.check_circle_outline;
}

/// Habit detail: stats, 3-month grid, week bars (desktop mockup).
class HabitDetailScreen extends StatefulWidget {
  const HabitDetailScreen({
    super.key,
    required this.store,
    required this.habitId,
    required this.onChanged,
    this.embedded = false,
    this.showSettingsInline = true,
  });

  final LocalStore store;
  final String habitId;
  final VoidCallback onChanged;
  final bool embedded;
  /// When false (desktop 3-col), settings live in the right rail.
  final bool showSettingsInline;

  @override
  State<HabitDetailScreen> createState() => HabitDetailScreenState();
}

class HabitDetailScreenState extends State<HabitDetailScreen> {
  Map<String, Object?>? _habit;
  Map<String, Map<String, Object?>> _logs = {};
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HabitDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.habitId != widget.habitId) {
      _loading = true;
      _load();
    }
  }

  Future<void> reload() => _load();

  String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _load() async {
    final h = await widget.store.getHabit(widget.habitId);
    if (h == null) {
      if (mounted) {
        setState(() {
          _habit = null;
          _loading = false;
        });
      }
      return;
    }
    final pid = h['profile_id']! as String;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 2, 1);
    final end = DateTime(now.year, now.month + 1, 0);
    final all = await widget.store.habitLogsForRange(
      pid,
      _ymd(start),
      _ymd(end),
    );
    if (!mounted) return;
    setState(() {
      _habit = h;
      _logs = all[widget.habitId] ?? {};
      _loading = false;
    });
  }

  Future<void> _edit() async {
    if (_habit == null) return;
    final ok = await showHabitEditor(
      context: context,
      store: widget.store,
      existing: _habit,
    );
    if (ok) {
      widget.onChanged();
      await _load();
    }
  }

  Future<void> _openDayLog(String ymd) async {
    final h = _habit;
    if (h == null) return;
    final changed = await showHabitDayLogDialog(
      context: context,
      store: widget.store,
      habit: h,
      loggedOnYmd: ymd,
      onChanged: () {
        widget.onChanged();
      },
    );
    if (!mounted) return;
    if (changed) {
      widget.onChanged();
      await _load();
    }
  }

  Future<void> _deleteHabit() async {
    final h = _habit;
    if (h == null) return;
    final id = h['id']! as String;
    final title = h['title'] as String? ?? 'Habit';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete habit?'),
        content: Text('Remove “$title” from this profile. Past logs stay on device until purged.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.softDeleteHabit(id);
    try {
      await ReminderNotifications.instance.cancelDailyHabit(id);
    } catch (_) {}
    widget.onChanged();
    if (mounted && !widget.embedded) {
      Navigator.of(context).maybePop();
    }
  }

  Map<String, Object?>? get habit => _habit;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final h = _habit;
    if (h == null) {
      return Center(
        child: Text(
          'Habit not found',
          style: TextStyle(color: BodylineColors.inkSubtle),
        ),
      );
    }

    final kind = (h['kind'] as String?) ?? 'yes_no';
    final title = h['title'] as String? ?? 'Habit';
    final unit = (h['unit_label'] as String?)?.trim();
    final unitShort = (unit != null && unit.isNotEmpty)
        ? unit
        : (kind == 'duration' ? 'min' : '');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d30Start = today.subtract(const Duration(days: 29));
    final d90Start = today.subtract(const Duration(days: 89));
    final s30 = habitWindowStats(
      habit: h,
      logs: _logs,
      start: d30Start,
      end: today,
    );
    final s90 = habitWindowStats(
      habit: h,
      logs: _logs,
      start: d90Start,
      end: today,
    );
    final avg = s30.valuedDays > 0 ? s30.sumValues / s30.valuedDays : null;
    final createdMs = h['created_at'] as int?;
    final since = createdMs == null
        ? null
        : DateFormat('MMMM yyyy')
            .format(DateTime.fromMillisecondsSinceEpoch(createdMs));
    final schedule = habitScheduleLabel(h['days_mask'] as String?);
    final charts = habitChartCodes(h);

    final months = <DateTime>[
      DateTime(now.year, now.month - 2, 1),
      DateTime(now.year, now.month - 1, 1),
      DateTime(now.year, now.month, 1),
    ];

    final content = ListView(
      padding: EdgeInsets.fromLTRB(
        widget.embedded ? 4 : 20,
        widget.embedded ? 0 : 12,
        widget.embedded ? 4 : 20,
        24,
      ),
      children: [
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
                habitIconFor(h),
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
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontFamily: 'Fraunces',
                          fontWeight: FontWeight.w600,
                          fontSize: 26,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    since == null ? schedule : '$schedule · since $since',
                    style: TextStyle(
                      color: BodylineColors.inkSubtle,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () => _openDayLog(
                DateFormat('yyyy-MM-dd').format(DateTime.now()),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: BodylineColors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              child: const Text('Update today'),
            ),
            IconButton(
              tooltip: 'Delete habit',
              onPressed: _deleteHabit,
              icon: const Icon(Icons.delete_outline),
            ),
            if (!widget.embedded)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: _edit,
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _StatChip(
                label: 'Last 30 days',
                value: s30.scheduled == 0
                    ? '—'
                    : '${s30.done} of ${s30.scheduled}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatChip(
                label: 'Last 90 days',
                value: s90.scheduled == 0
                    ? '—'
                    : '${s90.done} of ${s90.scheduled}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatChip(
                label: 'Average',
                value: avg == null
                    ? '—'
                    : '${avg.toStringAsFixed(avg == avg.roundToDouble() ? 0 : 1)}'
                        '${unitShort.isEmpty ? '' : ' $unitShort'}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatChip(
                label: 'Partial days',
                value: '${s30.partial}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Text(
              'Last 3 months',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            Text(
              'Lighter = partial day',
              style: TextStyle(
                fontSize: 12,
                color: BodylineColors.inkSubtle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < months.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: _CompactMonthGrid(
                  month: months[i],
                  habit: h,
                  logs: _logs,
                  onDayTap: _openDayLog,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 22),
        if (kind != 'yes_no') ...[
          Row(
            children: [
              Text(
                'This week',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Text(
                unitShort.isEmpty ? 'amount' : unitShort,
                style: TextStyle(
                  fontSize: 12,
                  color: BodylineColors.inkSubtle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _WeekBars(
            habit: h,
            logs: _logs,
            goal: (h['goal_value'] as num?)?.toDouble(),
            onDayTap: _openDayLog,
          ),
          const SizedBox(height: 22),
        ],
        if (widget.showSettingsInline) ...[
          HabitSettingsCard(habit: h, onEdit: _edit),
          if (charts.isNotEmpty) ...[
            const SizedBox(height: 12),
            HabitTrendsCard(chartCodes: charts),
          ],
        ],
      ],
    );

    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(title: Text(title)),
      body: content,
    );
  }
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: BodylineColors.inkSubtle,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class HabitSettingsCard extends StatelessWidget {
  const HabitSettingsCard({
    super.key,
    required this.habit,
    required this.onEdit,
    this.profileName,
  });

  final Map<String, Object?> habit;
  final VoidCallback onEdit;
  final String? profileName;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Type', habitKindLabel(habit['kind'] as String?)),
      ('Your goal', habitGoalLabel(habit)),
      ('Days', habitScheduleLabel(habit['days_mask'] as String?)),
      ('Reminder', habitReminderLabel(habit)),
      if (profileName != null && profileName!.isNotEmpty)
        ('For', profileName!),
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
                Text(
                  r.$2,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
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
                'Edit habit',
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

class HabitTrendsCard extends StatelessWidget {
  const HabitTrendsCard({super.key, required this.chartCodes});
  final List<String> chartCodes;

  @override
  Widget build(BuildContext context) {
    final names = chartCodes.join(' and ');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.link, size: 18, color: BodylineColors.tealDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shown on your trends',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: BodylineColors.tealDark,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$names show this habit as a shaded period — for context only, not cause and effect.',
                  style: TextStyle(
                    fontSize: 12,
                    color: BodylineColors.inkSubtle,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactMonthGrid extends StatelessWidget {
  const _CompactMonthGrid({
    required this.month,
    required this.habit,
    required this.logs,
    required this.onDayTap,
  });
  final DateTime month;
  final Map<String, Object?> habit;
  final Map<String, Map<String, Object?>> logs;
  final void Function(String ymd) onDayTap;

  @override
  Widget build(BuildContext context) {
    final kind = (habit['kind'] as String?) ?? 'yes_no';
    final goal = (habit['goal_value'] as num?)?.toDouble();
    final mask = (habit['days_mask'] as String?) ?? '1111111';
    final days = DateTime(month.year, month.month + 1, 0).day;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat.MMM().format(month),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: BodylineColors.inkSubtle,
          ),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            childAspectRatio: 1,
          ),
          itemCount: days,
          itemBuilder: (_, i) {
            final day = DateTime(month.year, month.month, i + 1);
            final ymd = DateFormat('yyyy-MM-dd').format(day);
            final scheduled = habitScheduledOn(mask, day);
            final future = day.isAfter(today);
            final String st;
            if (!scheduled || future) {
              st = 'off';
            } else {
              st = habitDayState(kind: kind, goalValue: goal, log: logs[ymd]);
            }
            final Color fill = switch (st) {
              'done' => BodylineColors.teal,
              'partial' => BodylineColors.teal.withValues(alpha: 0.38),
              'off' => BodylineColors.border.withValues(alpha: 0.25),
              _ => BodylineColors.surface,
            };
            final cell = Container(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(4),
                border: st == 'none'
                    ? Border.all(color: BodylineColors.border)
                    : null,
              ),
            );
            if (future) return cell;
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onDayTap(ymd),
                child: cell,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({
    required this.habit,
    required this.logs,
    required this.goal,
    required this.onDayTap,
  });
  final Map<String, Object?> habit;
  final Map<String, Map<String, Object?>> logs;
  final double? goal;
  final void Function(String ymd) onDayTap;

  @override
  Widget build(BuildContext context) {
    final kind = (habit['kind'] as String?) ?? 'yes_no';
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final values = <double>[];
    final states = <String>[];
    final ymds = <String>[];
    for (var i = 0; i < 7; i++) {
      final day = weekStart.add(Duration(days: i));
      final ymd = DateFormat('yyyy-MM-dd').format(day);
      final log = logs[ymd];
      final v = (log?['value'] as num?)?.toDouble() ?? 0;
      values.add(v);
      states.add(habitDayState(kind: kind, goalValue: goal, log: log));
      ymds.add(ymd);
    }
    final maxV = [
      ...values,
      if (goal != null && goal! > 0) goal!,
      1.0,
    ].reduce((a, b) => a > b ? a : b);

    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => onDayTap(ymds[i]),
                  child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    values[i] <= 0
                        ? ''
                        : values[i].toStringAsFixed(
                            values[i] == values[i].roundToDouble() ? 0 : 1,
                          ),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: BodylineColors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: FractionallySizedBox(
                      heightFactor: (values[i] / maxV).clamp(0.04, 1.0),
                      widthFactor: 1,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: states[i] == 'partial'
                              ? BodylineColors.teal.withValues(alpha: 0.38)
                              : BodylineColors.teal,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 11,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                ],
              ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Notes linked to this habit (day notes from the log modal, etc.).
class HabitNotesCard extends StatefulWidget {
  const HabitNotesCard({
    super.key,
    required this.store,
    required this.habit,
    required this.onChanged,
  });

  final LocalStore store;
  final Map<String, Object?> habit;
  final VoidCallback onChanged;

  @override
  State<HabitNotesCard> createState() => _HabitNotesCardState();
}

class _HabitNotesCardState extends State<HabitNotesCard> {
  List<Map<String, Object?>> _notes = [];
  var _loading = true;

  String get _habitId => widget.habit['id']! as String;
  String get _title => widget.habit['title'] as String? ?? 'Habit';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HabitNotesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.habit['id'] != widget.habit['id']) {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final rows = await widget.store.listNotesForHabit(_habitId);
    if (!mounted) return;
    setState(() {
      _notes = rows;
      _loading = false;
    });
  }

  Future<void> reload() => _load();

  Future<void> _addOrEdit({Map<String, Object?>? existing}) async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final ymd = (existing?['start_ymd'] as String?) ?? today;
    final ctrl = TextEditingController(
      text: (existing?['body'] as String?) ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Note for today' : 'Edit note'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 5,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: 'e.g. took a break, long walk after travel…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted || result == null) return;
    await widget.store.upsertHabitDayNote(
      profileId: pid,
      habitId: _habitId,
      habitTitle: _title,
      ymd: ymd,
      body: result,
      chartCodes: habitChartCodes(widget.habit),
    );
    widget.onChanged();
    await _load();
  }

  String _dateLabel(Map<String, Object?> n) {
    final ymd = n['start_ymd'] as String?;
    if (ymd == null || ymd.isEmpty) return 'Undated';
    final d = DateTime.tryParse(ymd);
    if (d == null) return ymd;
    return DateFormat('d MMM yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Notes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              TextButton(
                onPressed: () => _addOrEdit(),
                style: TextButton.styleFrom(
                  foregroundColor: BodylineColors.tealDark,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '+ Add',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_notes.isEmpty)
            Text(
              'Day notes for this habit show here and on Notes.',
              style: TextStyle(
                fontSize: 12,
                color: BodylineColors.inkSubtle,
                height: 1.35,
              ),
            )
          else
            for (var i = 0; i < _notes.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              InkWell(
                onTap: () => _addOrEdit(existing: _notes[i]),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dateLabel(_notes[i]),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: BodylineColors.tealDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (_notes[i]['body'] as String?) ?? '',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }
}
