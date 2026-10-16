import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../medicines/todays_doses_panel.dart';
import '../../data/habits_notes_store.dart';
import 'habit_amount_log_dialog.dart';
import 'habit_editor.dart';
import 'habit_detail_screen.dart';
import '../settings/health_connect_screen.dart';

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
  static const _stepGoal = 8000;

  List<Map<String, Object?>> _habits = [];
  Set<String> _done = {};
  Map<String, Map<String, Object?>> _todayLogs = {};
  Map<String, Map<String, Map<String, Object?>>> _weekLogs = {};
  List<MedicationDoseSlot> _doses = [];
  Map<String, Map<String, String>> _medDayStates = {};
  Map<String, String> _medNames = {};
  Map<String, int> _stepsByDay = {};
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
        _weekLogs = {};
        _doses = [];
        _medDayStates = {};
        _medNames = {};
        _stepsByDay = {};
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
    final weekLogs = await widget.store.habitLogsForRange(pid, startY, endY);
    final doses = await widget.store.listTodaysDoses(pid);
    final medDays = await widget.store.medicationDayStatesLastDays(pid, days: 7);
    final medNames = await widget.store.activeMedicationNames(pid);
    final stepsByDay = <String, int>{};
    final startMs = start.millisecondsSinceEpoch;
    for (final o in widget.store.observations) {
      if (o.profileId != pid) continue;
      if (o.parameterCode.toLowerCase() != 'steps') continue;
      if (o.observedAt.millisecondsSinceEpoch < startMs) continue;
      final y = DateFormat('yyyy-MM-dd').format(o.observedAt);
      final v = int.tryParse(o.valueReported.split('.').first) ??
          o.valueNum?.round() ??
          0;
      if (v > (stepsByDay[y] ?? 0)) stepsByDay[y] = v;
    }
    if (!mounted) return;
    setState(() {
      _habits = habits;
      _done = done;
      _todayLogs = todayLogs;
      _weekLogs = weekLogs;
      _doses = doses;
      _medDayStates = medDays;
      _medNames = medNames;
      _stepsByDay = stepsByDay;
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
    final title = h?['title'] as String? ?? 'Habit';
    if (kind == 'yes_no') {
      if (!done) {
        final ok = await confirmClearHabitLog(
          context: context,
          habitTitle: title,
        );
        if (!mounted || !ok) return;
      }
      await widget.store.setHabitProgress(
        habitId: id,
        profileId: pid,
        loggedOnYmd: _ymd,
        kind: kind,
        done: done,
        loggedByProfileId: pid,
      );
    } else if (!done) {
      final ok = await confirmClearHabitLog(
        context: context,
        habitTitle: title,
      );
      if (!mounted || !ok) return;
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
      final cur = (log?['value'] as num?)?.toDouble();
      final amount = await showHabitAmountLogDialog(
        context: context,
        habitTitle: title,
        kind: kind,
        unitLabel: h?['unit_label'] as String?,
        goalValue: goal,
        currentValue: cur,
      );
      if (!mounted || amount == null) return;
      await widget.store.setHabitProgress(
        habitId: id,
        profileId: pid,
        loggedOnYmd: _ymd,
        kind: kind,
        goalValue: goal,
        value: amount,
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

    final taken = _doses.where((d) => d.logStatus == 'taken').length;
    final habitTotal = _habits.length;
    var habitScore = 0.0;
    for (final h in _habits) {
      final id = h['id'] as String;
      final kind = (h['kind'] as String?) ?? 'yes_no';
      final goal = (h['goal_value'] as num?)?.toDouble();
      final st = habitDayState(
        kind: kind,
        goalValue: goal,
        log: _todayLogs[id],
      );
      if (st == 'done') {
        habitScore += 1;
      } else if (st == 'partial' && goal != null && goal > 0) {
        final v = (_todayLogs[id]?['value'] as num?)?.toDouble() ?? 0;
        habitScore += (v / goal).clamp(0.0, 1.0);
      }
    }
    final habitScoreLabel = habitTotal == 0
        ? 'none yet'
        : '${habitScore.toStringAsFixed(habitScore == habitScore.roundToDouble() ? 0 : 1)} of $habitTotal'
            '${habitScore < habitTotal && habitScore > 0 ? ' partial counts' : ' done today'}';

    final padH = widget.desktop ? DesktopLayout.mainPaddingH : 20.0;
    final padT = widget.desktop ? 8.0 : 16.0;

    final meds = _MedicinesCard(
      doses: _doses,
      taken: taken,
      store: widget.store,
      onChanged: () async {
        widget.onChanged();
        await _load();
      },
      onManage: widget.onOpenMedicines,
      expand: widget.desktop,
    );
    final habits = _HabitsCard(
      habits: _habits,
      done: _done,
      logs: _todayLogs,
      scoreLabel: habitScoreLabel,
      onToggle: _toggleHabit,
      onOpen: _openHabit,
      onAllHabits: widget.onOpenHabits,
      onAdd: promptAdd,
      expand: widget.desktop,
    );
    final family = _FamilyTodayCard(
      store: widget.store,
      onChanged: () async {
        widget.onChanged();
        await _load();
      },
      expand: widget.desktop,
    );
    final medTimes = <String, String>{};
    for (final d in _doses) {
      medTimes.putIfAbsent(d.medicationId, () => d.timeHm);
    }
    final footer = _HealthFooter(store: widget.store, profileName: _profileName);
    final weekGrid = _WeekGrid(
      habits: _habits,
      medDayStates: _medDayStates,
      medNames: _medNames,
      medTimes: medTimes,
      weekLogs: _weekLogs,
      stepsByDay: _stepsByDay,
      stepGoal: _stepGoal,
      todayYmd: _ymd,
      fillWidth: widget.desktop,
      showSectionChrome: widget.desktop,
      footer: widget.desktop ? footer : null,
    );

    Widget mobileHeader() => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: BodylineColors.ink,
                        ),
                  ),
                  Text(
                    '${DateFormat('EEEE, d MMMM').format(DateTime.now())} · $_profileName',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: BodylineColors.inkSubtle,
                        ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: promptAdd,
              style: FilledButton.styleFrom(
                backgroundColor: BodylineColors.ink,
                foregroundColor: BodylineColors.onInk,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New habit'),
            ),
          ],
        );

    late final Widget body;
    if (widget.desktop) {
      body = Padding(
        padding: EdgeInsets.fromLTRB(padH, padT, padH, 24),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 900;
            final weekBlock = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                weekGrid,
                if (!widget.desktop) ...[
                  const SizedBox(height: 16),
                  footer,
                ],
              ],
            );
            if (!wide) {
              return ListView(
                children: [
                  meds,
                  const SizedBox(height: 14),
                  habits,
                  const SizedBox(height: 14),
                  family,
                  const SizedBox(height: 28),
                  weekBlock,
                ],
              );
            }
            // Wide: ~45% today cards / ~55% Last 7 days.
            // Shell freezes "Today"; week title + date header stay fixed.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 45,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: meds),
                      const SizedBox(width: 14),
                      Expanded(child: habits),
                      const SizedBox(width: 14),
                      Expanded(child: family),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  flex: 55,
                  child: weekGrid,
                ),
              ],
            );
          },
        ),
      );
    } else {
      body = SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(padH, padT, padH, 40),
          children: [
            mobileHeader(),
            const SizedBox(height: 16),
            meds,
            const SizedBox(height: 14),
            habits,
            const SizedBox(height: 14),
            family,
            const SizedBox(height: 28),
            Text(
              'Last 7 days',
              style: _TodayChrome.sectionTitle(context),
            ),
            const SizedBox(height: _TodayChrome.sectionGap),
            const _WeekLegend(),
            const SizedBox(height: _TodayChrome.sectionGap),
            weekGrid,
            const SizedBox(height: 16),
            footer,
          ],
        ),
      );
    }

    // Always Scaffold: Home pushes this as a bare route (no Material → yellow
    // underlines + transparent canvas over black). Desktop shell nests fine.
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: body,
    );
  }
}

