import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/habits_notes_store.dart';
import '../../data/local_store.dart';
import '../../theme/tokens.dart';

/// Add / edit habit dialog fields matching daily-health mockups (non-med templates).
Future<bool> showHabitEditor({
  required BuildContext context,
  required LocalStore store,
  Map<String, Object?>? existing,
  String? forceProfileId,
}) async {
  final profiles = store.profiles;
  if (profiles.isEmpty) return false;

  var profileId = forceProfileId ??
      existing?['profile_id'] as String? ??
      store.activeProfileId ??
      profiles.first.id;
  final titleCtrl = TextEditingController(
    text: existing?['title'] as String? ?? '',
  );
  var kind = (existing?['kind'] as String?) ?? 'yes_no';
  final goalCtrl = TextEditingController(
    text: existing?['goal_value'] != null
        ? '${(existing!['goal_value'] as num).toString().replaceAll(RegExp(r'\.0$'), '')}'
        : '',
  );
  final unitCtrl = TextEditingController(
    text: existing?['unit_label'] as String? ?? '',
  );
  var days = ((existing?['days_mask'] as String?) ?? '1111111')
      .padRight(7, '1')
      .substring(0, 7)
      .split('');
  var reminder = ((existing?['reminder_enabled'] as int?) ?? 0) == 1;
  final reminderCtrl = TextEditingController(
    text: existing?['reminder_hm'] as String? ?? '08:00',
  );
  final chartsCtrl = TextEditingController(
    text: habitChartCodes(existing ?? {}).join(', '),
  );
  String? templateKey = existing?['template_key'] as String?;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        void applyTemplate(Map<String, String> t) {
          setLocal(() {
            templateKey = t['key'];
            titleCtrl.text = t['title'] ?? '';
            kind = t['kind'] ?? 'yes_no';
            goalCtrl.text = t['goal'] ?? '';
            unitCtrl.text = t['unit'] ?? '';
          });
        }

        return AlertDialog(
          title: Text(existing == null ? 'New habit' : 'Edit habit'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Templates',
                    style: TextStyle(
                      fontSize: 12,
                      color: BodylineColors.inkSubtle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in habitTemplates)
                        ActionChip(
                          label: Text(t['title']!),
                          onPressed: () => applyTemplate(t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (profiles.length > 1) ...[
                    DropdownButtonFormField<String>(
                      value: profileId,
                      decoration: const InputDecoration(labelText: 'Who it is for'),
                      items: [
                        for (final p in profiles)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: existing != null
                          ? null
                          : (v) => setLocal(() => profileId = v ?? profileId),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Habit'),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Type',
                    style: TextStyle(
                      fontSize: 12,
                      color: BodylineColors.inkSubtle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'yes_no', label: Text('Yes/No')),
                      ButtonSegment(value: 'count', label: Text('Count')),
                      ButtonSegment(value: 'duration', label: Text('Duration')),
                    ],
                    selected: {kind},
                    onSelectionChanged: (s) => setLocal(() => kind = s.first),
                  ),
                  if (kind != 'yes_no') ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: goalCtrl,
                            decoration: InputDecoration(
                              labelText: kind == 'duration' ? 'Goal (minutes)' : 'Goal',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: unitCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Unit (optional)',
                              hintText: 'glasses, min…',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Which days',
                    style: TextStyle(
                      fontSize: 12,
                      color: BodylineColors.inkSubtle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (var i = 0; i < 7; i++)
                        FilterChip(
                          label: Text(['M', 'T', 'W', 'T', 'F', 'S', 'S'][i]),
                          selected: days[i] == '1',
                          onSelected: (v) => setLocal(() => days[i] = v ? '1' : '0'),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reminder'),
                    subtitle: const Text('Off by default'),
                    value: reminder,
                    onChanged: (v) => setLocal(() => reminder = v),
                  ),
                  if (reminder)
                    TextField(
                      controller: reminderCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Time (HH:mm)',
                        hintText: '08:00',
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: chartsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Show on charts (optional)',
                      hintText: 'e.g. HbA1c, glucose',
                      helperText:
                          'Parameter codes, comma-separated. Shown beside trends — not cause and effect.',
                    ),
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
        );
      },
    ),
  );

  if (ok != true || titleCtrl.text.trim().isEmpty) {
    titleCtrl.dispose();
    goalCtrl.dispose();
    unitCtrl.dispose();
    reminderCtrl.dispose();
    chartsCtrl.dispose();
    return false;
  }

  final goal = double.tryParse(goalCtrl.text.trim());
  final mask = days.join();
  final charts = chartsCtrl.text
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final hm = reminder ? reminderCtrl.text.trim() : null;

  if (existing == null) {
    await store.addHabit(
      profileId: profileId,
      title: titleCtrl.text.trim(),
      kind: kind,
      goalValue: kind == 'yes_no' ? null : goal,
      unitLabel: unitCtrl.text.trim().isEmpty ? null : unitCtrl.text.trim(),
      daysMask: mask,
      reminderEnabled: reminder,
      reminderHm: hm,
      templateKey: templateKey,
      chartCodes: charts,
    );
  } else {
    await store.updateHabit(
      id: existing['id']! as String,
      title: titleCtrl.text.trim(),
      kind: kind,
      goalValue: kind == 'yes_no' ? null : goal,
      unitLabel: unitCtrl.text.trim().isEmpty ? null : unitCtrl.text.trim(),
      daysMask: mask,
      reminderEnabled: reminder,
      reminderHm: hm,
      chartCodes: charts,
    );
  }

  titleCtrl.dispose();
  goalCtrl.dispose();
  unitCtrl.dispose();
  reminderCtrl.dispose();
  chartsCtrl.dispose();
  return true;
}
