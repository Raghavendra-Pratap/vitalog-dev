import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../medicines/todays_doses_panel.dart';
import '../../data/habits_notes_store.dart';
import 'habit_editor.dart';
import 'habit_detail_screen.dart';

/// Today dashboard — habits + today's medicines (desktop mockup DesktopTodayV3).
class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.store,
    required this.onChanged,
    this.desktop = false,
    this.onOpenHabits,
    this.onOpenMedicines,
  });

  final LocalStore store;
  final VoidCallback onChanged;
  final bool desktop;
  final VoidCallback? onOpenHabits;
  final VoidCallback? onOpenMedicines;

  @override
  State<TodayScreen> createState() => TodayScreenState();
}

class TodayScreenState extends State<TodayScreen> {
  List<Map<String, Object?>> _habits = [];
  Set<String> _done = {};
  Map<String, Map<String, Object?>> _todayLogs = {};
  Map<String, Set<String>> _weekDone = {};
  Map<String, Map<String, Map<String, Object?>>> _weekLogs = {};
  List<MedicationDoseSlot> _doses = [];
  var _loading = true;

  String get _ymd => DateFormat('yyyy-MM-dd').format(DateTime.now());

  String get _profileName {
    final id = widget.store.activeProfileId;
    for (final p in widget.store.profiles) {
      if (p.id == id) return p.name;
    }
    return 'Profile';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      if (!mounted) return;
      setState(() {
        _habits = [];
        _done = {};
        _todayLogs = {};
        _weekDone = {};
        _weekLogs = {};
        _doses = [];
        _loading = false;
      });
      return;
    }
    final habits = await widget.store.listHabits(pid);
    final done = await widget.store.habitDoneIdsForDay(pid, _ymd);
    final todayLogs = await widget.store.habitLogsForDay(pid, _ymd);
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 6));
    final startY = DateFormat('yyyy-MM-dd').format(start);
    final endY = DateFormat('yyyy-MM-dd').format(end);
    final week = await widget.store.habitDoneMapForRange(pid, startY, endY);
    final weekLogs = await widget.store.habitLogsForRange(pid, startY, endY);
    final doses = await widget.store.listTodaysDoses(pid);
    if (!mounted) return;
    setState(() {
      _habits = habits;
      _done = done;
      _todayLogs = todayLogs;
      _weekDone = week;
      _weekLogs = weekLogs;
      _doses = doses;
      _loading = false;
    });
  }

  Future<void> promptAdd() async {
    final ok = await showHabitEditor(context: context, store: widget.store);
    if (ok) {
      widget.onChanged();
      await _load();
    }
  }

  Future<void> _toggleHabit(String id, bool done) async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;
    Map<String, Object?>? h;
    for (final x in _habits) {
      if (x['id'] == id) { h = x; break; }
    }
    final kind = (h?['kind'] as String?) ?? 'yes_no';
    final goal = (h?['goal_value'] as num?)?.toDouble();
    if (kind == 'yes_no') {
      await widget.store.setHabitProgress(
        habitId: id,
        profileId: pid,
        loggedOnYmd: _ymd,
        kind: kind,
        done: done,
        loggedByProfileId: pid,
      );
    } else if (!done) {
      await widget.store.setHabitProgress(
        habitId: id,
        profileId: pid,
        loggedOnYmd: _ymd,
        kind: kind,
        goalValue: goal,
        value: 0,
        loggedByProfileId: pid,
      );
    } else {
      final log = _todayLogs[id];
      final cur = (log?['value'] as num?)?.toDouble() ?? 0;
      final step = kind == 'duration' ? 5.0 : 1.0;
      await widget.store.setHabitProgress(
        habitId: id,
        profileId: pid,
        loggedOnYmd: _ymd,
        kind: kind,
        goalValue: goal,
        value: cur + step,
        loggedByProfileId: pid,
      );
    }
    await _load();
    widget.onChanged();
  }

  Future<void> _openHabit(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HabitDetailScreen(
          store: widget.store,
          habitId: id,
          onChanged: () {
            widget.onChanged();
            _load();
          },
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    // Keep static tokens in sync with the active ThemeData (light/dark bake race).
    BodylineColors.applyBrightness(Theme.of(context).brightness);

    if (_loading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final taken = _doses.where((d) => d.isDone).length;
    final habitDone = _done.length;
    final habitTotal = _habits.length;

    final list = ListView(
      padding: EdgeInsets.fromLTRB(
        widget.desktop ? 28 : 20,
        widget.desktop ? 8 : 16,
        widget.desktop ? 28 : 20,
        40,
      ),
      children: [
        if (!widget.desktop) ...[
          Text(
            'Today',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: BodylineColors.ink,
                ),
          ),
          Text(
            DateFormat('EEEE · d MMM yyyy').format(DateTime.now()),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: BodylineColors.inkSubtle,
                ),
          ),
          const SizedBox(height: 16),
        ],
        // Summary chips
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryChip(
              label: _doses.isEmpty
                  ? 'Medicines: none scheduled today'
                  : 'Medicines: $taken of ${_doses.length} taken today',
            ),
            _SummaryChip(
              label: habitTotal == 0
                  ? 'Habits: none yet'
                  : 'Habits: $habitDone of $habitTotal done today',
            ),
            if (_doses.isNotEmpty || habitTotal > 0)
              _SummaryChip(
                label: 'Tap Take or Log below — changes stay on this device',
              ),
          ],
        ),
        const SizedBox(height: 20),
        // Three cards row on desktop
        if (widget.desktop)
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 960;
              final meds = _MedicinesCard(
                doses: _doses,
                store: widget.store,
                onChanged: () async {
                  widget.onChanged();
                  await _load();
                },
                onManage: widget.onOpenMedicines,
              );
              final habits = _HabitsCard(
                habits: _habits,
                done: _done,
                logs: _todayLogs,
                onToggle: _toggleHabit,
                onOpen: _openHabit,
                onAllHabits: widget.onOpenHabits,
                onAdd: promptAdd,
              );
              final family = _FamilyTodayCard(
                store: widget.store,
                onChanged: () async {
                  widget.onChanged();
                  await _load();
                },
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: meds),
                    const SizedBox(width: 14),
                    Expanded(child: habits),
                    const SizedBox(width: 14),
                    Expanded(child: family),
                  ],
                );
              }
              return Column(
                children: [
                  meds,
                  const SizedBox(height: 14),
                  habits,
                  const SizedBox(height: 14),
                  family,
                ],
              );
            },
          )
        else ...[
          _MedicinesCard(
            doses: _doses,
            store: widget.store,
            onChanged: () async {
              widget.onChanged();
              await _load();
            },
            onManage: widget.onOpenMedicines,
          ),
          const SizedBox(height: 14),
          _HabitsCard(
            habits: _habits,
            done: _done,
            logs: _todayLogs,
            onToggle: _toggleHabit,
            onOpen: _openHabit,
            onAllHabits: widget.onOpenHabits,
            onAdd: promptAdd,
          ),
          const SizedBox(height: 14),
          _FamilyTodayCard(
            store: widget.store,
            onChanged: () async {
              widget.onChanged();
              await _load();
            },
          ),
        ],
        const SizedBox(height: 28),
        Text(
          'Last 7 days',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFamily: 'Fraunces',
                fontWeight: FontWeight.w600,
                color: BodylineColors.ink,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Done · partial · empty · today outlined',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: BodylineColors.inkSubtle,
              ),
        ),
        const SizedBox(height: 12),
        _WeekGrid(
          habits: _habits,
          doses: _doses,
          weekDone: _weekDone,
          weekLogs: _weekLogs,
          todayYmd: _ymd,
        ),
        const SizedBox(height: 16),
        _HealthFooter(store: widget.store, profileName: _profileName),
      ],
    );

    // Always Scaffold: Home pushes this as a bare route (no Material → yellow
    // underlines + transparent canvas over black). Desktop shell nests fine.
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: widget.desktop ? list : SafeArea(child: list),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BodylineColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: BodylineColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            height: 1.3,
            color: BodylineColors.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.title,
    required this.trailing,
    required this.child,
  });
  final String title;
  final Widget trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BodylineColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        side: BorderSide(color: BodylineColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _MedicinesCard extends StatelessWidget {
  const _MedicinesCard({
    required this.doses,
    required this.store,
    required this.onChanged,
    this.onManage,
  });
  final List<MedicationDoseSlot> doses;
  final LocalStore store;
  final VoidCallback onChanged;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: 'Medicines',
      trailing: TextButton(
        onPressed: onManage,
        child: const Text('Manage'),
      ),
      child: doses.isEmpty
          ? Text(
              'No dose times for today. Add schedules under Medicines.',
              style: TextStyle(color: BodylineColors.inkSubtle, fontSize: 13),
            )
          : TodaysDosesPanel(
              store: store,
              onChanged: onChanged,
              compact: true,
              mode: TodaysDosesMode.detailList,
            ),
    );
  }
}

