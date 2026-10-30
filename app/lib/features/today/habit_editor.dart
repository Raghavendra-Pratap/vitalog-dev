import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/habits_notes_store.dart';
import '../../data/local_store.dart';
import '../../notifications/reminder_notifications.dart';
import '../../theme/tokens.dart';
import '../../widgets/chart_link_picker.dart';

/// Add / edit habit dialog — lifestyle templates only (dosing lives on Medicines).
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
  String? templateKey = existing?['template_key'] as String?;

  // code → display name for suggestions (observations + catalogue).
  final codeToName = <String, String>{};
  for (final o in store.observations) {
    if (o.deleted) continue;
    if (o.profileId != profileId && forceProfileId == null) {
      // Still include active-profile rows primarily; allow all for linking.
    }
    if (o.parameterCode.isNotEmpty) {
      codeToName[o.parameterCode] = o.parameterName.isNotEmpty
          ? o.parameterName
          : o.parameterCode;
    }
  }
  try {
    final panels = await store.catalogPanels();
    for (final panel in panels) {
      for (final p in panel.parameters) {
        codeToName.putIfAbsent(
          p.code,
          () => p.name.isNotEmpty ? p.name : p.code,
        );
      }
    }
  } catch (_) {}

  String labelFor(String code) => codeToName[code] ?? code;

  /// Resolve legacy free-text entries (names) to catalogue codes when possible.
  String? resolveChartToken(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t == kChartCodeAll) return null;
    if (codeToName.containsKey(t)) return t;
    final lower = t.toLowerCase();
    for (final e in codeToName.entries) {
      if (e.key.toLowerCase() == lower || e.value.toLowerCase() == lower) {
        return e.key;
      }
    }
    // Keep unknown token so user data is not silently dropped.
    codeToName.putIfAbsent(t, () => t);
    return t;
  }

  final existingCharts = habitChartCodes(existing ?? {});
  var showOnAllCharts = chartCodesAreAll(existingCharts);
  var selectedCharts = <String>{
    for (final c in existingCharts)
      if (c != kChartCodeAll)
        if (resolveChartToken(c) != null) resolveChartToken(c)!,
  };

  final chartOptions = codeToName.keys.toList()
    ..sort(
      (a, b) => labelFor(a).toLowerCase().compareTo(labelFor(b).toLowerCase()),
    );

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
                  DropdownButtonFormField<String?>(
                    value: habitTemplatesFor('lifestyle')
                            .any((e) => e['key'] == templateKey)
                        ? templateKey
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Template',
                      hintText: 'Custom or pick a starter',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Custom'),
                      ),
                      for (final t in habitTemplatesFor('lifestyle'))
                        DropdownMenuItem<String?>(
                          value: t['key'],
                          child: Text(t['title']!),
                        ),
                    ],
                    onChanged: (key) {
                      if (key == null) {
                        setLocal(() => templateKey = null);
                        return;
                      }
                      final match = habitTemplatesFor('lifestyle')
                          .where((e) => e['key'] == key);
                      if (match.isEmpty) return;
                      applyTemplate(match.first);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (profiles.length > 1) ...[
                    DropdownButtonFormField<String>(
                      value: profileId,
                      decoration:
                          const InputDecoration(labelText: 'Who it is for'),
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
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: WidgetStatePropertyAll(
                        Theme.of(ctx).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    segments: const [
                      ButtonSegment(
                        value: 'yes_no',
                        label: Text('Yes/No', maxLines: 1, softWrap: false),
                      ),
                      ButtonSegment(
                        value: 'count',
                        label: Text('Count', maxLines: 1, softWrap: false),
                      ),
                      ButtonSegment(
                        value: 'duration',
                        label: Text('Duration', maxLines: 1, softWrap: false),
                      ),
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
                              labelText: kind == 'duration'
                                  ? 'Goal (minutes)'
                                  : 'Goal',
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < 7; i++)
                        _DayCircle(
                          label: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                          selected: days[i] == '1',
                          onTap: () => setLocal(
                            () => days[i] = days[i] == '1' ? '0' : '1',
                          ),
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
                  Text(
                    'Show on charts',
                    style: TextStyle(
                      fontSize: 12,
                      color: BodylineColors.inkSubtle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('All charts'),
                    subtitle: const Text(
                      'Pins this habit on every trend — for context, not cause and effect.',
                    ),
                    value: showOnAllCharts,
                    onChanged: (v) => setLocal(() {
                      showOnAllCharts = v;
                      if (v) selectedCharts.clear();
                    }),
                  ),
                  if (!showOnAllCharts) ...[
                    Text(
                      selectedCharts.isEmpty
                          ? 'Search and add a chart'
                          : 'Shows on ${selectedCharts.length} chart${selectedCharts.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: BodylineColors.inkSubtle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ChartLinkPicker(
                      options: chartOptions,
                      selected: selectedCharts,
                      labelFor: labelFor,
                      hintText: 'Search tests to add…',
                      onChanged: (next) => setLocal(() {
                        selectedCharts
                          ..clear()
                          ..addAll(next);
                      }),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Shown beside trends — not cause and effect.',
                      style: TextStyle(
                        fontSize: 11,
                        color: BodylineColors.inkSubtle,
                      ),
                    ),
                  ],
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
    return false;
  }

  final goal = double.tryParse(goalCtrl.text.trim());
  final mask = days.join();
  final charts = showOnAllCharts
      ? const [kChartCodeAll]
      : selectedCharts.toList();
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

  try {
    final all = await store.listAllHabits();
    await ReminderNotifications.instance.ensurePermission();
    await ReminderNotifications.instance.rescheduleAllHabits(all);
  } catch (_) {}

  return true;
}

class _DayCircle extends StatelessWidget {
  const _DayCircle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? BodylineColors.teal : BodylineColors.chip;
    final fg = selected ? BodylineColors.onInk : BodylineColors.inkSubtle;
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
