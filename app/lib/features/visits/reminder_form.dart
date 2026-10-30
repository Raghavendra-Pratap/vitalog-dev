import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../notifications/reminder_notifications.dart';
import '../../theme/tokens.dart';
import '../../widgets/month_year_date_picker.dart';
import '../../desktop.dart';

const _recurPresets = <({String? rrule, String label})>[
  (rrule: null, label: 'Once'),
  (rrule: 'FREQ=WEEKLY', label: 'Weekly'),
  (rrule: 'FREQ=MONTHLY', label: 'Monthly'),
  (rrule: 'FREQ=MONTHLY;INTERVAL=3', label: 'Every 3 months'),
  (rrule: 'FREQ=MONTHLY;INTERVAL=6', label: 'Every 6 months'),
  (rrule: 'FREQ=YEARLY', label: 'Yearly'),
];

DateTime _withTime(DateTime day, TimeOfDay tod) =>
    DateTime(day.year, day.month, day.day, tod.hour, tod.minute);

/// Shared add-reminder dialog. Returns the saved row, or null if cancelled.
Future<ReminderRecord?> showAddReminderDialog(
  BuildContext context, {
  required LocalStore store,
  String? initialTitle,
  String? targetCode,
  String kind = 'custom',
  DateTime? initialDue,
  String? initialRrule,
}) async {
  final pid = store.activeProfileId;
  if (pid == null) return null;

  final title = TextEditingController(text: initialTitle ?? '');
  final notesCtrl = TextEditingController();
  // Default 09:00 so date-only pickers don't silently become midnight.
  final seed = initialDue ?? DateTime.now().add(const Duration(days: 30));
  DateTime due = (initialDue != null &&
          (initialDue.hour != 0 || initialDue.minute != 0))
      ? initialDue
      : DateTime(seed.year, seed.month, seed.day, 9, 0);
  String? rrule = initialRrule;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Add reminder'),
        titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
        contentPadding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 12, 28, 20),
        insetPadding: bodylineDialogInset(ctx),
        content: SizedBox(
          width: bodylineDialogWidth(ctx, 400),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: title,
                autofocus: (initialTitle ?? '').trim().isEmpty,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Due: ${DateFormat('d MMM yyyy').format(due)}'),
                trailing: const Icon(Icons.calendar_today_outlined, size: 18),
                onTap: () async {
                  final d = await pickBodylineDate(
                    ctx,
                    initialDate: due,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (d != null) {
                    setLocal(
                      () => due = _withTime(
                        d,
                        TimeOfDay(hour: due.hour, minute: due.minute),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Time: ${DateFormat('h:mm a').format(due)}',
                ),
                trailing: const Icon(Icons.schedule_outlined, size: 18),
                onTap: () async {
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay(hour: due.hour, minute: due.minute),
                    helpText: 'Alert time',
                  );
                  if (t != null) {
                    setLocal(() => due = _withTime(due, t));
                  }
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Repeat',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: BodylineColors.inkSubtle,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _recurPresets)
                    ChoiceChip(
                      label: Text(p.label),
                      selected: rrule == p.rrule,
                      onSelected: (_) => setLocal(() => rrule = p.rrule),
                    ),
                ],
              ),
            ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  if (ok != true || title.text.trim().isEmpty) {
    title.dispose();
    notesCtrl.dispose();
    return null;
  }

  final rem = await store.addReminder(
    profileId: pid,
    title: title.text.trim(),
    dueAt: due,
    kind: kind,
    targetCode: targetCode,
    rrule: rrule,
    notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
  );
  title.dispose();
  notesCtrl.dispose();

  final allowed = await ReminderNotifications.instance.ensurePermission();
  await ReminderNotifications.instance.scheduleReminder(rem);

  if (context.mounted) {
    final recur = ReminderRecord.labelForRrule(rrule);
    final when = DateFormat('d MMM yyyy · h:mm a').format(due);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          allowed
              ? (recur == null
                  ? 'Reminder saved. Alert at $when.'
                  : 'Reminder saved ($recur). Next alert $when.')
              : 'Reminder saved on this device. Enable notifications in system settings to get alerts.',
        ),
      ),
    );
  }
  return rem;
}