String _fmtSteps(int n) {
  if (n >= 10000) return '${(n / 1000).toStringAsFixed(1)}k'.replaceAll('.0k', 'k');
  if (n >= 1000) {
    final k = n / 1000;
    return k == k.roundToDouble()
        ? '${k.round()}k'
        : '${k.toStringAsFixed(1)}k';
  }
  return '$n';
}



/// Shared Today chrome — keep Medicines / Habits / Family / Last 7 days aligned.
abstract final class _TodayChrome {
  static const cardPadding = EdgeInsets.fromLTRB(16, 14, 16, 14);
  static const sectionGap = 12.0;

  static TextStyle sectionTitle(BuildContext context) {
    return Theme.of(context).textTheme.titleLarge!.copyWith(
      color: BodylineColors.ink,
      fontWeight: FontWeight.w700,
    );
  }

  static TextStyle rowTitle([Color? color]) => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color ?? BodylineColors.ink,
      );

  static TextStyle rowSubtitle() => TextStyle(
        fontSize: 12,
        color: BodylineColors.inkSubtle,
      );
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.title,
    required this.trailing,
    required this.child,
    this.expand = false,
  });
  final String title;
  final Widget trailing;
  final Widget child;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: _TodayChrome.sectionTitle(context),
          ),
        ),
        trailing,
      ],
    );
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: _TodayChrome.sectionGap),
        if (expand)
          Expanded(child: child)
        else
          child,
      ],
    );
    final padded = Padding(
      padding: _TodayChrome.cardPadding,
      child: column,
    );
    return Material(
      color: BodylineColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        side: BorderSide(color: BodylineColors.border),
      ),
      // Fill the Expanded parent so nested ListViews get a bounded height.
      child: expand ? SizedBox.expand(child: padded) : padded,
    );
  }
}

