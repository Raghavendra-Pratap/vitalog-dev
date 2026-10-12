import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/habits_notes_store.dart';
import '../../data/local_store.dart';
import '../../theme/tokens.dart';
import 'habit_detail_screen.dart';
import 'habit_editor.dart';

/// All habits for the active profile (Care › Habits).
class HabitsScreen extends StatefulWidget {
  const HabitsScreen({
    super.key,
    required this.store,
    required this.onChanged,
    this.embedded = false,
  });

  final LocalStore store;
  final VoidCallback onChanged;
  final bool embedded;

  @override
  State<HabitsScreen> createState() => HabitsScreenState();
}

class HabitsScreenState extends State<HabitsScreen> {
  List<Map<String, Object?>> _habits = [];
  Map<String, Map<String, Object?>> _logs = {};
  var _loading = true;
  String? _selectedId;

  String get _ymd => DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HabitsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  Future<void> _load() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      if (!mounted) return;
      setState(() {
        _habits = [];
        _logs = {};
        _loading = false;
      });
      return;
    }
    final habits = await widget.store.listHabits(pid);
    final logs = await widget.store.habitLogsForDay(pid, _ymd);
    if (!mounted) return;
    setState(() {
      _habits = habits;
      _logs = logs;
      _loading = false;
      if (_selectedId != null &&
          !habits.any((h) => h['id'] == _selectedId)) {
        _selectedId = habits.isEmpty ? null : habits.first['id'] as String?;
      }
    });
  }

  Future<void> promptAdd() async {
    final ok = await showHabitEditor(context: context, store: widget.store);
    if (ok) {
      widget.onChanged();
      await _load();
    }
  }

  Future<void> _openDetail(String id) async {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide && widget.embedded) {
      setState(() => _selectedId = id);
      return;
    }
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

  Future<void> _quickLog(Map<String, Object?> h) async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;
    final id = h['id']! as String;
    final kind = (h['kind'] as String?) ?? 'yes_no';
    final goal = (h['goal_value'] as num?)?.toDouble();
    final log = _logs[id];
    if (kind == 'yes_no') {
      final done = (log?['done'] as int? ?? 0) == 1;
      await widget.store.setHabitProgress(
        habitId: id,
        profileId: pid,
        loggedOnYmd: _ymd,
        kind: kind,
        done: !done,
        loggedByProfileId: storeActorId(widget.store),
      );
    } else {
      final cur = (log?['value'] as num?)?.toDouble() ?? 0;
      final step = kind == 'duration' ? 5.0 : 1.0;
      final next = cur + step;
      await widget.store.setHabitProgress(
        habitId: id,
        profileId: pid,
        loggedOnYmd: _ymd,
        kind: kind,
        goalValue: goal,
        value: next,
        loggedByProfileId: storeActorId(widget.store),
      );
    }
    widget.onChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900 && widget.embedded;
    final list = _loading
        ? const Center(child: CircularProgressIndicator())
        : _habits.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'No habits yet',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontFamily: 'Fraunces',
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Track daily check-ins on this device — not streaks or advice.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: BodylineColors.inkSubtle),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: promptAdd,
                        icon: const Icon(Icons.add),
                        label: const Text('New habit'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                itemCount: _habits.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final h = _habits[i];
                  final id = h['id'] as String;
                  final title = h['title'] as String? ?? 'Habit';
                  final kind = (h['kind'] as String?) ?? 'yes_no';
                  final goal = (h['goal_value'] as num?)?.toDouble();
                  final log = _logs[id];
                  final st = habitDayState(
                    kind: kind,
                    goalValue: goal,
                    log: log,
                  );
                  final subtitle = switch (st) {
                    'done' => 'Done today',
                    'partial' => _partialLabel(kind, log, goal, h),
                    _ => 'Not yet today',
                  };
                  final selected = wide && id == _selectedId;
                  return Material(
                    color: selected
                        ? BodylineColors.tealTint
                        : BodylineColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(BodylineRadii.cardSmall),
                      side: BorderSide(
                        color: selected
                            ? BodylineColors.teal
                            : BodylineColors.border,
                      ),
                    ),
                    child: ListTile(
                      onTap: () => _openDetail(id),
                      title: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(subtitle),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (st == 'done')
                            FilledButton.tonal(
                              onPressed: () async {
                                final pid = widget.store.activeProfileId;
                                if (pid == null) return;
                                await widget.store.setHabitProgress(
                                  habitId: id,
                                  profileId: pid,
                                  loggedOnYmd: _ymd,
                                  kind: kind,
                                  goalValue: goal,
                                  done: false,
                                  value: 0,
                                  loggedByProfileId: storeActorId(widget.store),
                                );
                                widget.onChanged();
                                await _load();
                              },
                              child: const Text('Undo'),
                            )
                          else
                            FilledButton(
                              onPressed: () => _quickLog(h),
                              style: FilledButton.styleFrom(
                                backgroundColor: BodylineColors.teal,
                              ),
                              child: Text(kind == 'yes_no' ? 'Mark done' : 'Log'),
                            ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () async {
                              await widget.store.softDeleteHabit(id);
                              await _load();
                              widget.onChanged();
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );

    Widget body = list;
    if (wide) {
      final sel = _selectedId;
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 360, child: list),
          const VerticalDivider(width: 1),
          Expanded(
            child: sel == null
                ? Center(
                    child: Text(
                      'Select a habit',
                      style: TextStyle(color: BodylineColors.inkSubtle),
                    ),
                  )
                : HabitDetailScreen(
                    key: ValueKey(sel),
                    store: widget.store,
                    habitId: sel,
                    embedded: true,
                    onChanged: () {
                      widget.onChanged();
                      _load();
                    },
                  ),
          ),
        ],
      );
    }

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(title: const Text('Habits')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: promptAdd,
        icon: const Icon(Icons.add),
        label: const Text('New habit'),
      ),
      body: body,
    );
  }

  String _partialLabel(
    String kind,
    Map<String, Object?>? log,
    double? goal,
    Map<String, Object?> h,
  ) {
    final v = (log?['value'] as num?)?.toDouble() ?? 0;
    final unit = h['unit_label'] as String?;
    final g = goal ?? 0;
    final u = unit != null && unit.isNotEmpty
        ? ' $unit'
        : (kind == 'duration' ? ' min' : '');
    if (g > 0) {
      return '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)} of '
          '${g.toStringAsFixed(g == g.roundToDouble() ? 0 : 1)}$u';
    }
    return '${v.toStringAsFixed(0)}$u today';
  }
}

/// Active profile is the actor when logging for someone else later.
String storeActorId(LocalStore store) =>
    store.activeProfileId ?? '';
