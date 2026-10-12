import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../theme/tokens.dart';
import '../shell/app_shell.dart';
import '../../widgets/bodyline_dialog.dart';
import '../../widgets/month_year_date_picker.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.store, required this.onDone});

  final LocalStore store;
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  String _relation = 'self';
  String? _sex;
  DateTime? _dob;

  static const _relations = <BodylineSelectOption<String>>[
    BodylineSelectOption(value: 'self', label: 'Me'),
    BodylineSelectOption(value: 'parent', label: 'Parent'),
    BodylineSelectOption(value: 'spouse', label: 'Partner'),
    BodylineSelectOption(value: 'child', label: 'Child'),
    BodylineSelectOption(value: 'other', label: 'Other'),
  ];

  static const _sexes = <BodylineSelectOption<String?>>[
    BodylineSelectOption(value: null, label: 'Prefer not to say'),
    BodylineSelectOption(value: 'M', label: 'Male'),
    BodylineSelectOption(value: 'F', label: 'Female'),
    BodylineSelectOption(value: 'other', label: 'Other'),
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final picked = await pickBodylineDate(
      context,
      initialDate: _dob ?? DateTime(1995, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Date of birth (optional)',
    );
    if (picked == null || !mounted) return;
    setState(() => _dob = picked);
  }

  Future<void> _continue() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final dob = _dob;
    final dobIso = dob == null
        ? null
        : '${dob.year.toString().padLeft(4, '0')}-'
            '${dob.month.toString().padLeft(2, '0')}-'
            '${dob.day.toString().padLeft(2, '0')}';
    await widget.store.createProfile(
      name: name,
      relation: _relation,
      sex: _sex,
      dob: dobIso,
    );
    widget.onDone();
  }

  String get _relationLabel =>
      _relations
          .firstWhere((o) => o.value == _relation, orElse: () => _relations.first)
          .label;

  String get _sexLabel =>
      _sexes.firstWhere((o) => o.value == _sex, orElse: () => _sexes.first).label;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      const BodylineLockup(markSize: 36, wordSize: 28),
                      const SizedBox(height: 10),
                      Text(
                        'Your body, over time.',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: BodylineColors.inkSubtle,
                            ),
                      ),
                      const SizedBox(height: 36),
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                        ),
                      ),
                      const SizedBox(height: 16),
                      BodylineSelectField<String>(
                        label: 'This profile is',
                        value: _relation,
                        valueLabel: _relationLabel,
                        options: _relations,
                        onSelected: (v) => setState(() => _relation = v),
                      ),
                      const SizedBox(height: 16),
                      BodylineSelectField<String?>(
                        label: 'Sex (for default ranges later)',
                        value: _sex,
                        valueLabel: _sexLabel,
                        options: _sexes,
                        onSelected: (v) => setState(() => _sex = v),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: _pickDob,
                        borderRadius: BorderRadius.circular(BodylineRadii.input),
                        child: InputDecorator(
                          isFocused: false,
                          decoration: InputDecoration(
                            labelText: 'Date of birth (optional)',
                            suffixIcon: _dob == null
                                ? Icon(
                                    Icons.expand_more,
                                    color: BodylineColors.inkMuted,
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Clear',
                                        onPressed: () =>
                                            setState(() => _dob = null),
                                        icon: const Icon(Icons.close, size: 18),
                                      ),
                                      Icon(
                                        Icons.expand_more,
                                        color: BodylineColors.inkMuted,
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                  ),
                          ),
                          child: Text(
                            _dob == null
                                ? 'Not set'
                                : DateFormat('d MMM yyyy').format(_dob!),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _dob == null
                                  ? BodylineColors.inkSubtle
                                  : BodylineColors.ink,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              FilledButton(
                onPressed: _continue,
                style: FilledButton.styleFrom(
                  backgroundColor: BodylineColors.ink,
                  foregroundColor: BodylineColors.onInk,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Data stays on this device. Nothing is sent to Vitalog servers.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