class _MedicinesCard extends StatelessWidget {
  const _MedicinesCard({
    required this.doses,
    required this.taken,
    required this.store,
    required this.onChanged,
    this.onManage,
    this.expand = false,
  });
  final List<MedicationDoseSlot> doses;
  final int taken;
  final LocalStore store;
  final VoidCallback onChanged;
  final VoidCallback? onManage;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final title = doses.isEmpty
        ? 'Medicines'
        : 'Medicines  $taken of ${doses.length}';
    return _CardShell(
      title: title,
      trailing: TextButton(
        onPressed: onManage,
        child: const Text('Manage'),
      ),
      expand: expand,
      child: doses.isEmpty
          ? Text(
              'No dose times for today. Add schedules under Medicines.',
              style: _TodayChrome.rowSubtitle(),
            )
          : (expand
              ? SingleChildScrollView(
                  child: TodaysDosesPanel(
                    store: store,
                    onChanged: onChanged,
                    compact: true,
                    mode: TodaysDosesMode.detailList,
                  ),
                )
              : TodaysDosesPanel(
                  store: store,
                  onChanged: onChanged,
                  compact: true,
                  mode: TodaysDosesMode.detailList,
                )),
    );
  }
}

class _HabitsCard extends StatelessWidget {
  const _HabitsCard({
    required this.habits,
    required this.done,
    required this.logs,
    required this.scoreLabel,
    required this.onToggle,
    this.onOpen,
    this.onAllHabits,
    this.onAdd,
    this.expand = false,
  });
  final List<Map<String, Object?>> habits;
  final Set<String> done;
  final Map<String, Map<String, Object?>> logs;
  final String scoreLabel;
  final Future<void> Function(String id, bool done) onToggle;
  final Future<void> Function(String id)? onOpen;
  final VoidCallback? onAllHabits;
  final VoidCallback? onAdd;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      shrinkWrap: !expand,
      itemCount: habits.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final h = habits[i];
        return _HabitRow(
          habit: h,
          log: logs[h['id'] as String],
          onToggle: onToggle,
          onOpen: onOpen,
        );
      },
    );
    return _CardShell(
      title: habits.isEmpty ? 'Habits' : 'Habits  $scoreLabel',
      trailing: TextButton(
        onPressed: onAllHabits,
        child: const Text('All habits'),
      ),
      expand: expand,
      child: habits.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No habits yet. Add one to check in daily.',
                  style: _TodayChrome.rowSubtitle(),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: onAdd,
                  child: const Text('New habit'),
                ),
              ],
            )
          : expand
              ? list
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: list,
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
    final v = (log?['value'] as num?)?.toDouble() ?? 0;
    final g = goal ?? 0;
    final u = unit != null && unit.isNotEmpty
        ? ' $unit'
        : (kind == 'duration' ? ' min' : '');
    final progress = (st == 'done')
        ? 1.0
        : (g > 0 ? (v / g).clamp(0.0, 1.0) : 0.0);

    String status;
    if (st == 'done') {
      status = kind == 'yes_no'
          ? 'Done'
          : (g > 0
              ? '${v.toStringAsFixed(0)} of ${g.toStringAsFixed(0)}$u'
              : '${v.toStringAsFixed(0)}$u');
    } else if (st == 'partial') {
      status = g > 0
          ? '${v.toStringAsFixed(0)} of ${g.toStringAsFixed(0)}$u'
          : '${v.toStringAsFixed(0)}$u';
    } else {
      status = kind == 'yes_no'
          ? 'Not yet'
          : (g > 0 ? '0 of ${g.toStringAsFixed(0)}$u' : 'Not logged');
    }

    final actionLabel = kind == 'yes_no'
        ? 'Mark done'
        : (st == 'none' ? 'Log' : 'Update');

    return InkWell(
      onTap: onOpen == null ? null : () => onOpen!(id),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _TodayChrome.rowTitle()),
                  const SizedBox(height: 2),
                  Text(
                    status,
                    style: _TodayChrome.rowSubtitle(),
                  ),
                  if (kind != 'yes_no') ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: BodylineColors.chip,
                        color: BodylineColors.teal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (kind != 'yes_no') ...[
              FilledButton(
                onPressed: () => onToggle(id, true),
                style: FilledButton.styleFrom(
                  backgroundColor: BodylineColors.teal,
                ),
                child: Text(actionLabel),
              ),
              if (st != 'none')
                IconButton(
                  tooltip: 'Clear today’s log',
                  onPressed: () => onToggle(id, false),
                  icon: Icon(
                    Icons.delete_outline,
                    color: BodylineColors.inkSubtle,
                  ),
                ),
            ] else if (st == 'done')
              FilledButton.tonal(
                onPressed: () => onToggle(id, false),
                child: const Text('Undo'),
              )
            else
              OutlinedButton(
                onPressed: () => onToggle(id, true),
                child: Text(actionLabel),
              ),
          ],
        ),
      ),
    );
  }
}

