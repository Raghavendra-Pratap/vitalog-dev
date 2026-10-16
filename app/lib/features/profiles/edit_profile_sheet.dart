import 'package:flutter/material.dart';
import '../../widgets/bodyline_dialog.dart';
import '../../widgets/month_year_date_picker.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

const kProfileRelations = <String>[
  'self',
  'mother',
  'father',
  'partner',
  'son',
  'daughter',
  'brother',
  'sister',
  'other',
];

/// Older codes still stored on some profiles — keep displaying them.
const kLegacyProfileRelations = <String>[
  'parent',
  'spouse',
  'child',
  'sibling',
];

bool isKnownProfileRelation(String value) =>
    kProfileRelations.contains(value) || kLegacyProfileRelations.contains(value);

String profileRelationLabel(String value) {
  switch (value) {
    case 'self':
      return 'You';
    case 'mother':
      return 'Mother';
    case 'father':
      return 'Father';
    case 'partner':
    case 'spouse':
      return 'Partner';
    case 'son':
      return 'Son';
    case 'daughter':
      return 'Daughter';
    case 'brother':
      return 'Brother';
    case 'sister':
      return 'Sister';
    case 'parent':
      return 'Parent';
    case 'child':
      return 'Child';
    case 'sibling':
      return 'Sibling';
    case 'other':
      return 'Other';
    default:
      // Custom “other” label typed by the user.
      return value.trim().isEmpty ? 'Other' : value.trim();
  }
}

/// Choices when adding/editing a member (excludes You).
List<String> profileRelationChoices({String? include}) {
  final out = <String>[
    for (final r in kProfileRelations)
      if (r != 'self') r,
  ];
  if (include != null &&
      include.isNotEmpty &&
      include != 'self' &&
      isKnownProfileRelation(include) &&
      !out.contains(include)) {
    out.insert(0, include);
  }
  return out;
}

Future<bool> showEditProfileDialog({
  required BuildContext context,
  required LocalStore store,
  required ProfileRecord profile,
}) async {
  final name = TextEditingController(text: profile.name);
  final isCustom = profile.relation.isNotEmpty &&
      !isKnownProfileRelation(profile.relation);
  var relation = profile.relation == 'self'
      ? 'self'
      : (isCustom
          ? 'other'
          : (isKnownProfileRelation(profile.relation)
              ? profile.relation
              : 'other'));
  final otherCtrl = TextEditingController(
    text: isCustom ? profile.relation : '',
  );
  final heightCtrl = TextEditingController(
    text: profile.heightCm == null
        ? ''
        : (profile.heightCm == profile.heightCm!.roundToDouble()
            ? profile.heightCm!.toStringAsFixed(0)
            : profile.heightCm.toString()),
  );
  DateTime? dob;
  if (profile.dob != null && profile.dob!.isNotEmpty) {
    try {
      dob = DateTime.parse(profile.dob!);
    } catch (_) {}
  }
  String? sex = switch ((profile.sex ?? '').trim().toLowerCase()) {
    'm' || 'male' => 'M',
    'f' || 'female' => 'F',
    'other' => 'other',
    _ => null,
  };

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Edit profile'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  BodylineSelectField<String>(
                    label: 'Relation to you',
                    value: relation,
                    valueLabel: profileRelationLabel(relation),
                    options: [
                      if (relation == 'self')
                        const BodylineSelectOption(value: 'self', label: 'You'),
                      for (final r in profileRelationChoices(
                        include: relation == 'self' ? null : relation,
                      ))
                        BodylineSelectOption(
                          value: r,
                          label: profileRelationLabel(r),
                        ),
                    ],
                    onSelected: (v) => setLocal(() => relation = v),
                  ),
                  if (relation == 'other') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: otherCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Describe the relation',
                        hintText: 'e.g. Aunt, Cousin, Caregiver',
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dob == null
                              ? 'Date of birth (optional)'
                              : 'DOB · ${dob!.year}-${dob!.month.toString().padLeft(2, '0')}-${dob!.day.toString().padLeft(2, '0')}',
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await pickBodylineDate(
                            ctx,
                            initialDate: dob ?? DateTime(1990, 1, 1),
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setLocal(() => dob = picked);
                        },
                        child: Text(dob == null ? 'Set' : 'Change'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  BodylineSelectField<String?>(
                    label: 'Sex',
                    value: sex,
                    valueLabel: switch (sex) {
                      'M' => 'Male',
                      'F' => 'Female',
                      'other' => 'Other',
                      _ => 'Prefer not to say',
                    },
                    options: const [
                      BodylineSelectOption(value: null, label: 'Prefer not to say'),
                      BodylineSelectOption(value: 'M', label: 'Male'),
                      BodylineSelectOption(value: 'F', label: 'Female'),
                      BodylineSelectOption(value: 'other', label: 'Other'),
                    ],
                    onSelected: (v) => setLocal(() => sex = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: heightCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Height (cm, optional)',
                      hintText: 'e.g. 172',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(ctx, false);
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: BodylineColors.teal,
                ),
                onPressed: () {
                  if (relation == 'other' &&
                      otherCtrl.text.trim().isEmpty) {
                    return;
                  }
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(ctx, true);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  // The dialog route is still animating out when this future completes.
  // Disposing the fields' controllers in that window trips a Flutter
  // assertion (_dependents.isEmpty) and replaces the screen with red.
  final trimmed = name.text.trim();
  final otherLabel = otherCtrl.text.trim();
  final heightRaw = heightCtrl.text.trim();
  Future<void>.delayed(const Duration(milliseconds: 400), () {
    name.dispose();
    otherCtrl.dispose();
    heightCtrl.dispose();
  });
  if (ok != true) return false;
  if (trimmed.isEmpty) return false;

  final savedRelation = relation == 'other'
      ? otherLabel
      : relation;

  final pickedDob = dob;
  final dobIso = pickedDob == null
      ? null
      : '${pickedDob.year.toString().padLeft(4, '0')}-'
          '${pickedDob.month.toString().padLeft(2, '0')}-'
          '${pickedDob.day.toString().padLeft(2, '0')}';
  double? heightCm;
  var clearHeight = false;
  if (heightRaw.isEmpty) {
    clearHeight = profile.heightCm != null;
  } else {
    heightCm = double.tryParse(heightRaw);
    if (heightCm == null || heightCm < 50 || heightCm > 280) {
      return false;
    }
  }
  await store.updateProfile(
    id: profile.id,
    name: trimmed,
    relation: savedRelation,
    dob: dobIso,
    clearDob: dobIso == null && (profile.dob != null && profile.dob!.isNotEmpty),
    sex: sex,
    clearSex: sex == null && (profile.sex != null && profile.sex!.isNotEmpty),
    heightCm: heightCm,
    clearHeightCm: clearHeight,
  );
  if (heightCm != null &&
      (profile.heightCm == null || (profile.heightCm! - heightCm).abs() >= 0.05)) {
    final reported = heightCm == heightCm.roundToDouble()
        ? heightCm.toStringAsFixed(0)
        : heightCm.toStringAsFixed(1);
    await store.recordVital(
      profileId: profile.id,
      parameterCode: 'height',
      parameterName: 'Height',
      valueReported: reported,
      unitReported: 'cm',
      title: 'Height',
    );
  }
  return true;
}