class _HabitsCard extends StatelessWidget {
  const _HabitsCard({
    required this.habits,
    required this.done,
    required this.logs,
    required this.onToggle,
    this.onOpen,
    this.onAllHabits,
    this.onAdd,
  });
  final List<Map<String, Object?>> habits;
  final Set<String> done;
  final Map<String, Map<String, Object?>> logs;
  final Future<void> Function(String id, bool done) onToggle;
  final Future<void> Function(String id)? onOpen;
  final VoidCallback? onAllHabits;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: 'Habits',
      trailing: TextButton(
        onPressed: onAllHabits,
        child: const Text('All habits'),
      ),
      child: habits.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No habits yet. Add one to check in daily.',
                  style: TextStyle(color: BodylineColors.inkSubtle, fontSize: 13),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: onAdd,
                  child: const Text('New habit'),
                ),
              ],
            )
          : Column(
              children: [
                for (final h in habits.take(6)) ...[
                  _HabitRow(
                    habit: h,
                    log: logs[h['id'] as String],
                    onToggle: onToggle,
                    onOpen: onOpen,
                  ),
                  if (h != habits.take(6).last) const SizedBox(height: 8),
                ],
                if (habits.length > 6) ...[
                  const SizedBox(height: 4),
                  TextButton(onPressed: onAllHabits, child: const Text('See all')),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New habit'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow({
    required this.habit,
    required this.log,
    required this.onToggle,
    this.onOpen,
  });
  final Map<String, Object?> habit;
  final Map<String, Object?>? log;
  final Future<void> Function(String id, bool done) onToggle;
  final Future<void> Function(String id)? onOpen;

  @override
  Widget build(BuildContext context) {
    final id = habit['id']! as String;
    final title = habit['title'] as String? ?? 'Habit';
    final kind = (habit['kind'] as String?) ?? 'yes_no';
    final goal = (habit['goal_value'] as num?)?.toDouble();
    final st = habitDayState(kind: kind, goalValue: goal, log: log);
    final unit = habit['unit_label'] as String?;
    String status;
    if (st == 'done') {
      status = 'Done';
    } else if (st == 'partial') {
      final v = (log?['value'] as num?)?.toDouble() ?? 0;
      final g = goal ?? 0;
      final u = unit != null && unit.isNotEmpty
          ? ' $unit'
          : (kind == 'duration' ? ' min' : '');
      status = g > 0
          ? '${v.toStringAsFixed(0)} / ${g.toStringAsFixed(0)}$u'
          : '${v.toStringAsFixed(0)}$u';
    } else {
      status = kind == 'yes_no' ? 'Not yet' : 'Log progress';
    }
    return InkWell(
      onTap: onOpen == null ? null : () => onOpen!(id),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    status,
                    style: TextStyle(fontSize: 12, color: BodylineColors.inkSubtle),
                  ),
                ],
              ),
            ),
            if (st == 'done')
              FilledButton.tonal(
                onPressed: () => onToggle(id, false),
                child: const Text('Undo'),
              )
            else
              FilledButton(
                onPressed: () => onToggle(id, true),
                style: FilledButton.styleFrom(backgroundColor: BodylineColors.teal),
                child: Text(kind == 'yes_no' ? 'Mark done' : 'Log'),
              ),
          ],
        ),
      ),
    );
  }
}

