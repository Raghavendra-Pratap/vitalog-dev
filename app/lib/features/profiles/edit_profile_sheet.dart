import 'package:flutter/material.dart';
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
  DateTime? dob;
  if (profile.dob != null && profile.dob!.isNotEmpty) {
    try {
      dob = DateTime.parse(profile.dob!);
    } catch (_) {}
  }

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
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: relation,
                    items: [
                      for (final r in profileRelationChoices(
                        include: relation == 'self' ? null : relation,
                      ))
                        DropdownMenuItem(
                          value: r,
                          child: Text(profileRelationLabel(r)),
                        ),
                      if (relation == 'self')
                        const DropdownMenuItem(
                          value: 'self',
                          child: Text('You'),
                        ),
                    ],
                    onChanged: (v) => setLocal(() => relation = v ?? relation),
                    decoration: const InputDecoration(
                      labelText: 'Relation to you',
                    ),
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
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      dob == null
                          ? 'Date of birth (optional)'
                          : 'DOB · ${dob!.year}-${dob!.month.toString().padLeft(2, '0')}-${dob!.day.toString().padLeft(2, '0')}',
                    ),
                    trailing: TextButton(
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
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
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

  if (ok != true) {
    name.dispose();
    otherCtrl.dispose();
    return false;
  }
  final trimmed = name.text.trim();
  final otherLabel = otherCtrl.text.trim();
  name.dispose();
  otherCtrl.dispose();
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
  await store.updateProfile(
    id: profile.id,
    name: trimmed,
    relation: savedRelation,
    dob: dobIso,
    clearDob: dobIso == null && (profile.dob != null && profile.dob!.isNotEmpty),
  );
  return true;
}
