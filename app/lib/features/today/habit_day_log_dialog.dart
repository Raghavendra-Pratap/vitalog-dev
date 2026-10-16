import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/habits_notes_store.dart';
import '../../data/local_store.dart';
import '../../desktop.dart';
import '../../theme/tokens.dart';
import '../../widgets/bodyline_dialog.dart';
import 'habit_amount_log_dialog.dart';

String _fmtAmount(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Day log sheet: list entry rows for [ymd], add / edit / delete each one.
Future<bool> showHabitDayLogDialog({
  required BuildContext context,
  required LocalStore store,
  required Map<String, Object?> habit,
  required String loggedOnYmd,
  VoidCallback? onChanged,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: BodylineColors.ink.withValues(alpha: 0.35),
    builder: (ctx) => _HabitDayLogDialog(
      store: store,
      habit: habit,
      loggedOnYmd: loggedOnYmd,
      onChanged: onChanged,
    ),
  );
  // Barrier dismiss returns null — still report dirty if callback already fired.
  return changed == true;
}

class _HabitDayLogDialog extends StatefulWidget {
  const _HabitDayLogDialog({
    required this.store,
    required this.habit,
    required this.loggedOnYmd,
    this.onChanged,
  });

  final LocalStore store;
  final Map<String, Object?> habit;
  final String loggedOnYmd;
  final VoidCallback? onChanged;

  @override
  State<_HabitDayLogDialog> createState() => _HabitDayLogDialogState();
}

class _HabitDayLogDialogState extends State<_HabitDayLogDialog> {
  List<Map<String, Object?>> _entries = [];
  Map<String, Object?>? _dayNote;
  var _loading = true;
  var _dirty = false;

  String get _habitId => widget.habit['id']! as String;
  String get _kind => (widget.habit['kind'] as String?) ?? 'yes_no';
  double? get _goal => (widget.habit['goal_value'] as num?)?.toDouble();
  String? get _unitLabel => widget.habit['unit_label'] as String?;
  String get _title => widget.habit['title'] as String? ?? 'Habit';

  String get _unitSuffix =>
      habitAmountUnitSuffix(kind: _kind, unitLabel: _unitLabel);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rows = await widget.store.listHabitLogEntries(
      habitId: _habitId,
      loggedOnYmd: widget.loggedOnYmd,
    );
    final note = await widget.store.habitDayNote(
      habitId: _habitId,
      ymd: widget.loggedOnYmd,
    );
    if (!mounted) return;
    setState(() {
      _entries = rows;
      _dayNote = note;
      _loading = false;
    });
  }

  void _markDirty() {
    _dirty = true;
    widget.onChanged?.call();
  }

  double get _total {
    var s = 0.0;
    for (final e in _entries) {
      s += (e['value'] as num?)?.toDouble() ?? 0;
    }
    return s;
  }

  Future<double?> _promptAmount({
    required String title,
    double? initial,
  }) async {
    final unit = _unitSuffix.trim();
    final ctrl = TextEditingController(
      text: initial == null ? '' : _fmtAmount(initial),
    );
    final result = await showBodylineDialog<double>(
      context: context,
      title: title,
      subtitle: _goal != null && _goal! > 0
          ? (unit.isEmpty
              ? 'Goal: ${_fmtAmount(_goal!)}'
              : 'Goal: ${_fmtAmount(_goal!)} $unit')
          : null,
      showLockup: false,
      maxWidth: 320,
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        decoration: InputDecoration(
          labelText: unit.isEmpty ? 'Amount' : 'Amount ($unit)',
          hintText: _kind == 'duration' ? 'e.g. 20' : 'e.g. 3000',
        ),
      ),
      actionsBuilder: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          style: TextButton.styleFrom(foregroundColor: BodylineColors.tealDark),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(ctrl.text.trim());
            if (v == null || v < 0) return;
            Navigator.pop(ctx, v);
          },
          style: FilledButton.styleFrom(
            backgroundColor: BodylineColors.ink,
            foregroundColor: BodylineColors.onInk,
            shape: const StadiumBorder(),
          ),
          child: const Text(
            'Save',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _addEntry() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;

    if (_kind == 'yes_no') {
      await widget.store.addHabitLogEntry(
        habitId: _habitId,
        profileId: pid,
        loggedOnYmd: widget.loggedOnYmd,
        kind: _kind,
        done: true,
        loggedByProfileId: pid,
      );
      _markDirty();
      await _reload();
      return;
    }

    final amount = await _promptAmount(title: 'Add log');
    if (!mounted || amount == null) return;
    await widget.store.addHabitLogEntry(
      habitId: _habitId,
      profileId: pid,
      loggedOnYmd: widget.loggedOnYmd,
      kind: _kind,
      goalValue: _goal,
      value: amount,
      loggedByProfileId: pid,
    );
    _markDirty();
    await _reload();
  }

  Future<void> _editEntry(Map<String, Object?> row) async {
    final id = row['id']! as String;
    if (_kind == 'yes_no') {
      final done = (row['done'] as int? ?? 0) == 1;
      await widget.store.updateHabitLogEntry(
        id: id,
        kind: _kind,
        done: !done,
      );
      _markDirty();
      await _reload();
      return;
    }
    final cur = (row['value'] as num?)?.toDouble() ?? 0;
    final amount = await _promptAmount(title: 'Edit log', initial: cur);
    if (!mounted || amount == null) return;
    await widget.store.updateHabitLogEntry(
      id: id,
      kind: _kind,
      goalValue: _goal,
      value: amount,
    );
    _markDirty();
    await _reload();
  }

  Future<void> _deleteEntry(Map<String, Object?> row) async {
    final ok = await showBodylineDialog<bool>(
      context: context,
      title: 'Delete this log?',
      subtitle: _title,
      showLockup: false,
      maxWidth: 320,
      content: Text(
        'Removes this entry for the day. Other entries stay.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      actionsBuilder: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: BodylineColors.tealDark),
          child: const Text(
            'Keep',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: BodylineColors.danger,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
          ),
          child: const Text(
            'Delete',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
    if (!mounted || ok != true) return;
    await widget.store.softDeleteHabitLogEntry(row['id']! as String);
    _markDirty();
    await _reload();
  }


  Future<void> _editDayNote() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;
    final ctrl = TextEditingController(
      text: (_dayNote?['body'] as String?) ?? '',
    );
    final result = await showBodylineDialog<String?>(
      context: context,
      title: _dayNote == null ? 'Note for this day' : 'Edit day note',
      subtitle: _title,
      showLockup: false,
      maxWidth: 400,
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 5,
        minLines: 3,
        decoration: const InputDecoration(
          hintText: 'e.g. took a break, long walk after travel…',
          alignLabelWithHint: true,
        ),
      ),
      actionsBuilder: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          style: TextButton.styleFrom(foregroundColor: BodylineColors.tealDark),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          style: FilledButton.styleFrom(
            backgroundColor: BodylineColors.ink,
            foregroundColor: BodylineColors.onInk,
            shape: const StadiumBorder(),
          ),
          child: const Text(
            'Save',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
    ctrl.dispose();
    if (!mounted || result == null) return;
    await widget.store.upsertHabitDayNote(
      profileId: pid,
      habitId: _habitId,
      habitTitle: _title,
      ymd: widget.loggedOnYmd,
      body: result,
      chartCodes: habitChartCodes(widget.habit),
    );
    _markDirty();
    await _reload();
  }

  Future<void> _clearDayNote() async {
    final pid = widget.store.activeProfileId;
    if (pid == null || _dayNote == null) return;
    final ok = await showBodylineDialog<bool>(
      context: context,
      title: 'Remove day note?',
      subtitle: _title,
      showLockup: false,
      maxWidth: 320,
      content: Text(
        'Removes this note from the habit and from Notes.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      actionsBuilder: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: BodylineColors.tealDark),
          child: const Text(
            'Keep',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: BodylineColors.danger,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
          ),
          child: const Text(
            'Remove',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
    if (!mounted || ok != true) return;
    await widget.store.upsertHabitDayNote(
      profileId: pid,
      habitId: _habitId,
      habitTitle: _title,
      ymd: widget.loggedOnYmd,
      body: '',
    );
    _markDirty();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final day = DateTime.tryParse(widget.loggedOnYmd);
    final dateLabel = day == null
        ? widget.loggedOnYmd
        : DateFormat('EEEE, d MMMM yyyy').format(day);
    final unit = _unitSuffix.trim();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_dirty);
      },
      child: Dialog(
      backgroundColor: BodylineColors.surface,
      elevation: 0,
      insetPadding: bodylineDialogInset(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BodylineRadii.sheet),
        side: BorderSide(color: BodylineColors.border),
      ),
      child: SizedBox(
        width: bodylineDialogWidth(context, 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                dateLabel,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (_kind != 'yes_no' && _entries.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  unit.isEmpty
                      ? 'Total: ${_fmtAmount(_total)}'
                      : 'Total: ${_fmtAmount(_total)} $unit',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: BodylineColors.tealDark,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No logs for this day yet.',
                    style: TextStyle(color: BodylineColors.inkSubtle),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final row = _entries[i];
                      final label = _kind == 'yes_no'
                          ? (((row['done'] as int? ?? 0) == 1)
                              ? 'Done'
                              : 'Not done')
                          : () {
                              final v =
                                  (row['value'] as num?)?.toDouble() ?? 0;
                              return unit.isEmpty
                                  ? _fmtAmount(v)
                                  : '${_fmtAmount(v)} $unit';
                            }();
                      return Material(
                        color: BodylineColors.selectedWash,
                        borderRadius:
                            BorderRadius.circular(BodylineRadii.card),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _editEntry(row),
                                icon: Icon(
                                  Icons.edit_outlined,
                                  size: 20,
                                  color: BodylineColors.inkSubtle,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _deleteEntry(row),
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                  color: BodylineColors.inkSubtle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (!_loading) ...[
                const SizedBox(height: 16),
                Text(
                  'Note for this day',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: BodylineColors.inkSubtle,
                  ),
                ),
                const SizedBox(height: 8),
                if (_dayNote == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _editDayNote,
                      style: TextButton.styleFrom(
                        foregroundColor: BodylineColors.tealDark,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
                      label: const Text(
                        'Add note',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                else
                  Material(
                    color: BodylineColors.selectedWash,
                    borderRadius: BorderRadius.circular(BodylineRadii.card),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              (_dayNote!['body'] as String?) ?? '',
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.35,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit note',
                            visualDensity: VisualDensity.compact,
                            onPressed: _editDayNote,
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: BodylineColors.inkSubtle,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove note',
                            visualDensity: VisualDensity.compact,
                            onPressed: _clearDayNote,
                            icon: Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: BodylineColors.inkSubtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, _dirty),
                    style: TextButton.styleFrom(
                      foregroundColor: BodylineColors.tealDark,
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _addEntry,
                    style: FilledButton.styleFrom(
                      backgroundColor: BodylineColors.teal,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      _kind == 'yes_no' ? 'Log done' : 'Add log',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
