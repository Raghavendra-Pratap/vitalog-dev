import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/habits_notes_store.dart';
import '../../data/local_store.dart';
import '../../theme/tokens.dart';
import 'habit_editor.dart';

/// Habit detail: month grid with partial shading, week totals, chart links.
class HabitDetailScreen extends StatefulWidget {
  const HabitDetailScreen({
    super.key,
    required this.store,
    required this.habitId,
    required this.onChanged,
    this.embedded = false,
  });

  final LocalStore store;
  final String habitId;
  final VoidCallback onChanged;
  final bool embedded;

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  Map<String, Object?>? _habit;
  Map<String, Map<String, Object?>> _monthLogs = {};
  var _loading = true;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = DateTime(DateTime.now().year, DateTime.now().month);
    _load();
  }

  String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _load() async {
    final h = await widget.store.getHabit(widget.habitId);
    if (h == null) {
      if (mounted) setState(() { _habit = null; _loading = false; });
      return;
    }
    final pid = h['profile_id']! as String;
    final start = DateTime(_month.year, _month.month, 1);
    final end = DateTime(_month.year, _month.month + 1, 0);
    final logs = await widget.store.habitLogsForRange(
      pid,
      _ymd(start),
      _ymd(end),
    );
    if (!mounted) return;
    setState(() {
      _habit = h;
      _monthLogs = logs[widget.habitId] ?? {};
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final h = _habit;
    if (h == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Habit')),
        body: const Center(child: Text('Habit not found')),
      );
    }
    final kind = (h['kind'] as String?) ?? 'yes_no';
    final goal = (h['goal_value'] as num?)?.toDouble();
    final title = h['title'] as String? ?? 'Habit';
    final unit = h['unit_label'] as String?;
    final charts = habitChartCodes(h);

    // Month stats
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    var doneDays = 0;
    var partialDays = 0;
    var scheduledDays = 0;
    var weekMinutes = 0.0;
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(_month.year, _month.month, d);
      final mask = (h['days_mask'] as String?) ?? '1111111';
      if (!habitScheduledOn(mask, day)) continue;
      if (day.isAfter(now)) continue;
      scheduledDays++;
      final st = habitDayState(
        kind: kind,
        goalValue: goal,
        log: _monthLogs[_ymd(day)],
      );
      if (st == 'done') doneDays++;
      if (st == 'partial') partialDays++;
    }
    if (kind == 'duration') {
      for (var i = 0; i < 7; i++) {
        final day = weekStart.add(Duration(days: i));
        final log = _monthLogs[_ymd(day)];
        // also check if outside loaded month — reload week separately if needed
        weekMinutes += (log?['value'] as num?)?.toDouble() ?? 0;
      }
    }

    final body = ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(
            scheduledDays == 0
                ? 'No scheduled days this month yet'
                : '$doneDays of $scheduledDays days'
                    '${partialDays > 0 ? ' · $partialDays partial' : ''}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFamily: 'Fraunces',
                ),
          ),
          if (kind == 'duration') ...[
            const SizedBox(height: 4),
            Text(
              '${weekMinutes.toStringAsFixed(weekMinutes == weekMinutes.roundToDouble() ? 0 : 1)}'
              '${unit != null && unit.isNotEmpty ? ' $unit' : ' min'} this week',
              style: TextStyle(color: BodylineColors.inkSubtle),
            ),
          ],
          if (goal != null && kind != 'yes_no') ...[
            const SizedBox(height: 4),
            Text(
              'Goal: ${goal.toString().replaceAll(RegExp(r"\.0$"), "")}'
              '${unit != null && unit.isNotEmpty ? " $unit" : kind == "duration" ? " min" : ""}',
              style: TextStyle(color: BodylineColors.inkSubtle, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _month = DateTime(_month.year, _month.month - 1);
                    _loading = true;
                  });
                  _load();
                },
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  DateFormat.yMMMM().format(_month),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _month = DateTime(_month.year, _month.month + 1);
                    _loading = true;
                  });
                  _load();
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MonthGrid(
            month: _month,
            habit: h,
            logs: _monthLogs,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _legendDot(BodylineColors.teal, 'Done'),
              const SizedBox(width: 12),
              _legendDot(BodylineColors.teal.withValues(alpha: 0.35), 'Partial'),
              const SizedBox(width: 12),
              _legendDot(BodylineColors.border, 'Empty'),
            ],
          ),
          if (charts.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Shown on trends',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFamily: 'Fraunces',
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Beside ${charts.join(", ")} — for context only, not cause and effect.',
              style: TextStyle(color: BodylineColors.inkSubtle, fontSize: 13),
            ),
          ],
        ],
      );

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontFamily: 'Fraunces',
                          )),
                ),
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _edit),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _edit),
        ],
      ),
      body: body,
    );
  }

  Widget _legendDot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: BodylineColors.inkSubtle)),
        ],
      );
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.habit,
    required this.logs,
  });
  final DateTime month;
  final Map<String, Object?> habit;
  final Map<String, Map<String, Object?>> logs;

  @override
  Widget build(BuildContext context) {
    final kind = (habit['kind'] as String?) ?? 'yes_no';
    final goal = (habit['goal_value'] as num?)?.toDouble();
    final mask = (habit['days_mask'] as String?) ?? '1111111';
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1; // Mon=0
    final cells = <Widget>[
      for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
        Center(
          child: Text(d,
              style: TextStyle(fontSize: 11, color: BodylineColors.inkSubtle)),
        ),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++)
        Builder(builder: (_) {
          final day = DateTime(month.year, month.month, d);
          final ymd = DateFormat('yyyy-MM-dd').format(day);
          final scheduled = habitScheduledOn(mask, day);
          final st = scheduled
              ? habitDayState(kind: kind, goalValue: goal, log: logs[ymd])
              : 'off';
          Color fill;
          switch (st) {
            case 'done':
              fill = BodylineColors.teal;
              break;
            case 'partial':
              fill = BodylineColors.teal.withValues(alpha: 0.35);
              break;
            case 'off':
              fill = Colors.transparent;
              break;
            default:
              fill = BodylineColors.border.withValues(alpha: 0.4);
          }
          return Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$d',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: st == 'done' ? Colors.white : BodylineColors.ink,
              ),
            ),
          );
        }),
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
}
