import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/medical_store.dart';
import '../../data/models.dart';
import '../../desktop.dart';
import '../../theme/tokens.dart';
import '../../widgets/drug_name_field.dart';

enum _CourseMode { ongoing, days, until }
enum _FreqMode { daily, specific, interval }
enum _RestockMode { none, date, fromStock, nextVisit }

class _FollowUpOption {
  const _FollowUpOption({required this.dateYmd, required this.label});
  final String dateYmd;
  final String label;
}

class _DoseRow {
  _DoseRow({String hm = '08:00', String amount = '1'})
      : hm = TextEditingController(text: hm),
        amount = TextEditingController(text: amount);
  final TextEditingController hm;
  final TextEditingController amount;
  void dispose() {
    hm.dispose();
    amount.dispose();
  }
}

String doseUnitForForm(String form) {
  return switch (form) {
    'syrup' => 'ml',
    'drops' => 'drops',
    'tube' => 'applications',
    'injection' => 'doses',
    'inhaler' => 'puffs',
    'capsule' => 'capsules',
    'tablet' => 'tablets',
    _ => 'units',
  };
}

String stockLabelForForm(String form) {
  return switch (form) {
    'syrup' => 'ml left (optional)',
    'drops' => 'Drops left (optional)',
    'capsule' => 'Capsules left (optional)',
    'tablet' => 'Tablets left (optional)',
    _ => 'Stock left (optional)',
  };
}

/// Result: name, kind, strength?, instructions?, pills?, restock?, stockNote?,
/// prescribedAs?, dosageForm?, endDate?, daysMask, intervalDays?, doseUnit, slots.
Future<Map<String, Object?>?> showMedicineEditorDialog({
  required BuildContext context,
  required LocalStore store,
  MedicalItem? initial,
  List<({String dateYmd, String label})> upcomingFollowUps = const [],
}) {
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (ctx) => _MedicineEditorDialog(
      store: store,
      initial: initial,
      upcomingFollowUps: [
        for (final o in upcomingFollowUps)
          _FollowUpOption(dateYmd: o.dateYmd, label: o.label),
      ],
    ),
  );
}

class _MedicineEditorDialog extends StatefulWidget {
  const _MedicineEditorDialog({
    required this.store,
    this.upcomingFollowUps = const [],
    this.initial,
  });

  final LocalStore store;
  final List<_FollowUpOption> upcomingFollowUps;
  final MedicalItem? initial;

  @override
  State<_MedicineEditorDialog> createState() => _MedicineEditorDialogState();
}

