import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../widgets/month_year_date_picker.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../profiles/edit_profile_sheet.dart';

Future<void> showFamilySheet({
  required BuildContext context,
  required LocalStore store,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: BodylineColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => FamilySheet(store: store, onChanged: onChanged),
  );
}

class FamilySheet extends StatefulWidget {
  const FamilySheet({super.key, required this.store, required this.onChanged});
  final LocalStore store;
  final VoidCallback onChanged;

  @override
  State<FamilySheet> createState() => _FamilySheetState();
}

class _FamilySheetState extends State<FamilySheet> {
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: BodylineColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Family', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Switch whose results you are viewing.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (final p in store.profiles) _card(p),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addMember,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add family member'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 48),
              foregroundColor: BodylineColors.tealDark,
              side: BorderSide(color: BodylineColors.border),
            ),
          ),
        ],
      ),
    );
  }


  String? _ageLabel(String? dob) {
    if (dob == null || dob.isEmpty) return null;
    try {
      final d = DateTime.parse(dob);
      final now = DateTime.now();
      var age = now.year - d.year;
      if (now.month < d.month ||
          (now.month == d.month && now.day < d.day)) {
        age--;
      }
      if (age < 0) return null;
      return age == 1 ? '1 yr' : '$age yrs';
    } catch (_) {
      return null;
    }
  }

  String? _dobLabel(String? dob) {
    if (dob == null || dob.isEmpty) return null;
    try {
      return DateFormat('d MMM yyyy').format(DateTime.parse(dob));
    } catch (_) {
      return null;
    }
  }

  ObservationRecord? _latestWeight(String profileId) {
    final list = widget.store.observations
        .where(
          (o) =>
              o.profileId == profileId &&
              !o.deleted &&
              o.parameterCode.toUpperCase() == 'WEIGHT',
        )
        .toList()
      ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
    return list.isEmpty ? null : list.first;
  }

  Widget _card(ProfileRecord p) {
    final active = p.id == widget.store.activeProfileId;
    final flagged = widget.store.observations
        .where((o) =>
            o.profileId == p.id &&
            o.flag != null &&
            o.flag != ObservationFlag.normal)
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: active ? BodylineColors.tealTint : BodylineColors.paper,
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        child: InkWell(
          borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
          onTap: () async {
            await widget.store.switchProfile(p.id);
            widget.onChanged();
            if (mounted) Navigator.pop(context);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: BodylineColors.teal.withValues(alpha: 0.15),
                  child: Text(
                    p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                    style: TextStyle(
                      color: BodylineColors.tealDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        [
                          profileRelationLabel(p.relation),
                          if (_ageLabel(p.dob) != null) _ageLabel(p.dob)!,
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_dobLabel(p.dob) != null ||
                          _latestWeight(p.id) != null)
                        Text(
                          [
                            if (_dobLabel(p.dob) != null)
                              'DOB ${_dobLabel(p.dob)}',
                            if (_latestWeight(p.id) != null)
                              () {
                                final w = _latestWeight(p.id)!;
                                final u = w.unitReported.trim();
                                final v = w.valueReported.trim();
                                final value = u.isEmpty ? v : '$v $u';
                                return 'Weight $value · ${DateFormat('d MMM yyyy').format(w.observedAt)}';
                              }(),
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: BodylineColors.inkSubtle,
                                fontSize: 11,
                              ),
                        ),
                    ],
                  ),
                ),
                Text(
                  flagged > 0 ? '$flagged outside range' : 'In range',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: flagged > 0
                            ? BodylineColors.orangeText
                            : BodylineColors.inkSubtle,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                IconButton(
                  tooltip: 'Edit profile',
                  onPressed: () => _editMember(p),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: BodylineColors.inkSubtle,
                ),
                IconButton(
                  tooltip: 'Delete member',
                  onPressed: () => _deleteMember(p),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: BodylineColors.inkSubtle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editMember(ProfileRecord p) async {
    final changed = await showEditProfileDialog(
      context: context,
      store: widget.store,
      profile: p,
    );
    if (changed && mounted) {
      widget.onChanged();
      setState(() {});
    }
  }

  Future<void> _deleteMember(ProfileRecord p) async {
    if (widget.store.profiles.length <= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keep at least one profile on this device.'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete family member?'),
        content: Text(
          'Remove ${p.name} from this device? Sync will tombstone this profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.store.softDeleteProfile(p.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _addMember() async {
    final name = TextEditingController();
    var relation = 'mother';
    final otherCtrl = TextEditingController();
    DateTime? dob;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Add member'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        for (final r in profileRelationChoices())
                          DropdownMenuItem(
                            value: r,
                            child: Text(profileRelationLabel(r)),
                          ),
                      ],
                      onChanged: (v) =>
                          setLocal(() => relation = v ?? relation),
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
                        onChanged: (_) => setLocal(() {}),
                      ),
                    ],
                    const SizedBox(height: 8),
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
                          if (picked != null) {
                            setLocal(() => dob = picked);
                          }
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
                  onPressed: () {
                    if (relation == 'other' &&
                        otherCtrl.text.trim().isEmpty) {
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: BodylineColors.ink,
                    foregroundColor: BodylineColors.onInk,
                  ),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final picked = dob;
      final dobIso = picked == null
          ? null
          : '${picked.year.toString().padLeft(4, '0')}-'
              '${picked.month.toString().padLeft(2, '0')}-'
              '${picked.day.toString().padLeft(2, '0')}';
      final savedRelation =
          relation == 'other' ? otherCtrl.text.trim() : relation;
      if (relation == 'other' && savedRelation.isEmpty) {
        name.dispose();
        otherCtrl.dispose();
        return;
      }
      await widget.store.createProfile(
        name: name.text.trim(),
        relation: savedRelation,
        dob: dobIso,
      );
      widget.onChanged();
      setState(() {});
    }
    name.dispose();
  }
}