class _FamilyTodayCard extends StatefulWidget {
  const _FamilyTodayCard({
    required this.store,
    required this.onChanged,
    this.expand = false,
  });
  final LocalStore store;
  final VoidCallback onChanged;
  final bool expand;

  @override
  State<_FamilyTodayCard> createState() => _FamilyTodayCardState();
}

class _FamilyTodayCardState extends State<_FamilyTodayCard> {
  final Map<String, int> _pendingMeds = {};
  final Map<String, int> _pendingHabits = {};
  final Map<String, int> _doneAll = {};
  final Map<String, int> _totalAll = {};
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
    final doneAll = <String, int>{};
    final totalAll = <String, int>{};
    final ymd = DateFormat('yyyy-MM-dd').format(DateTime.now());
    for (final p in widget.store.profiles) {
      final doses = await widget.store.listTodaysDoses(p.id);
      final medDone = doses.where((d) => d.logStatus == 'taken').length;
      pendingM[p.id] = doses.where((d) => !d.isDone).length;
      final habits = await widget.store.listHabits(p.id);
      final logs = await widget.store.habitLogsForDay(p.id, ymd);
      var habitDone = 0;
      var open = 0;
      for (final h in habits) {
        final kind = (h['kind'] as String?) ?? 'yes_no';
        final goal = (h['goal_value'] as num?)?.toDouble();
        final st = habitDayState(
          kind: kind,
          goalValue: goal,
          log: logs[h['id'] as String],
        );
        if (st == 'done') {
          habitDone++;
        } else {
          open++;
        }
      }
      pendingH[p.id] = open;
      doneAll[p.id] = medDone + habitDone;
      totalAll[p.id] = doses.length + habits.length;
    }
    if (!mounted) return;
    setState(() {
      _pendingMeds
        ..clear()
        ..addAll(pendingM);
      _pendingHabits
        ..clear()
        ..addAll(pendingH);
      _doneAll
        ..clear()
        ..addAll(doneAll);
      _totalAll
        ..clear()
        ..addAll(totalAll);
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.store.profiles;
    return _CardShell(
      title: 'Family today',
      trailing: Text(
        'Click to log for them',
        style: _TodayChrome.rowSubtitle(),
      ),
      expand: widget.expand,
      child: profiles.isEmpty
          ? Text(
              'No profiles yet.',
              style: _TodayChrome.rowSubtitle(),
            )
          : Builder(
              builder: (context) {
                final shown =
                    widget.expand ? profiles : profiles.take(4).toList();
                final column = Column(
                  children: [
                    for (var i = 0; i < shown.length; i++) ...[
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: BodylineColors.tealTint,
                            child: Text(
                              shown[i].name.isNotEmpty
                                  ? shown[i].name[0].toUpperCase()
                                  : '?',
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
                                  shown[i].name,
                                  style: _TodayChrome.rowTitle(),
                                ),
                                Text(
                                  !_ready
                                      ? '…'
                                      : _statusLine(shown[i].id),
                                  style: _TodayChrome.rowSubtitle(),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            !_ready
                                ? '…'
                                : '${_doneAll[shown[i].id] ?? 0} of ${_totalAll[shown[i].id] ?? 0}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: BodylineColors.inkSubtle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (shown[i].id != widget.store.activeProfileId)
                            TextButton(
                              onPressed: () async {
                                await widget.store.switchProfile(shown[i].id);
                                widget.onChanged();
                              },
                              child: const Text('Log'),
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
                      if (i < shown.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                );
                if (widget.expand) {
                  return SingleChildScrollView(child: column);
                }
                return column;
              },
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

class _WeekLegend extends StatelessWidget {
  const _WeekLegend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color fill, String label, {Color? border, Widget? child}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 12,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(4),
              border:
                  border == null ? null : Border.all(color: border, width: 1.4),
            ),
            child: child,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: BodylineColors.inkSubtle),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        item(
          BodylineColors.teal,
          'Done',
          child: const Icon(Icons.check, size: 10, color: Colors.white),
        ),
        item(
          BodylineColors.teal.withValues(alpha: 0.35),
          'Partly done (shows %)',
        ),
        item(
          BodylineColors.chip,
          'Not done',
          child: Text(
            '–',
            style: TextStyle(
              fontSize: 10,
              height: 1,
              color: BodylineColors.inkSubtle,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        item(
          Colors.white,
          'Today, updates as you log',
          border: BodylineColors.ink,
        ),
        item(BodylineColors.blue, 'Step goal reached'),
      ],
    );
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.habits,
    required this.medDayStates,
    required this.medNames,
    required this.weekLogs,
    required this.stepsByDay,
    required this.stepGoal,
    required this.todayYmd,
    this.medTimes = const {},
    this.fillWidth = false,
    this.showSectionChrome = false,
    this.footer,
  });

  final List<Map<String, Object?>> habits;
  final Map<String, Map<String, String>> medDayStates;
  final Map<String, String> medNames;
  final Map<String, String> medTimes;
  final Map<String, Map<String, Map<String, Object?>>> weekLogs;
  final Map<String, int> stepsByDay;
  final int stepGoal;
  final String todayYmd;
  final bool fillWidth;
  final bool showSectionChrome;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) {
      return DateTime.now().subtract(Duration(days: 6 - i));
    });

    if (medDayStates.isEmpty && habits.isEmpty && stepsByDay.isEmpty) {
      return Text(
        'Add medicines, habits, or steps to see a week grid here.',
        style: _TodayChrome.rowSubtitle(),
      );
    }

    Widget headerCell(DateTime d, {required bool flex}) {
      final ymd = DateFormat('yyyy-MM-dd').format(d);
      final isToday = ymd == todayYmd;
      final label = Text(
        isToday
            ? 'Today ${DateFormat('d MMM').format(d)}'
            : DateFormat('E d MMM').format(d),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          height: 1.15,
          fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
          color: isToday ? BodylineColors.teal : BodylineColors.inkSubtle,
        ),
      );
      if (flex) {
        return Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: label,
          ),
        );
      }
      return SizedBox(width: 56, child: label);
    }

    final dateHeader = Row(
      children: [
        _labelSlot(child: const SizedBox.shrink()),
        for (final d in days) headerCell(d, flex: fillWidth),
        _weekSummarySlot(
          child: Text(
            'This week',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: BodylineColors.inkSubtle,
            ),
          ),
        ),
      ],
    );

    final rows = <Widget>[
      for (final mid in medDayStates.keys) ...[
        _gridRow(
          icon: Icons.medication_outlined,
          iconTint: const Color(0xFFE8E0F5),
          iconColor: const Color(0xFF6B4F8A),
          title: medNames[mid] ?? 'Medicine',
          subtitle: medTimes[mid] == null
              ? 'Medicine'
              : 'Medicine · ${medTimes[mid]}',
          days: days,
          todayYmd: todayYmd,
          stateFor: (ymd) => medDayStates[mid]?[ymd] ?? 'none',
          labelFor: (_, __) => null,
        ),
        const SizedBox(height: 8),
      ],
      for (final h in habits) ...[
        _gridRow(
          icon: _habitIconFor(h['title'] as String? ?? ''),
          iconTint: BodylineColors.selectedWash,
          iconColor: BodylineColors.tealDark,
          title: h['title'] as String? ?? 'Habit',
          subtitle: () {
            final kind = (h['kind'] as String?) ?? 'yes_no';
            final goal = (h['goal_value'] as num?)?.toDouble();
            if (kind != 'yes_no' && goal != null && goal > 0) {
              return 'Habit · your goal';
            }
            return 'Habit';
          }(),
          days: days,
          todayYmd: todayYmd,
          stateFor: (ymd) {
            final id = h['id'] as String;
            final kind = (h['kind'] as String?) ?? 'yes_no';
            final goal = (h['goal_value'] as num?)?.toDouble();
            return habitDayState(
              kind: kind,
              goalValue: goal,
              log: weekLogs[id]?[ymd],
            );
          },
          labelFor: (ymd, st) {
            if (st != 'partial') return null;
            final id = h['id'] as String;
            final goal = (h['goal_value'] as num?)?.toDouble() ?? 0;
            final v = (weekLogs[id]?[ymd]?['value'] as num?)?.toDouble() ?? 0;
            if (goal <= 0) return null;
            final pct = ((v / goal) * 100).clamp(0, 100).round();
            return '$pct%';
          },
        ),
        const SizedBox(height: 8),
      ],
      if (medDayStates.isNotEmpty || habits.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: CustomPaint(
            painter: _DashedLinePainter(color: BodylineColors.border),
            child: const SizedBox(width: double.infinity, height: 1),
          ),
        ),
      _stepsRow(days),
    ];

    final chrome = showSectionChrome
        ? Padding(
            padding: const EdgeInsets.only(bottom: _TodayChrome.sectionGap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last 7 days',
                  style: _TodayChrome.sectionTitle(context),
                ),
                const SizedBox(width: 16),
                const Expanded(child: _WeekLegend()),
              ],
            ),
          )
        : const SizedBox.shrink();

    if (!fillWidth) {
      return Material(
        color: BodylineColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BodylineRadii.card),
          side: BorderSide(color: BodylineColors.border),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: _TodayChrome.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              dateHeader,
              const SizedBox(height: 8),
              ...rows,
            ],
          ),
        ),
      );
    }

    return Material(
      color: BodylineColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        side: BorderSide(color: BodylineColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: _TodayChrome.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            chrome,
            dateHeader,
            const SizedBox(height: _TodayChrome.sectionGap),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                ),
              ),
            ),
            if (footer != null) ...[
              const SizedBox(height: _TodayChrome.sectionGap),
              Divider(height: 1, color: BodylineColors.border),
              const SizedBox(height: _TodayChrome.sectionGap),
              footer!,
            ],
          ],
        ),
      ),
    );
  }

  static IconData _habitIconFor(String title) {
    final t = title.toLowerCase();
    if (t.contains('walk') || t.contains('run') || t.contains('step')) {
      return Icons.directions_walk_outlined;
    }
    if (t.contains('water') || t.contains('glass') || t.contains('hydrat')) {
      return Icons.water_drop_outlined;
    }
    if (t.contains('sugar') || t.contains('sweet') || t.contains('no ')) {
      return Icons.block;
    }
    if (t.contains('sleep') || t.contains('bed')) {
      return Icons.bedtime_outlined;
    }
    return Icons.check_circle_outline;
  }

  Widget _labelSlot({required Widget child}) {
    if (fillWidth) {
      return Expanded(
        flex: 5,
        child: Align(alignment: Alignment.centerLeft, child: child),
      );
    }
    return SizedBox(width: 180, child: child);
  }

  Widget _weekSummarySlot({required Widget child}) {
    if (fillWidth) {
      return Expanded(
        flex: 2,
        child: Align(alignment: Alignment.centerRight, child: child),
      );
    }
    return SizedBox(width: 64, child: child);
  }

  Widget _stepsRow(List<DateTime> days) {
    var met = 0;
    for (final d in days) {
      final ymd = DateFormat('yyyy-MM-dd').format(d);
      if ((stepsByDay[ymd] ?? 0) >= stepGoal) met++;
    }
    return _gridRow(
      icon: Icons.directions_walk_outlined,
      iconTint: BodylineColors.blueTint,
      iconColor: BodylineColors.blue,
      title: 'Steps',
      subtitle: 'Your goal ${_fmtSteps(stepGoal)} · from phone',
      days: days,
      todayYmd: todayYmd,
      stateFor: (ymd) {
        final n = stepsByDay[ymd] ?? 0;
        if (n <= 0) return 'none';
        if (n >= stepGoal) return 'steps_met';
        return 'steps_partial';
      },
      labelFor: (ymd, st) {
        final n = stepsByDay[ymd] ?? 0;
        if (n <= 0) return null;
        return _fmtSteps(n);
      },
      weekCountOverride: met,
    );
  }

  Widget _gridRow({
    required IconData icon,
    required Color iconTint,
    required Color iconColor,
    required String title,
    required String subtitle,
    required List<DateTime> days,
    required String todayYmd,
    required String Function(String ymd) stateFor,
    required String? Function(String ymd, String state) labelFor,
    int? weekCountOverride,
  }) {
    final doneCount = weekCountOverride ??
        days.where((d) {
          final st = stateFor(DateFormat('yyyy-MM-dd').format(d));
          return st == 'done' || st == 'partial';
        }).length;

    return Row(
      children: [
        _labelSlot(
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _TodayChrome.rowTitle(),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _TodayChrome.rowSubtitle(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final d in days)
          _daySlot(
            child: Builder(
              builder: (_) {
                final ymd = DateFormat('yyyy-MM-dd').format(d);
                final st = stateFor(ymd);
                return _DayCell(
                  state: st,
                  isToday: ymd == todayYmd,
                  label: labelFor(ymd, st),
                );
              },
            ),
          ),
        _weekSummarySlot(
          child: Text(
            '$doneCount / 7',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _daySlot({required Widget child}) {
    final cell = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: SizedBox(
        height: 30,
        width: fillWidth ? double.infinity : 56,
        child: child,
      ),
    );
    if (fillWidth) return Expanded(flex: 2, child: cell);
    return SizedBox(width: 62, child: cell);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.state,
    required this.isToday,
    this.label,
  });
  final String state;
  final bool isToday;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final sealed = state == 'done' || state == 'steps_met';
    Color fill;
    var showCheck = false;
    var showDash = false;
    Color? labelColor;

    switch (state) {
      case 'done':
        fill = BodylineColors.teal;
        showCheck = true;
        break;
      case 'partial':
        fill = BodylineColors.teal.withValues(alpha: 0.28);
        labelColor = BodylineColors.tealDark;
        break;
      case 'steps_met':
        fill = BodylineColors.blue;
        labelColor = Colors.white;
        break;
      case 'steps_partial':
        fill = BodylineColors.blueTint;
        labelColor = BodylineColors.blueText;
        break;
      default:
        fill = BodylineColors.chip;
        showDash = label == null;
        labelColor = BodylineColors.inkSubtle;
    }

    // Mockup: today column is white + ink border until sealed (done / goal met).
    if (isToday && !sealed) {
      fill = BodylineColors.surface;
      showDash = false;
      if (label != null) {
        labelColor = state.startsWith('steps')
            ? BodylineColors.blueText
            : BodylineColors.tealDark;
      }
    }

    Widget? child;
    if (showCheck) {
      child = const Icon(Icons.check, size: 15, color: Colors.white);
    } else if (showDash) {
      child = Text(
        '–',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: BodylineColors.inkSubtle,
        ),
      );
    } else if (label != null) {
      child = Text(
        label!,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: labelColor ?? BodylineColors.ink,
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(9),
        border: isToday ? Border.all(color: BodylineColors.ink, width: 1.6) : null,
      ),
      child: child,
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}


class _HealthFooter extends StatelessWidget {
  const _HealthFooter({required this.store, required this.profileName});
  final LocalStore store;
  final String profileName;

  ObservationRecord? _latest(String pid, String code) {
    return store.observations
        .where((o) =>
            o.profileId == pid &&
            o.parameterCode.toLowerCase() == code.toLowerCase())
        .fold<ObservationRecord?>(null, (best, o) {
      if (best == null || o.observedAt.isAfter(best.observedAt)) return o;
      return best;
    });
  }

  String? _sleepLabel(ObservationRecord? o) {
    if (o == null) return null;
    final hours = double.tryParse(o.valueReported) ?? o.valueNum;
    if (hours == null) return 'Sleep ${o.valueReported} ${o.unitReported}';
    final totalMin = (hours * 60).round();
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (m == 0) return 'Sleep ${h} h';
    return 'Sleep $h h ${m.toString().padLeft(2, '0')} m';
  }

  @override
  Widget build(BuildContext context) {
    final pid = store.activeProfileId;
    final bits = <String>[];
    if (pid != null) {
      final sleep = _sleepLabel(_latest(pid, 'sleep_hrs'));
      if (sleep != null) bits.add(sleep);
      final weight = _latest(pid, 'weight');
      if (weight != null) {
        bits.add('Weight ${weight.valueReported} ${weight.unitReported}');
      }
      final sys = _latest(pid, 'bp_sys');
      final dia = _latest(pid, 'bp_dia');
      if (sys != null && dia != null) {
        bits.add('BP ${sys.valueReported}/${dia.valueReported}');
      } else if (sys != null) {
        bits.add('BP ${sys.valueReported}');
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: bits.isEmpty
              ? Text(
                  'Also today: sync sleep, weight, or BP from Health Connect or add them manually.',
                  style: TextStyle(
                    fontSize: 13,
                    color: BodylineColors.inkSubtle,
                    height: 1.35,
                  ),
                )
              : Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 13,
                      color: BodylineColors.inkSubtle,
                      height: 1.35,
                    ),
                    children: [
                      const TextSpan(
                        text: 'Also today, synced from your phone: ',
                      ),
                      TextSpan(
                        text: bits.join(' · '),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: BodylineColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HealthConnectScreen(store: store),
              ),
            );
          },
          style: TextButton.styleFrom(
            foregroundColor: BodylineColors.teal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text('Health data →'),
        ),
      ],
    );
  }
}