class _MedicineEditorDialogState extends State<_MedicineEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _strength;
  late final TextEditingController _instructions;
  late final TextEditingController _pills;
  late final TextEditingController _restock;
  final _lead = TextEditingController(text: '3');
  late final TextEditingController _endDate;
  final _durationDays = TextEditingController();
  final _intervalDays = TextEditingController(text: '2');
  late String _kind;
  var _form = 'tablet';
  var _courseMode = _CourseMode.ongoing;
  var _freqMode = _FreqMode.daily;
  var _daysMask = '1111111';
  var _restockMode = _RestockMode.none;
  String? _visitDateYmd;
  String? _nameError;
  String? _planNote;
  final _rows = <_DoseRow>[_DoseRow()];

  String get _unit => doseUnitForForm(_form);

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.title ?? '');
    _strength = TextEditingController(text: i?.strength ?? '');
    _instructions = TextEditingController(text: i?.instructions ?? '');
    _endDate = TextEditingController(text: i?.endDate ?? '');
    _form = i?.dosageForm ?? 'tablet';
    _pills = TextEditingController(
      text: i?.pillCount == null ? '' : '${i!.pillCount}',
    );
    _restock = TextEditingController(text: i?.restockOn ?? '');
    _kind = () {
      final k = i?.kind;
      if (k != null && kMedicationKinds.contains(k)) return k;
      return 'allopathic';
    }();
    if (i?.restockOn != null && i!.restockOn!.isNotEmpty) {
      _restockMode = _RestockMode.date;
    }
    if (i?.endDate != null && i!.endDate!.trim().isNotEmpty) {
      _courseMode = _CourseMode.until;
    }
    _name.addListener(_onNameChanged);
    _pills.addListener(_recalcRestock);
    _lead.addListener(_recalcRestock);
    if (widget.upcomingFollowUps.isNotEmpty) {
      _visitDateYmd = widget.upcomingFollowUps.first.dateYmd;
    }
    if (i != null) {
      _loadSchedule(i.id);
    }
  }

  Future<void> _loadSchedule(String medicationId) async {
    final row = await widget.store.primaryMedicationSchedule(medicationId);
    if (!mounted || row == null) return;
    final slots = MedicalStoreMixin.parseMedTimeSlots(row['times_json']);
    final mask = (row['days_mask'] as String?) ?? '1111111';
    final interval = row['interval_days'] as int?;
    setState(() {
      for (final r in _rows) {
        r.dispose();
      }
      _rows
        ..clear()
        ..addAll(
          slots.isEmpty
              ? [_DoseRow()]
              : [
                  for (final s in slots)
                    _DoseRow(
                      hm: s.hm,
                      amount: s.amount == s.amount.roundToDouble()
                          ? '${s.amount.round()}'
                          : '${s.amount}',
                    ),
                ],
        );
      _daysMask = mask;
      if (interval != null && interval > 1) {
        _freqMode = _FreqMode.interval;
        _intervalDays.text = '$interval';
      } else if (mask != '1111111') {
        _freqMode = _FreqMode.specific;
      } else {
        _freqMode = _FreqMode.daily;
      }
    });
    _recalcRestock();
  }

  void _onNameChanged() {
    if (_nameError != null && _name.text.trim().isNotEmpty) {
      setState(() => _nameError = null);
    }
  }

  int _unitsPerDay() {
    var n = 0.0;
    for (final r in _rows) {
      final a = double.tryParse(r.amount.text.trim()) ?? 0;
      if (r.hm.text.trim().contains(':')) n += a;
    }
    return n <= 0 ? 1 : n.ceil();
  }

  void _recalcRestock() {
    if (_restockMode == _RestockMode.none ||
        _restockMode == _RestockMode.date) {
      if (_planNote != null) setState(() => _planNote = null);
      return;
    }
    final pills = int.tryParse(_pills.text.trim());
    final lead = int.tryParse(_lead.text.trim()) ?? 3;
    DateTime? visitOn;
    if (_restockMode == _RestockMode.nextVisit && _visitDateYmd != null) {
      final p = _visitDateYmd!.split('-');
      if (p.length == 3) {
        visitOn = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
    }
    final dpd = _unitsPerDay();
    int? days;
    DateTime? stockOut;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    if (pills != null && pills > 0) {
      days = pills ~/ dpd;
      stockOut = start.add(Duration(days: days));
    }
    String? analysis;
    DateTime? alertOn;
    if (_restockMode == _RestockMode.nextVisit && visitOn != null) {
      if (stockOut == null) {
        analysis =
            'Reminder ${lead > 0 ? '$lead day${lead == 1 ? '' : 's'} before' : 'on'} this visit.';
        alertOn = visitOn.subtract(Duration(days: lead));
      } else {
        final earlier = stockOut.isBefore(visitOn) ? stockOut : visitOn;
        alertOn = earlier.subtract(Duration(days: lead));
        analysis = 'Alert before stock runs out or the visit.';
      }
    } else if (stockOut != null) {
      alertOn = stockOut.subtract(Duration(days: lead));
      analysis =
          'About $days day${days == 1 ? '' : 's'} of stock at this dose.';
    }
    if (alertOn != null) {
      _restock.text = DateFormat('yyyy-MM-dd').format(alertOn);
    }
    setState(() => _planNote = analysis);
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _pills.removeListener(_recalcRestock);
    _lead.removeListener(_recalcRestock);
    _name.dispose();
    _strength.dispose();
    _instructions.dispose();
    _pills.dispose();
    _restock.dispose();
    _lead.dispose();
    _endDate.dispose();
    _durationDays.dispose();
    _intervalDays.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() =>
          _nameError = 'Enter the name as on the bottle or prescription.');
      return;
    }
    if (_restockMode == _RestockMode.fromStock ||
        _restockMode == _RestockMode.nextVisit) {
      _recalcRestock();
    }

    String? endDate;
    if (_courseMode == _CourseMode.days) {
      final n = int.tryParse(_durationDays.text.trim());
      if (n != null && n > 0) {
        endDate = DateFormat('yyyy-MM-dd')
            .format(DateTime.now().add(Duration(days: n)));
      }
    } else if (_courseMode == _CourseMode.until) {
      final e = _endDate.text.trim();
      if (e.isNotEmpty) endDate = e;
    }

    var daysMask = '1111111';
    int? intervalDays;
    if (_freqMode == _FreqMode.specific) {
      daysMask = _daysMask.padRight(7, '0').substring(0, 7);
      if (!daysMask.contains('1')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pick at least one day for this medicine.'),
          ),
        );
        return;
      }
    } else if (_freqMode == _FreqMode.interval) {
      intervalDays = int.tryParse(_intervalDays.text.trim());
      if (intervalDays == null || intervalDays < 2) intervalDays = 2;
    }

    final slots = <Map<String, Object>>[];
    for (final r in _rows) {
      final hm = r.hm.text.trim();
      if (!hm.contains(':')) continue;
      final amount = double.tryParse(r.amount.text.trim()) ?? 1;
      slots.add({'hm': hm, 'amount': amount <= 0 ? 1 : amount});
    }

    Navigator.pop(context, <String, Object?>{
      'name': name,
      'kind': _kind,
      if (_strength.text.trim().isNotEmpty) 'strength': _strength.text.trim(),
      if (_instructions.text.trim().isNotEmpty)
        'instructions': _instructions.text.trim(),
      if (_pills.text.trim().isNotEmpty) 'pills': _pills.text.trim(),
      if (_restockMode != _RestockMode.none &&
          _restock.text.trim().isNotEmpty)
        'restock': _restock.text.trim(),
      if (_planNote != null && _planNote!.isNotEmpty) 'stockNote': _planNote!,
      if (widget.initial?.prescribedAs != null &&
          widget.initial!.prescribedAs!.isNotEmpty)
        'prescribedAs': widget.initial!.prescribedAs!,
      'dosageForm': _form,
      if (endDate != null) 'endDate': endDate,
      'daysMask': daysMask,
      if (intervalDays != null) 'intervalDays': intervalDays,
      'doseUnit': _unit,
      'slots': slots,
    });
  }

  Future<void> _pickTime(_DoseRow row) async {
    final parts = row.hm.text.trim().split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      row.hm.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    });
    _recalcRestock();
  }

  int get _selectedDayCount {
    final m = _daysMask.padRight(7, '0');
    var n = 0;
    for (var i = 0; i < 7; i++) {
      if (m[i] == '1') n++;
    }
    return n;
  }

  String get _freqSummary {
    if (_freqMode == _FreqMode.daily) return 'Taken every day — off days none.';
    if (_freqMode == _FreqMode.interval) {
      final n = int.tryParse(_intervalDays.text.trim()) ?? 2;
      return 'Taken every $n days from course start — other days show ×.';
    }
    final n = _selectedDayCount;
    if (n == 0) return 'Pick at least one day.';
    if (n == 1) return 'Once a week on the day you selected — other days show ×.';
    if (n == 2) return 'Twice a week on selected days — other days show ×.';
    if (_daysMask == '1111100') return 'Weekdays (Mon–Fri) — weekends show ×.';
    if (_daysMask == '0000011') return 'Weekends only — weekdays show ×.';
    return '$n days a week — unselected days show × on the month track.';
  }

  void _applyDayMask(String mask) {
    setState(() {
      _freqMode = _FreqMode.specific;
      _daysMask = mask.padRight(7, '0').substring(0, 7);
    });
  }

  Widget _freqPresets() {
    Widget chip(String label, String mask) {
      final selected =
          _freqMode == _FreqMode.specific && _daysMask == mask;
      return FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _applyDayMask(mask),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        chip('Mon–Fri', '1111100'),
        chip('Weekends', '0000011'),
        chip('Once weekly (Mon)', '1000000'),
        chip('Tue & Fri', '0100100'),
        chip('Mon · Wed · Fri', '1010100'),
      ],
    );
  }

  Widget _weekdayChips() {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (var i = 0; i < 7; i++)
          FilterChip(
            label: Text(labels[i]),
            selected: _daysMask.padRight(7, '0')[i] == '1',
            onSelected: (on) {
              final chars = _daysMask.padRight(7, '0').split('');
              chars[i] = on ? '1' : '0';
              setState(() {
                _freqMode = _FreqMode.specific;
                _daysMask = chars.join();
              });
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
      contentPadding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 28, 20),
      insetPadding: bodylineDialogInset(context),
      title: Text(
        widget.initial == null ? 'Add medicine or remedy' : 'Edit medicine',
      ),
      content: SizedBox(
        width: bodylineDialogWidth(context, 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(_kind),
                initialValue: _kind,
                items: [
                  for (final k in kMedicationKinds)
                    DropdownMenuItem(
                      value: k,
                      child: Text(medicationKindLabel(k)),
                    ),
                ],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              const SizedBox(height: 8),
              DrugNameField(
                controller: _name,
                autofocus: true,
                showKindSubtitle: true,
                preferredKind: _kind,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'As on the bottle or prescription',
                  helperText: 'Suggestions are offline names only — not advice',
                  errorText: _nameError,
                ),
                onSelected: (s) {
                  setState(() {
                    _kind = kMedicationKinds.contains(s.kind) ? s.kind : _kind;
                    _nameError = null;
                  });
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _strength,
                decoration: const InputDecoration(
                  labelText: 'Strength (optional)',
                  hintText: '500 mg, 100 mcg…',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _form,
                items: const [
                  DropdownMenuItem(value: 'tablet', child: Text('Tablet')),
                  DropdownMenuItem(value: 'capsule', child: Text('Capsule')),
                  DropdownMenuItem(value: 'syrup', child: Text('Syrup')),
                  DropdownMenuItem(value: 'tube', child: Text('Tube / cream')),
                  DropdownMenuItem(value: 'drops', child: Text('Drops')),
                  DropdownMenuItem(value: 'injection', child: Text('Injection')),
                  DropdownMenuItem(value: 'inhaler', child: Text('Inhaler')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() {
                  _form = v ?? 'tablet';
                  _recalcRestock();
                }),
                decoration: const InputDecoration(labelText: 'Form'),
              ),
              const SizedBox(height: 16),
              Text('How often', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Sets which calendar days need a dose — off days show ×.',
                style: TextStyle(fontSize: 12, color: BodylineColors.inkSubtle),
              ),
              const SizedBox(height: 8),
              SegmentedButton<_FreqMode>(
                segments: const [
                  ButtonSegment(
                    value: _FreqMode.daily,
                    label: Text('Every day'),
                  ),
                  ButtonSegment(
                    value: _FreqMode.specific,
                    label: Text('Specific days'),
                  ),
                  ButtonSegment(
                    value: _FreqMode.interval,
                    label: Text('Every N days'),
                  ),
                ],
                selected: {_freqMode},
                onSelectionChanged: (s) {
                  setState(() {
                    _freqMode = s.first;
                    if (_freqMode == _FreqMode.specific &&
                        _daysMask == '1111111') {
                      _daysMask = '1111100'; // default Mon–Fri
                    }
                  });
                },
              ),
              if (_freqMode == _FreqMode.specific) ...[
                const SizedBox(height: 10),
                Text(
                  'Quick patterns',
                  style: TextStyle(fontSize: 12, color: BodylineColors.inkSubtle),
                ),
                const SizedBox(height: 6),
                _freqPresets(),
                const SizedBox(height: 10),
                Text(
                  'Or tap days (once a week = one day; twice = two days…)',
                  style: TextStyle(fontSize: 12, color: BodylineColors.inkSubtle),
                ),
                const SizedBox(height: 6),
                _weekdayChips(),
              ],
              if (_freqMode == _FreqMode.interval) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _intervalDays,
                  decoration: const InputDecoration(
                    labelText: 'Every how many days?',
                    hintText: '2',
                    helperText:
                        '2 = every other day, 3 = every third day, from course start',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _freqSummary,
                style: TextStyle(
                  fontSize: 12,
                  color: _freqMode == _FreqMode.specific &&
                          _selectedDayCount == 0
                      ? theme.colorScheme.error
                      : BodylineColors.inkSubtle,
                ),
              ),
              const SizedBox(height: 16),
              Text('Dose times', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Clock time and how much each time (e.g. 1 tablet morning, 2 at night).',
                style: TextStyle(fontSize: 12, color: BodylineColors.inkSubtle),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _rows.length; i++) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: () => _pickTime(_rows[i]),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Time',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: Text(_rows[i].hm.text),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _rows[i].amount,
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          suffixText: _unit,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => _recalcRestock(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: _rows.length <= 1
                          ? null
                          : () => setState(() {
                                _rows.removeAt(i).dispose();
                                _recalcRestock();
                              }),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _rows.add(_DoseRow(hm: '20:00', amount: '1'));
                    _recalcRestock();
                  }),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add dose time'),
                ),
              ),
              const SizedBox(height: 12),
              Text('Course end', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<_CourseMode>(
                segments: const [
                  ButtonSegment(
                    value: _CourseMode.ongoing,
                    label: Text('Ongoing'),
                  ),
                  ButtonSegment(
                    value: _CourseMode.days,
                    label: Text('For N days'),
                  ),
                  ButtonSegment(
                    value: _CourseMode.until,
                    label: Text('Until date'),
                  ),
                ],
                selected: {_courseMode},
                onSelectionChanged: (s) =>
                    setState(() => _courseMode = s.first),
              ),
              if (_courseMode == _CourseMode.days) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _durationDays,
                  decoration: const InputDecoration(
                    labelText: 'Number of days',
                    hintText: '7',
                    helperText: 'Ends that many days from today',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
              if (_courseMode == _CourseMode.until) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _endDate,
                  decoration: const InputDecoration(
                    labelText: 'Until',
                    hintText: 'yyyy-MM-dd',
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _instructions,
                decoration: const InputDecoration(
                  labelText: 'Instructions (optional)',
                  hintText: 'empty stomach, with food…',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pills,
                decoration: InputDecoration(
                  labelText: stockLabelForForm(_form),
                  hintText: '30',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              Text('Restock reminder', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('None'),
                    selected: _restockMode == _RestockMode.none,
                    onSelected: (_) => setState(() {
                      _restockMode = _RestockMode.none;
                      _restock.clear();
                      _planNote = null;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('From stock'),
                    selected: _restockMode == _RestockMode.fromStock,
                    onSelected: (_) {
                      setState(() => _restockMode = _RestockMode.fromStock);
                      _recalcRestock();
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Next visit'),
                    selected: _restockMode == _RestockMode.nextVisit,
                    onSelected: widget.upcomingFollowUps.isEmpty
                        ? null
                        : (_) {
                            setState(() {
                              _restockMode = _RestockMode.nextVisit;
                              _visitDateYmd ??=
                                  widget.upcomingFollowUps.first.dateYmd;
                            });
                            _recalcRestock();
                          },
                  ),
                  ChoiceChip(
                    label: const Text('Pick date'),
                    selected: _restockMode == _RestockMode.date,
                    onSelected: (_) => setState(() {
                      _restockMode = _RestockMode.date;
                      _planNote = null;
                    }),
                  ),
                ],
              ),
              if (_restockMode == _RestockMode.nextVisit) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey(_visitDateYmd),
                  initialValue: _visitDateYmd,
                  items: [
                    for (final o in widget.upcomingFollowUps)
                      DropdownMenuItem(
                        value: o.dateYmd,
                        child: Text(o.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _visitDateYmd = v);
                    _recalcRestock();
                  },
                  decoration:
                      const InputDecoration(labelText: 'Follow-up visit'),
                ),
              ],
              if (_restockMode == _RestockMode.fromStock ||
                  _restockMode == _RestockMode.nextVisit) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _lead,
                  decoration: const InputDecoration(
                    labelText: 'Alert days before',
                    hintText: '3',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
              if (_restockMode == _RestockMode.date ||
                  _restockMode == _RestockMode.fromStock ||
                  _restockMode == _RestockMode.nextVisit) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _restock,
                  readOnly: _restockMode != _RestockMode.date,
                  decoration: InputDecoration(
                    labelText: _restockMode == _RestockMode.date
                        ? 'Restock by'
                        : 'Alert on',
                    hintText: 'yyyy-MM-dd',
                  ),
                ),
              ],
              if (_planNote != null) ...[
                const SizedBox(height: 8),
                Text(
                  _planNote!,
                  style: TextStyle(
                    fontSize: 12,
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
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: BodylineColors.tealDark),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: BodylineColors.ink,
            foregroundColor: BodylineColors.onInk,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
