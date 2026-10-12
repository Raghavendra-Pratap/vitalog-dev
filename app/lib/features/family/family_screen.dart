import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import '../../widgets/month_year_date_picker.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../profiles/edit_profile_sheet.dart';

/// Desktop Family artboard — profile cards grid to switch who you are viewing.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({
    super.key,
    required this.store,
    required this.onChanged,
  });

  final LocalStore store;
  final VoidCallback onChanged;

  @override
  FamilyScreenState createState() => FamilyScreenState();
}

class FamilyScreenState extends State<FamilyScreen> {
  final Map<String, int> _medCounts = {};

  @override
  void initState() {
    super.initState();
    _loadMeds();
  }

  Future<void> _loadMeds() async {
    final map = <String, int>{};
    for (final p in widget.store.profiles) {
      final meds = await widget.store.listMedications(p.id);
      map[p.id] = meds.length;
    }
    if (mounted) setState(() => _medCounts
      ..clear()
      ..addAll(map));
  }

  /// Called from desktop top bar "+ Add family member".
  Future<void> promptAddMember() => _addMember();

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final fmt = DateFormat('d MMM yyyy');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesktopLayout.mainPaddingH,
        8,
        DesktopLayout.mainPaddingH,
        DesktopLayout.mainPaddingV,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.55,
              ),
              itemCount: store.profiles.length,
              itemBuilder: (context, i) => _card(store.profiles[i], fmt),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 14, color: BodylineColors.teal),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Family profiles stay on this device and in your own cloud backup. Nobody else can see them.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: BodylineColors.inkSubtle,
                      ),
                ),
              ),
            ],
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
      final d = DateTime.parse(dob);
      return DateFormat('d MMM yyyy').format(d);
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

  Color _avatarColor(ProfileRecord p) {
    final colors = [
      BodylineColors.teal,
      const Color(0xFF6B5B95),
      const Color(0xFF8B5E3C),
      const Color(0xFF3A6EA5),
      const Color(0xFF5C7A3A),
    ];
    return colors[p.name.hashCode.abs() % colors.length];
  }

  Widget _card(ProfileRecord p, DateFormat fmt) {
    final active = p.id == widget.store.activeProfileId;
    final obs = widget.store.observations.where((o) => o.profileId == p.id);
    final flagged = obs
        .where((o) => o.flag != null && o.flag != ObservationFlag.normal)
        .map((o) => o.parameterCode)
        .toSet()
        .length;
    final params = obs.map((o) => o.parameterCode).toSet().length;
    final reports = widget.store.reports.where((r) => r.profileId == p.id).toList()
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
    final last = reports.isEmpty ? null : reports.first.collectedAt;
    final meds = _medCounts[p.id] ?? 0;
    final sinceYear = reports.isEmpty ? null : reports.map((r) => r.collectedAt.year).reduce((a, b) => a < b ? a : b);
    final relation = p.relation.isEmpty
        ? 'Family'
        : profileRelationLabel(p.relation);
    final age = _ageLabel(p.dob);
    final dobLabel = _dobLabel(p.dob);
    final weight = _latestWeight(p.id);
    final relationBit = active
        ? '${profileRelationLabel(p.relation.isEmpty ? 'self' : p.relation)} · currently viewing'
        : relation;
    final subtitle = [
      relationBit,
      if (age != null) age,
    ].join(' · ');

    return Material(
      color: BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.card),
      elevation: active ? 0 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        onTap: () async {
          await widget.store.switchProfile(p.id);
          widget.onChanged();
          setState(() {});
        },
        onLongPress: () => _editMember(p),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BodylineRadii.card),
            border: Border.all(
              color: active ? BodylineColors.teal : BodylineColors.border,
              width: active ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: _avatarColor(p),
                    child: Text(
                      p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                      style: TextStyle(
                        color: BodylineColors.onInk,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
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
                          style: const TextStyle(
                            fontFamily: 'Fraunces',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(flagged),
                  IconButton(
                    tooltip: 'Edit profile',
                    onPressed: () => _editMember(p),
                    icon: const Icon(Icons.edit_outlined),
                    color: BodylineColors.inkSubtle,
                  ),
                  IconButton(
                    tooltip: 'Delete member',
                    onPressed: () => _deleteMember(p),
                    icon: const Icon(Icons.delete_outline),
                    color: BodylineColors.inkSubtle,
                  ),
                ],
              ),
              if (dobLabel != null || weight != null) ...[
                const SizedBox(height: 8),
                if (dobLabel != null)
                  Text(
                    'DOB $dobLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: BodylineColors.inkSubtle,
                        ),
                  ),
                if (weight != null) ...[
                  if (dobLabel != null) const SizedBox(height: 2),
                  Text(
                    () {
                      final v = weight.valueReported.trim();
                      final u = weight.unitReported.trim();
                      final when = DateFormat('d MMM yyyy').format(weight.observedAt);
                      final value = u.isEmpty ? v : '$v $u';
                      return 'Weight $value · $when';
                    }(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: BodylineColors.inkSubtle,
                        ),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  _stat('Tracked', '$params', 'parameters'),
                  const SizedBox(width: 8),
                  _stat(
                    'Reports',
                    '${reports.length}',
                    sinceYear == null ? '' : 'since $sinceYear',
                  ),
                  const SizedBox(width: 8),
                  _stat('Meds', '$meds', meds == 0 ? 'none' : 'current'),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      last == null
                          ? 'No tests yet'
                          : 'Last test ${fmt.format(last)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (flagged > 0)
                    Text(
                      '$flagged need attention',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: BodylineColors.tealDark,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(int flagged) {
    final ok = flagged == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ok ? BodylineColors.tealTint : BodylineColors.orangeTint,
        borderRadius: BorderRadius.circular(BodylineRadii.pill),
      ),
      child: Text(
        ok ? 'In range' : '$flagged flagged',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: ok ? BodylineColors.tealDark : BodylineColors.orangeText,
        ),
      ),
    );
  }

  Widget _stat(String label, String value, String sub) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: BodylineColors.chip,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: BodylineColors.inkSubtle)),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (sub.isNotEmpty)
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: BodylineColors.inkSubtle)),
          ],
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
    if (changed) {
      await _loadMeds();
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
          'Remove ${p.name} from this device? Their records stay in the vault until you clear data; sync will tombstone this profile.',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
      return;
    }
    await _loadMeds();
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
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Name'),
                      textCapitalization: TextCapitalization.words,
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
      await _loadMeds();
      widget.onChanged();
      setState(() {});
    }
    name.dispose();
  }
}

