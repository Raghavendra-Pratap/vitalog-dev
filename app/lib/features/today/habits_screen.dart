import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/habits_notes_store.dart';
import '../../data/local_store.dart';
import '../../desktop.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../medicines/dose_wait_header_chip.dart';
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
  /// habitId → ymd → log (last ~90 days) for list progress fractions.
  Map<String, Map<String, Map<String, Object?>>> _rangeLogs = {};
  var _loading = true;
  String? _selectedId;
  final _detailKey = GlobalKey<HabitDetailScreenState>();
  var _notesTick = 0;

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
        _rangeLogs = {};
        _loading = false;
      });
      return;
    }
    final habits = await widget.store.listHabits(pid);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 89));
    final range = await widget.store.habitLogsForRange(
      pid,
      DateFormat('yyyy-MM-dd').format(start),
      _ymd,
    );
    if (!mounted) return;
    setState(() {
      _habits = habits;
      _rangeLogs = range;
      _loading = false;
      if (_selectedId == null && habits.isNotEmpty) {
        _selectedId = habits.first['id'] as String?;
      } else if (_selectedId != null &&
          !habits.any((h) => h['id'] == _selectedId)) {
        _selectedId = habits.isEmpty ? null : habits.first['id'] as String?;
      }
    });
  }

  /// Shell / Today call this so habit stats refresh after a log elsewhere.
  Future<void> reload() => _load();

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

  String? get _profileName {
    final id = widget.store.activeProfileId;
    for (final p in widget.store.profiles) {
      if (p.id == id) return p.name;
    }
    return widget.store.profiles.isEmpty
        ? null
        : widget.store.profiles.first.name;
  }

  ({int done, int scheduled}) _progress30(Map<String, Object?> h) {
    final id = h['id'] as String?;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: 29));
    final s = habitWindowStats(
      habit: h,
      logs: id == null ? const {} : (_rangeLogs[id] ?? const {}),
      start: start,
      end: today,
    );
    return (done: s.done, scheduled: s.scheduled);
  }

  Widget _habitTile(Map<String, Object?> h, {required bool selected}) {
    final id = h['id'] as String;
    final title = h['title'] as String? ?? 'Habit';
    final schedule = habitScheduleLabel(h['days_mask'] as String?);
    final prog = _progress30(h);
    final frac = prog.scheduled == 0
        ? '—'
        : '${prog.done}/${prog.scheduled}';

    return Material(
      color: selected ? BodylineColors.selectedWash : BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.card),
      child: InkWell(
        onTap: () => _openDetail(id),
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BodylineRadii.card),
            border: Border.all(
              color: selected ? BodylineColors.teal : BodylineColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                habitIconFor(h),
                size: 22,
                color: BodylineColors.tealDark,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$schedule · $frac',
                      style: TextStyle(
                        fontSize: 12,
                        color: BodylineColors.inkSubtle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList({required bool wide}) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_habits.isEmpty) {
      return Center(
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
              if (widget.embedded) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: promptAdd,
                  style: FilledButton.styleFrom(
                    backgroundColor: BodylineColors.ink,
                    foregroundColor: BodylineColors.onInk,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('New habit'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _habits.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final h = _habits[i];
        final id = h['id'] as String;
        final selected = wide && id == _selectedId;
        if (wide) {
          return _habitTile(h, selected: selected);
        }
        // Mobile: open detail — log via calendar / Update today.
        final prog = _progress30(h);
        final schedule = habitScheduleLabel(h['days_mask'] as String?);
        final frac = prog.scheduled == 0
            ? '—'
            : '${prog.done}/${prog.scheduled}';
        return Material(
          color: BodylineColors.surface,
          borderRadius: BorderRadius.circular(BodylineRadii.card),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BodylineRadii.card),
              side: BorderSide(color: BodylineColors.border),
            ),
            leading: Icon(habitIconFor(h), color: BodylineColors.tealDark),
            onTap: () => _openDetail(id),
            title: Text(
              h['title'] as String? ?? 'Habit',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('$schedule · $frac'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = widget.embedded && useWideShell(context);
    final list = _buildList(wide: wide);

    Widget body = list;
    if (wide) {
      final sel = _selectedId;
      final selectedHabit = sel == null
          ? null
          : _habits.cast<Map<String, Object?>?>().firstWhere(
                (h) => h?['id'] == sel,
                orElse: () => null,
              );
      final detail = sel == null
          ? Center(
              child: Text(
                _habits.isEmpty
                    ? 'Add a habit from + New habit to get started.'
                    : 'Select a habit',
                style: TextStyle(color: BodylineColors.inkSubtle),
              ),
            )
          : HabitDetailScreen(
              key: _detailKey,
              store: widget.store,
              habitId: sel,
              embedded: true,
              showSettingsInline: false,
              onChanged: () {
                widget.onChanged();
                setState(() => _notesTick++);
                _load();
              },
            );

      final charts = selectedHabit == null
          ? const <String>[]
          : habitChartCodes(selectedHabit);

      body = Padding(
        padding: const EdgeInsets.fromLTRB(
          DesktopLayout.mainPaddingH,
          4,
          DesktopLayout.mainPaddingH,
          DesktopLayout.mainPaddingV,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 280,
              child: list,
            ),
            const SizedBox(width: DesktopLayout.mainGap),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                decoration: BoxDecoration(
                  color: BodylineColors.surface,
                  borderRadius: BorderRadius.circular(BodylineRadii.card),
                  border: Border.all(color: BodylineColors.border),
                ),
                child: detail,
              ),
            ),
            const SizedBox(width: DesktopLayout.mainGap),
            SizedBox(
              width: 260,
              child: selectedHabit == null
                  ? const SizedBox.shrink()
                  : ListView(
                      children: [
                        HabitSettingsCard(
                          habit: selectedHabit,
                          profileName: _profileName,
                          onEdit: () async {
                            final ok = await showHabitEditor(
                              context: context,
                              store: widget.store,
                              existing: selectedHabit,
                            );
                            if (ok) {
                              widget.onChanged();
                              await _load();
                              await _detailKey.currentState?.reload();
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        HabitNotesCard(
                          key: ValueKey('notes-$sel-$_notesTick'),
                          store: widget.store,
                          habit: selectedHabit,
                          onChanged: () {
                            widget.onChanged();
                            setState(() => _notesTick++);
                            _load();
                            _detailKey.currentState?.reload();
                          },
                        ),
                        if (charts.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          HabitTrendsCard(chartCodes: charts),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      );
    }

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(
        title: const Text('Habits'),
        actions: doseWaitActions(),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'page-habits-fab',
        onPressed: promptAdd,
        tooltip: 'New habit',
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: body,
      ),
    );
  }
}

/// Active profile is the actor when logging for someone else later.
String storeActorId(LocalStore store) => store.activeProfileId ?? '';