class _FamilyTodayCard extends StatefulWidget {
  const _FamilyTodayCard({required this.store, required this.onChanged});
  final LocalStore store;
  final VoidCallback onChanged;

  @override
  State<_FamilyTodayCard> createState() => _FamilyTodayCardState();
}

class _FamilyTodayCardState extends State<_FamilyTodayCard> {
  final Map<String, int> _pendingMeds = {};
  final Map<String, int> _pendingHabits = {};
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _FamilyTodayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  Future<void> _load() async {
    final pendingM = <String, int>{};
    final pendingH = <String, int>{};
    final ymd = DateFormat('yyyy-MM-dd').format(DateTime.now());
    for (final p in widget.store.profiles) {
      final doses = await widget.store.listTodaysDoses(p.id);
      pendingM[p.id] = doses.where((d) => !d.isDone).length;
      final habits = await widget.store.listHabits(p.id);
      final logs = await widget.store.habitLogsForDay(p.id, ymd);
      var open = 0;
      for (final h in habits) {
        final kind = (h['kind'] as String?) ?? 'yes_no';
        final goal = (h['goal_value'] as num?)?.toDouble();
        final st = habitDayState(
          kind: kind,
          goalValue: goal,
          log: logs[h['id'] as String],
        );
        if (st != 'done') open++;
      }
      pendingH[p.id] = open;
    }
    if (!mounted) return;
    setState(() {
      _pendingMeds
        ..clear()
        ..addAll(pendingM);
      _pendingHabits
        ..clear()
        ..addAll(pendingH);
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.store.profiles;
    return _CardShell(
      title: 'Family today',
      trailing: const SizedBox.shrink(),
      child: profiles.isEmpty
          ? Text(
              'No profiles yet.',
              style: TextStyle(color: BodylineColors.inkSubtle, fontSize: 13),
            )
          : Column(
              children: [
                for (final p in profiles.take(4)) ...[
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: BodylineColors.tealTint,
                        child: Text(
                          p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: 12,
                            color: BodylineColors.teal,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              !_ready
                                  ? '…'
                                  : _statusLine(p.id),
                              style: TextStyle(
                                fontSize: 12,
                                color: BodylineColors.inkSubtle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (p.id != widget.store.activeProfileId)
                        TextButton(
                          onPressed: () async {
                            await widget.store.switchProfile(p.id);
                            widget.onChanged();
                          },
                          child: const Text('Log for them'),
                        )
                      else
                        Text(
                          'You',
                          style: TextStyle(
                            fontSize: 12,
                            color: BodylineColors.inkSubtle,
                          ),
                        ),
                    ],
                  ),
                  if (p != profiles.take(4).last) const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  String _statusLine(String id) {
    final m = _pendingMeds[id] ?? 0;
    final h = _pendingHabits[id] ?? 0;
    if (m == 0 && h == 0) return 'Caught up today';
    final parts = <String>[];
    if (m > 0) parts.add('$m dose${m == 1 ? '' : 's'} left');
    if (h > 0) parts.add('$h habit${h == 1 ? '' : 's'} open');
    return parts.join(' · ');
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.habits,
    required this.doses,
    required this.weekDone,
    required this.weekLogs,
    required this.todayYmd,
  });
  final List<Map<String, Object?>> habits;
  final List<MedicationDoseSlot> doses;
  final Map<String, Set<String>> weekDone;
  final Map<String, Map<String, Map<String, Object?>>> weekLogs;
  final String todayYmd;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) {
      final d = DateTime.now().subtract(Duration(days: 6 - i));
      return d;
    });
    final rows = <(String, String Function(DateTime))>[
      for (final medName in {
        for (final d in doses) d.name,
      })
        (
          medName,
          (day) {
            if (DateFormat('yyyy-MM-dd').format(day) != todayYmd) return 'none';
            final all = doses.where((d) => d.name == medName).toList();
            if (all.isEmpty) return 'none';
            if (all.every((d) => d.isDone)) return 'done';
            if (all.any((d) => d.isDone)) return 'partial';
            return 'none';
          },
        ),
      for (final h in habits)
        (
          h['title'] as String? ?? 'Habit',
          (day) {
            final ymd = DateFormat('yyyy-MM-dd').format(day);
            final id = h['id'] as String;
            final kind = (h['kind'] as String?) ?? 'yes_no';
            final goal = (h['goal_value'] as num?)?.toDouble();
            return habitDayState(
              kind: kind,
              goalValue: goal,
              log: weekLogs[id]?[ymd],
            );
          },
        ),
    ];

    if (rows.isEmpty) {
      return Text(
        'Add medicines or habits to see a week grid here.',
        style: TextStyle(color: BodylineColors.inkSubtle, fontSize: 13),
      );
    }

    return Material(
      color: BodylineColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        side: BorderSide(color: BodylineColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 140),
                for (final d in days)
                  SizedBox(
                    width: 52,
                    child: Text(
                      DateFormat('E\nd').format(d),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight:
                            DateFormat('yyyy-MM-dd').format(d) == todayYmd
                                ? FontWeight.w800
                                : FontWeight.w500,
                        color: BodylineColors.inkSubtle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final row in rows) ...[
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      row.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final d in days)
                    SizedBox(
                      width: 52,
                      height: 36,
                      child: Center(
                        child: _DayCell(
                          state: row.$2(d),
                          isToday:
                              DateFormat('yyyy-MM-dd').format(d) == todayYmd,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.state, required this.isToday});
  final String state;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    switch (state) {
      case 'done':
        fill = BodylineColors.teal;
        break;
      case 'partial':
        fill = BodylineColors.teal.withValues(alpha: 0.35);
        break;
      default:
        fill = BodylineColors.chip;
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        border: isToday
            ? Border.all(color: BodylineColors.ink, width: 1.5)
            : null,
      ),
      child: state == 'done'
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }
}

class _HealthFooter extends StatelessWidget {
  const _HealthFooter({required this.store, required this.profileName});
  final LocalStore store;
  final String profileName;

  @override
  Widget build(BuildContext context) {
    final pid = store.activeProfileId;
    final weight = pid == null
        ? null
        : store.observations
            .where((o) =>
                o.profileId == pid &&
                o.parameterCode.toLowerCase() == 'weight')
            .fold<ObservationRecord?>(null, (best, o) {
            if (best == null || o.observedAt.isAfter(best.observedAt)) {
              return o;
            }
            return best;
          });
    final bits = <String>[];
    if (weight != null) {
      bits.add('Weight ${weight.valueReported} ${weight.unitReported}');
    }
    final text = bits.isEmpty
        ? 'Measurements from Health Connect or manual entry show here when present.'
        : 'Also on this device for $profileName: ${bits.join(' · ')}.';
    return Text(
      text,
      style: TextStyle(fontSize: 13, color: BodylineColors.inkSubtle, height: 1.35),
    );
  }
}
