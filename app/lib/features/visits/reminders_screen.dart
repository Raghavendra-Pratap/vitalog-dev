import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../desktop.dart';
import '../../notifications/reminder_notifications.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../medicines/dose_wait_controller.dart';
import '../medicines/dose_wait_screen.dart';
import '../medicines/todays_doses_panel.dart';
import 'reminder_form.dart';

enum _RightPane { timer, stopwatch, reminder, doses }

/// Reminders hub: master list + timer/stopwatch detail (desktop 2-col).
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({
    super.key,
    required this.store,
    required this.onChanged,
    this.embedded = false,
  });

  final LocalStore store;
  final VoidCallback onChanged;
  final bool embedded;

  @override
  RemindersScreenState createState() => RemindersScreenState();
}

class RemindersScreenState extends State<RemindersScreen> {
  List<ReminderRecord> _reminders = [];
  var _loading = true;
  var _loadGen = 0;
  bool? _alertsOn;
  _RightPane _pane = _RightPane.doses;
  String? _selectedReminderId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RemindersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  Future<void> promptAdd() => _add();

  /// Select Timer or Stopwatch detail pane (desktop header chip).
  void openTool(DoseWaitMode mode) {
    setState(() {
      _pane = mode == DoseWaitMode.countdown
          ? _RightPane.timer
          : _RightPane.stopwatch;
      _selectedReminderId = null;
    });
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _reminders = [];
        _loading = false;
      });
      return;
    }
    // Mirror visit follow-up dates into reminders (covers edit/legacy gaps).
    final ensured = await widget.store.ensureVisitFollowUpReminders(pid);
    for (final rem in ensured) {
      await ReminderNotifications.instance.scheduleReminder(rem);
    }
    final rolled = await widget.store.rollForwardRecurring(pid);
    final alerts = await ReminderNotifications.instance.notificationsEnabled();
    await ReminderNotifications.instance.rescheduleAll(rolled);
    if (!mounted || gen != _loadGen) return;
    setState(() {
      _reminders = rolled;
      _alertsOn = alerts;
      _loading = false;
      if (_selectedReminderId != null &&
          !rolled.any((r) => r.id == _selectedReminderId)) {
        _selectedReminderId = null;
        if (_pane == _RightPane.reminder) _pane = _RightPane.timer;
      }
    });
  }

  Future<void> _add() async {
    final rem = await showAddReminderDialog(context, store: widget.store);
    if (rem == null) return;
    widget.onChanged();
    await _load();
    if (!mounted) return;
    setState(() {
      _selectedReminderId = rem.id;
      _pane = _RightPane.reminder;
    });
  }

  Future<void> _enableAlerts() async {
    await ReminderNotifications.instance.ensurePermission();
    final alerts = await ReminderNotifications.instance.notificationsEnabled();
    if (!mounted) return;
    setState(() => _alertsOn = alerts);
  }

  Future<void> _complete(ReminderRecord r) async {
    final next = await widget.store.completeReminder(r.id);
    if (next == null) {
      await ReminderNotifications.instance.cancelReminder(r.id);
    } else {
      await ReminderNotifications.instance.scheduleReminder(next);
    }
    widget.onChanged();
    await _load();
  }

  ReminderRecord? get _selected {
    for (final r in _reminders) {
      if (r.id == _selectedReminderId) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final wide = widget.embedded && useWideShell(context);
    if (wide) return _buildDesktop(context);
    return _buildMobile(context);
  }

  Widget _buildDesktop(BuildContext context) {
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
            width: DesktopLayout.testsMasterCol,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toolCard(context),
                const SizedBox(height: 12),
                if (_alertsOn == false) ...[
                  _alertsBanner(context),
                  const SizedBox(height: 12),
                ],
                TodaysDosesPanel(
                  store: widget.store,
                  onChanged: widget.onChanged,
                  mode: TodaysDosesMode.masterCard,
                  selected: _pane == _RightPane.doses,
                  onSelect: () => setState(() {
                    _pane = _RightPane.doses;
                    _selectedReminderId = null;
                  }),
                ),
                const SizedBox(height: 16),
                Text(
                  'Reminders',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Only reminders you create appear here.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: BodylineColors.inkSubtle,
                      ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _reminders.isEmpty
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No reminders yet.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        )
                      : ListView(
                          children: _reminderTiles(context),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(child: _detailPane(context)),
        ],
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: widget.embedded ? null : AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton(
        heroTag: widget.embedded ? 'care-tab-reminders-fab' : 'page-reminders-fab',
        onPressed: _add,
        tooltip: 'Add reminder',
        backgroundColor: BodylineColors.teal,
        foregroundColor: BodylineColors.isDark
            ? const Color(0xFF04201C)
            : Colors.white,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                if (_alertsOn == false) ...[
                  _alertsBanner(context),
                  const SizedBox(height: 12),
                ],
                TodaysDosesPanel(
                  store: widget.store,
                  onChanged: widget.onChanged,
                ),
                const SizedBox(height: 20),
                Text(
                  'Reminders',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                if (_reminders.isEmpty)
                  Text(
                    'No reminders yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: BodylineColors.inkSubtle,
                        ),
                  )
                else
                  ..._reminderTiles(context),
              ],
            ),
          ),
          // Pin Timer / Stopwatch to the bottom of the screen (clear of FAB).
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 88, 12),
              child: _toolCard(context, pushTools: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolCard(BuildContext context, {bool pushTools = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _toolBtn(
              label: 'Timer',
              icon: Icons.hourglass_bottom,
              selected: !pushTools && _pane == _RightPane.timer,
              onTap: () {
                if (pushTools) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DoseWaitScreen(
                        mode: DoseWaitMode.countdown,
                      ),
                    ),
                  );
                  return;
                }
                setState(() {
                  _pane = _RightPane.timer;
                  _selectedReminderId = null;
                });
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _toolBtn(
              label: 'Stopwatch',
              icon: Icons.timer_outlined,
              selected: !pushTools && _pane == _RightPane.stopwatch,
              onTap: () {
                if (pushTools) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DoseWaitScreen(
                        mode: DoseWaitMode.stopwatch,
                      ),
                    ),
                  );
                  return;
                }
                setState(() {
                  _pane = _RightPane.stopwatch;
                  _selectedReminderId = null;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolBtn({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? BodylineColors.selectedWash : BodylineColors.chip,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? BodylineColors.tealDark : BodylineColors.inkMuted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? BodylineColors.tealDark : BodylineColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _alertsBanner(BuildContext context) {
    return Material(
      color: BodylineColors.orangeTint,
      borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.notifications_off_outlined,
                size: 18, color: BodylineColors.orangeText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Alerts are off. Enable notifications for reminder banners.',
                style: TextStyle(
                  color: BodylineColors.orangeText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: _enableAlerts,
              child: Text(
                'Enable',
                style: TextStyle(
                  color: BodylineColors.orangeText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _reminderTiles(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    return [
      for (final r in _reminders) ...[
        _reminderCard(context, r, fmt),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _reminderCard(
    BuildContext context,
    ReminderRecord r,
    DateFormat fmt,
  ) {
    final selected =
        _pane == _RightPane.reminder && r.id == _selectedReminderId;
    final recur = ReminderRecord.labelForRrule(r.rrule);
    return Material(
      color: selected ? BodylineColors.selectedWash : BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        onTap: () => setState(() {
          _selectedReminderId = r.id;
          _pane = _RightPane.reminder;
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
                r.title,
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
                  'Due ${fmt.format(r.dueAt)}',
                  if (recur != null) recur,
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (r.notes != null && r.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  r.notes!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: BodylineColors.inkSubtle,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailPane(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      padding: const EdgeInsets.all(20),
      child: switch (_pane) {
        _RightPane.timer => _timerDetail(context),
        _RightPane.stopwatch => _stopwatchDetail(context),
        _RightPane.reminder => _reminderDetail(context),
        _RightPane.doses => ListView(
            children: [
              TodaysDosesPanel(
                store: widget.store,
                onChanged: widget.onChanged,
                mode: TodaysDosesMode.detailList,
              ),
            ],
          ),
      },
    );
  }

  Widget _timerDetail(BuildContext context) {
    return const DoseTimerView(showTitle: true);
  }

  Widget _stopwatchDetail(BuildContext context) {
    return const DoseStopwatchView(showTitle: true);
  }

  Widget _reminderDetail(BuildContext context) {
    final r = _selected;
    if (r == null) {
      return Center(
        child: Text(
          'Select a reminder, or open Timer / Stopwatch.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final fmt = DateFormat('d MMM yyyy');
    final recur = ReminderRecord.labelForRrule(r.rrule);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          r.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        _detailRow('Due', fmt.format(r.dueAt)),
        _detailRow('Repeat', recur ?? 'Once'),
        if (r.notes != null && r.notes!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Notes',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: BodylineColors.inkSubtle,
                ),
          ),
          const SizedBox(height: 4),
          Text(r.notes!, style: Theme.of(context).textTheme.bodyMedium),
        ],
        const Spacer(),
        FilledButton(
          onPressed: () => _complete(r),
          style: FilledButton.styleFrom(
            backgroundColor: BodylineColors.ink,
            foregroundColor: BodylineColors.onInk,
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text(r.isRecurring ? 'Done this time' : 'Done'),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                color: BodylineColors.inkSubtle,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
