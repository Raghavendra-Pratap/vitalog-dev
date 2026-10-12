import 'package:flutter/material.dart';

import '../../data/local_store.dart';
import '../../security/app_lock.dart';
import '../../theme/theme_controller.dart';
import '../../sync/lan_sync_service.dart';
// import '../doctor/doctor_summary.dart'; // Doctor summary hidden for now
import '../visits/care_screen.dart';
import '../medicines/medicines_screen.dart';
import '../../notifications/reminder_notifications.dart';
import '../../widgets/clinical_attachments.dart';
import '../../data/models.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../settings/settings_screen.dart';
import '../profiles/edit_profile_sheet.dart';

enum _Section {
  conditions,
  medications,
  allergies,
  vaccinations,
  surgeries,
  familyHistory,
  emergency,
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.store,
    required this.onChanged,
    required this.lock,
    required this.theme,
    required this.sync,
    this.desktop = false,
    this.onOpenDesktopNav,
  });

  final LocalStore store;
  final VoidCallback onChanged;
  final AppLockController lock;
  final ThemeController theme;
  final LanSyncService sync;
  final bool desktop;
  /// Desktop nav: 4 medicines · 5 reminders · 6 visits · 7 doctors.
  final ValueChanged<int>? onOpenDesktopNav;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _openCareTab(int navIndex) {
    final go = widget.onOpenDesktopNav;
    if (go == null) return false;
    go(navIndex);
    return true;
  }

  final Map<_Section, List<MedicalItem>> _items = {};
  List<String> _doctors = [];
  List<VisitRecord> _recentVisits = [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store.activeProfileId != widget.store.activeProfileId) {
      _reload();
    }
  }

  Future<void> _reload() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      setState(() {
        _items.clear();
        _doctors = [];
        _recentVisits = [];
        _loading = false;
      });
      return;
    }
    final map = <_Section, List<MedicalItem>>{
      _Section.conditions: await widget.store.listConditions(pid),
      _Section.medications: await widget.store.listMedications(pid),
      _Section.allergies: await widget.store.listAllergies(pid),
      _Section.vaccinations: await widget.store.listImmunizations(pid),
      _Section.surgeries: await widget.store.listProcedures(pid),
      _Section.familyHistory: await widget.store.listFamilyHistory(pid),
      _Section.emergency: await widget.store.listEmergencyContacts(pid),
    };
    final doctors = await widget.store.listDoctorNames(pid);
    final visits = await widget.store.listVisits(pid);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(map);
      _doctors = doctors;
      _recentVisits = visits.take(5).toList();
      _loading = false;
    });
  }

  ProfileRecord? get _profile {
    final id = widget.store.activeProfileId;
    if (id == null) return null;
    for (final p in widget.store.profiles) {
      if (p.id == id) return p;
    }
    return widget.store.profiles.isEmpty ? null : widget.store.profiles.first;
  }

  String _metaLine(ProfileRecord p) {
    final parts = <String>[];
    if (p.sex != null && p.sex!.isNotEmpty) {
      parts.add(p.sex![0].toUpperCase() + p.sex!.substring(1));
    }
    if (p.dob != null && p.dob!.isNotEmpty) {
      final age = _ageFromDob(p.dob!);
      if (age != null) parts.add('$age yrs');
    }
    parts.add(profileRelationLabel(p.relation));
    return parts.join(' · ');
  }

  int? _ageFromDob(String dob) {
    try {
      final d = DateTime.parse(dob);
      final now = DateTime.now();
      var age = now.year - d.year;
      if (now.month < d.month ||
          (now.month == d.month && now.day < d.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    if (widget.desktop) return _buildDesktopProfile(profile);

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          widget.desktop ? 32 : 20,
          widget.desktop ? 8 : 12,
          widget.desktop ? 32 : 20,
          widget.desktop ? 24 : 100,
        ),
        children: [
          if (!widget.desktop)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Health profile',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        store: widget.store,
                        lock: widget.lock,
                        theme: widget.theme,
                        sync: widget.sync,
                        onChanged: () {
                          widget.onChanged();
                          _reload();
                        },
                      ),
                    ),
                  );
                  await _reload();
                },
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          if (profile != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BodylineColors.surface,
                borderRadius: BorderRadius.circular(BodylineRadii.card),
                border: Border.all(color: BodylineColors.border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: BodylineColors.tealTint,
                    child: Text(
                      profile.name.isEmpty
                          ? '?'
                          : profile.name[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: BodylineColors.tealDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          _metaLine(profile),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Temporarily hidden — restore Doctor summary (PDF) when ready.
          // DoctorSummaryButton(store: widget.store),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _sectionCard(
              section: _Section.conditions,
              title: 'Conditions',
              icon: Icons.healing_outlined,
              empty: 'None added yet',
              countLabel: (n) => n == 1 ? '1 active' : '$n active',
            ),
            _sectionCard(
              section: _Section.medications,
              title: 'Medicines & remedies',
              icon: Icons.medication_outlined,
              empty: 'None added yet',
              countLabel: (n) => n == 1 ? '1 current' : '$n current',
              onOpen: () {
                if (_openCareTab(6)) return;
                _openSection(_Section.medications, 'Medicines & remedies');
              },
            ),
            _sectionCard(
              section: _Section.allergies,
              title: 'Allergies',
              icon: Icons.warning_amber_outlined,
              empty: 'None added yet',
              countLabel: (n) => '$n',
            ),
            _sectionCard(
              section: _Section.vaccinations,
              title: 'Vaccinations',
              icon: Icons.vaccines_outlined,
              empty: 'None added yet',
              countLabel: (n) => '$n',
            ),
            _sectionCard(
              section: _Section.surgeries,
              title: 'Surgeries & procedures',
              icon: Icons.local_hospital_outlined,
              empty: 'None added yet',
              countLabel: (n) => '$n',
            ),
            _sectionCard(
              section: _Section.familyHistory,
              title: 'Family history',
              icon: Icons.account_tree_outlined,
              empty: 'None added yet',
              countLabel: (n) => '$n',
            ),
            _sectionCard(
              section: _Section.emergency,
              title: 'Emergency contact',
              icon: Icons.contact_phone_outlined,
              empty: 'None added yet',
              countLabel: (n) => '$n',
            ),
          ],
        ],
      ),
    );
  }



  Widget _buildDesktopProfile(ProfileRecord? profile) {
    final allergies = _items[_Section.allergies] ?? const [];
    final meds = _items[_Section.medications] ?? const [];
    final initial = (profile?.name.isNotEmpty == true)
        ? profile!.name[0].toUpperCase()
        : '?';

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
          // Hero summary
          Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            decoration: BoxDecoration(
              color: BodylineColors.surface,
              borderRadius: BorderRadius.circular(BodylineRadii.card),
              border: Border.all(color: BodylineColors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: BodylineColors.teal,
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: BodylineColors.onInk,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.name ?? 'Profile',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontSize: 24,
                            ),
                      ),
                      Text(
                        profile == null ? '' : _metaLine(profile),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                            ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 480,
                  child: Row(
                    children: [
                      Expanded(
                        child: _miniStat(
                          'Blood group',
                          (profile?.bloodGroup == null ||
                                  profile!.bloodGroup!.isEmpty)
                              ? '[—]'
                              : profile.bloodGroup!,
                          'tap to set',
                          onTap: profile == null
                              ? null
                              : () => _setBloodGroup(profile),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _miniStat(
                          'Allergies',
                          '${allergies.length}',
                          allergies.isEmpty ? 'none' : 'listed',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _miniStat(
                          'Current meds',
                          '${meds.length}',
                          meds.isEmpty ? 'none' : 'current',
                          onTap: () {
                            if (!_openCareTab(6)) {
                              _openSection(_Section.medications, 'Medicines & remedies');
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, c) {
                      const cols = 4;
                      final gap = DesktopLayout.mainGap;
                      final w = (c.maxWidth - gap * (cols - 1)) / cols;
                      final cards = <Widget>[
                        _richSection(
                          _Section.conditions,
                          'Conditions',
                          (n) => n == 1 ? '1 active' : '$n active',
                          '+ Add condition',
                        ),
                        _richSection(
                          _Section.medications,
                          'Medicines & remedies',
                          (n) => n == 1 ? '1 current' : '$n current',
                          '+ Add medicine',
                        ),
                        _richSection(
                          _Section.allergies,
                          'Allergies',
                          (n) => n == 1 ? '1 listed' : '$n listed',
                          '+ Add allergy',
                        ),
                        _richSection(
                          _Section.vaccinations,
                          'Vaccinations',
                          (n) => n == 1 ? '1 recorded' : '$n recorded',
                          '+ Add vaccination',
                        ),
                        _richSection(
                          _Section.surgeries,
                          'Surgeries & procedures',
                          (n) => n == 1 ? '1 recorded' : '$n recorded',
                          '+ Add surgery',
                        ),
                        _richSection(
                          _Section.familyHistory,
                          'Family history',
                          (n) => n == 1 ? '1 note' : '$n notes',
                          '+ Add note',
                        ),
                        _richSection(
                          _Section.emergency,
                          'Emergency contacts',
                          (n) => n == 1 ? '1 contact' : '$n contacts',
                          '+ Add contact',
                        ),
                        _doctorsCard(),
                      ];
                      return SingleChildScrollView(
                        child: Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final card in cards)
                              SizedBox(width: w, child: card),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }


  Widget _doctorsCard() {
    return Material(
      color: BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        onTap: () {
          if (!_openCareTab(10)) {
            // Mobile: open visits/care where doctors are managed.
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CareScreen(
                  store: widget.store,
                  onChanged: widget.onChanged,
                ),
              ),
            );
          }
        },
        child: Container(
      constraints: const BoxConstraints(minHeight: 180),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Doctors',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'From visits',
                style: TextStyle(
                  fontSize: 12,
                  color: BodylineColors.inkSubtle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'From visits you log — add a visit with a doctor name to see them here.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_doctors.isEmpty && _recentVisits.isEmpty)
            Text(
              'No doctors yet.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else ...[
            for (final name in _doctors)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(name,
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            if (_recentVisits.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Recent visits',
                  style: TextStyle(
                    fontSize: 12,
                    color: BodylineColors.inkSubtle,
                    fontWeight: FontWeight.w600,
                  )),
              for (final v in _recentVisits.take(3))
                Text(
                  [
                    v.reason?.isNotEmpty == true ? v.reason! : 'Visit',
                    if (v.providerName != null) v.providerName!,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () async {
                if (_openCareTab(10)) return;
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CareScreen(
                      store: widget.store,
                      onChanged: widget.onChanged,
                    ),
                  ),
                );
                widget.onChanged();
                await _reload();
              },
              borderRadius: BorderRadius.circular(10),
              child: CustomPaint(
                painter: _DashedRRectPainter(
                  color: BodylineColors.inkSubtle,
                  radius: 10,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    '+ Add visit / doctor',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: BodylineColors.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _miniStat(
    String label,
    String value,
    String sub, {
    VoidCallback? onTap,
  }) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: BodylineColors.chip,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: BodylineColors.inkSubtle)),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: BodylineColors.ink,
            ),
          ),
          Text(sub,
              style: TextStyle(
                  fontSize: 12, color: BodylineColors.inkSubtle)),
        ],
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    );
  }

  static const _bloodGroups = <String>[
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  Future<void> _setBloodGroup(ProfileRecord profile) async {
    final chosen = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: BodylineColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Blood group',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Saved on this device only.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in _bloodGroups)
                      ChoiceChip(
                        label: Text(g),
                        selected: profile.bloodGroup == g,
                        onSelected: (_) => Navigator.pop(ctx, g),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, ''),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen == null || !mounted) return;
    await widget.store.updateProfile(
      id: profile.id,
      bloodGroup: chosen.isEmpty ? null : chosen,
      clearBloodGroup: chosen.isEmpty,
    );
    widget.onChanged();
    setState(() {});
  }

  Widget _richSection(
    _Section section,
    String title,
    String Function(int) countLabel,
    String addLabel,
  ) {
    final items = _items[section] ?? const [];
    return Material(
      color: BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        onTap: () {
          if (section == _Section.medications && _openCareTab(6)) return;
          _openSection(section, title);
        },
        child: Container(
      constraints: const BoxConstraints(minHeight: 180),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: BodylineColors.ink,
                  ),
                ),
              ),
              Text(
                countLabel(items.length),
                style: TextStyle(
                  fontSize: 12,
                  color: BodylineColors.inkSubtle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'None added yet',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final item in items.take(3))
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: BodylineColors.divider),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (item.subtitle != null && item.subtitle!.isNotEmpty)
                      Flexible(
                        child: Text(
                          item.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            color: BodylineColors.inkSubtle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () {
                if (section == _Section.medications && _openCareTab(6)) return;
                _openSection(section, title);
              },
              borderRadius: BorderRadius.circular(10),
              child: CustomPaint(
                painter: _DashedRRectPainter(
                  color: BodylineColors.inkSubtle,
                  radius: 10,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    addLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: BodylineColors.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required _Section section,
    required String title,
    required IconData icon,
    required String empty,
    required String Function(int) countLabel,
    VoidCallback? onOpen,
  }) {
    final items = _items[section] ?? const <MedicalItem>[];
    final preview = items.isEmpty
        ? empty
        : items
            .take(2)
            .map((i) => [
                  if (section == _Section.familyHistory &&
                      i.subtitle?.isNotEmpty == true)
                    '${i.subtitle} · ${i.title}'
                  else
                    i.title,
                  if (section != _Section.familyHistory &&
                      i.subtitle?.isNotEmpty == true)
                    i.subtitle!,
                ].join(section == _Section.familyHistory ? '' : ' · '))
            .join('\n');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: BodylineColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
          side: BorderSide(color: BodylineColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
          onTap: onOpen ?? () => _openSection(section, title),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Icon(icon, color: BodylineColors.tealDark, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (items.isNotEmpty)
                            Text(
                              countLabel(items.length),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: BodylineColors.tealDark,
                                  ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: BodylineColors.inkSubtle),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSection(_Section section, String title) async {
    if (section == _Section.medications) {
      if (_openCareTab(6)) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MedicinesScreen(
            store: widget.store,
            onChanged: widget.onChanged,
          ),
        ),
      );
      widget.onChanged();
      await _reload();
      return;
    }

    // Unmapped to Care tabs — manage in a popup on desktop/mobile.
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(BodylineRadii.card),
            child: _SectionListScreen(
              store: widget.store,
              section: section,
              title: title,
              embedded: true,
              onChanged: () {
                widget.onChanged();
                _reload();
              },
              onClose: () => Navigator.pop(ctx),
            ),
          ),
        ),
      ),
    );
    await _reload();
  }
}

class _SectionListScreen extends StatefulWidget {
  const _SectionListScreen({
    required this.store,
    required this.section,
    required this.title,
    required this.onChanged,
    this.embedded = false,
    this.onClose,
  });

  final LocalStore store;
  final _Section section;
  final String title;
  final VoidCallback onChanged;
  final bool embedded;
  final VoidCallback? onClose;

  @override
  State<_SectionListScreen> createState() => _SectionListScreenState();
}

class _SectionListScreenState extends State<_SectionListScreen> {
  List<MedicalItem> _items = [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      setState(() {
        _items = [];
        _loading = false;
      });
      return;
    }
    final list = switch (widget.section) {
      _Section.conditions => await widget.store.listConditions(pid),
      _Section.medications => await widget.store.listMedications(pid),
      _Section.allergies => await widget.store.listAllergies(pid),
      _Section.vaccinations => await widget.store.listImmunizations(pid),
      _Section.surgeries => await widget.store.listProcedures(pid),
      _Section.familyHistory => await widget.store.listFamilyHistory(pid),
      _Section.emergency => await widget.store.listEmergencyContacts(pid),
    };
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(
                    'Nothing here yet. Tap Add to record one.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    final title = widget.section == _Section.familyHistory &&
                            item.subtitle?.isNotEmpty == true
                        ? '${item.subtitle} · ${item.title}'
                        : item.title;
                    final subtitle = widget.section == _Section.familyHistory
                        ? null
                        : item.subtitle;
                    final tile = Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: BodylineColors.surface,
                        borderRadius:
                            BorderRadius.circular(BodylineRadii.cardSmall),
                        border: Border.all(color: BodylineColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (subtitle != null && subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              color: BodylineColors.inkSubtle,
                              size: 20,
                            ),
                            onSelected: (action) async {
                              if (action == 'edit') {
                                await _editItem(item);
                              } else if (action == 'delete') {
                                await _deleteItem(item);
                              } else if (action == 'open' &&
                                  widget.section == _Section.surgeries) {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ProcedureDetailScreen(
                                      store: widget.store,
                                      item: item,
                                      onChanged: () {
                                        widget.onChanged();
                                        _load();
                                      },
                                    ),
                                  ),
                                );
                                await _load();
                              }
                            },
                            itemBuilder: (_) => [
                              if (widget.section == _Section.surgeries)
                                const PopupMenuItem(
                                  value: 'open',
                                  child: Text('Open'),
                                ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                    return tile;
                  },
                );

    if (widget.embedded) {
      return Material(
        color: BodylineColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add',
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: BodylineColors.divider),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: FloatingActionButton(
        heroTag: 'profile-section-add-fab',
        onPressed: _add,
        tooltip: 'Add',
        backgroundColor: BodylineColors.teal,
        foregroundColor: BodylineColors.isDark
            ? const Color(0xFF04201C)
            : Colors.white,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: body,
    );
  }
  Future<void> _editItem(MedicalItem item) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _AddMedicalDialog(
        section: widget.section,
        initial: item,
      ),
    );
    if (result == null) return;
    switch (widget.section) {
      case _Section.conditions:
        await widget.store.updateCondition(id: item.id, name: result['name']!);
      case _Section.medications:
        await widget.store.updateMedication(
          id: item.id,
          name: result['name']!,
          kind: result['kind'] ?? item.kind ?? 'other',
          strength: result['extra1'],
          instructions: result['extra2'],
        );
      case _Section.allergies:
        await widget.store.updateAllergy(
          id: item.id,
          substance: result['name']!,
          reaction: result['extra1'],
          severity: result['extra2'],
        );
      case _Section.vaccinations:
        await widget.store.updateImmunization(
          id: item.id,
          vaccine: result['name']!,
          givenOn: result['extra1'],
        );
      case _Section.surgeries:
        await widget.store.updateProcedure(
          id: item.id,
          name: result['name']!,
          performedOn: result['extra1'],
        );
      case _Section.familyHistory:
        await widget.store.updateFamilyHistory(
          id: item.id,
          conditionName: result['name']!,
          relation: result['extra1'] ?? '',
        );
      case _Section.emergency:
        await widget.store.updateEmergencyContact(
          id: item.id,
          name: result['name']!,
          relation: result['extra1'],
          phone: result['extra2'],
        );
    }
    widget.onChanged();
    await _load();
  }

  Future<void> _deleteItem(MedicalItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Remove "${item.title}" from this profile?'),
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
    switch (widget.section) {
      case _Section.conditions:
        await widget.store.softDeleteCondition(item.id);
      case _Section.medications:
        await widget.store.softDeleteMedication(item.id);
      case _Section.allergies:
        await widget.store.softDeleteAllergy(item.id);
      case _Section.vaccinations:
        await widget.store.softDeleteImmunization(item.id);
      case _Section.surgeries:
        await widget.store.softDeleteProcedure(item.id);
      case _Section.familyHistory:
        await widget.store.softDeleteFamilyHistory(item.id);
      case _Section.emergency:
        await widget.store.softDeleteEmergencyContact(item.id);
    }
    widget.onChanged();
    await _load();
  }

  Future<void> _add() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _AddMedicalDialog(section: widget.section),
    );
    if (result == null) return;

    switch (widget.section) {
      case _Section.conditions:
        await widget.store.addCondition(
          profileId: pid,
          name: result['name']!,
        );
      case _Section.medications:
        final medId = await widget.store.addMedication(
          profileId: pid,
          name: result['name']!,
          kind: result['kind'] ?? 'other',
          strength: result['extra1'],
          instructions: result['extra2'],
        );
        final timesRaw = result['times'];
        if (timesRaw != null && timesRaw.trim().isNotEmpty) {
          final times = timesRaw
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (times.isNotEmpty) {
            await widget.store.addMedicationSchedule(
              medicationId: medId,
              times: times,
            );
            await ReminderNotifications.instance.ensurePermission();
            final schedules =
                await widget.store.listAllMedicationSchedules();
            await ReminderNotifications.instance
                .rescheduleAllDoses(schedules);
          }
        }
      case _Section.allergies:
        await widget.store.addAllergy(
          profileId: pid,
          substance: result['name']!,
          reaction: result['extra1'],
          severity: result['extra2'],
        );
      case _Section.vaccinations:
        await widget.store.addImmunization(
          profileId: pid,
          vaccine: result['name']!,
          givenOn: result['extra1'],
        );
      case _Section.surgeries:
        final procId = await widget.store.addProcedure(
          profileId: pid,
          name: result['name']!,
          performedOn: result['extra1'],
        );
        if (!mounted) return;
        final attach = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Attach treatment file?'),
            content: const Text(
              'Optional — add a discharge note, operative summary, or photo (PDF or image) to open from this device later.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Skip'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Attach'),
              ),
            ],
          ),
        );
        if (attach == true) {
          final files = await pickClinicalFiles();
          await attachPendingFiles(
            store: widget.store,
            ownerType: 'procedure',
            ownerId: procId,
            files: files,
          );
        }
      case _Section.familyHistory:
        await widget.store.addFamilyHistory(
          profileId: pid,
          relation: result['extra1'] ?? '',
          conditionName: result['name']!,
        );
      case _Section.emergency:
        await widget.store.addEmergencyContact(
          profileId: pid,
          name: result['name']!,
          relation: result['extra1'],
          phone: result['extra2'],
        );
    }
    widget.onChanged();
    await _load();
  }
}

class _AddMedicalDialog extends StatefulWidget {
  const _AddMedicalDialog({required this.section, this.initial});
  final _Section section;
  final MedicalItem? initial;

  @override
  State<_AddMedicalDialog> createState() => _AddMedicalDialogState();
}

class _AddMedicalDialogState extends State<_AddMedicalDialog> {
  late final TextEditingController _name;
  late final TextEditingController _extra1;
  late final TextEditingController _extra2;
  final _times = TextEditingController();
  late String _kind;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.title ?? '');
    _kind = i?.kind ?? 'allopathic';
    String e1 = '';
    String e2 = '';
    if (i != null) {
      switch (widget.section) {
        case _Section.medications:
          e1 = i.strength ?? '';
          e2 = i.instructions ?? '';
        case _Section.allergies:
        case _Section.emergency:
          e1 = i.subtitle?.split(' · ').first ?? '';
          e2 = (i.subtitle?.contains(' · ') == true)
              ? i.subtitle!.split(' · ').skip(1).join(' · ')
              : '';
        case _Section.vaccinations:
        case _Section.surgeries:
          e1 = i.subtitle ?? '';
        case _Section.familyHistory:
          e1 = i.subtitle ?? '';
        case _Section.conditions:
          break;
      }
    }
    _extra1 = TextEditingController(text: e1);
    _extra2 = TextEditingController(text: e2);
  }

  @override
  void dispose() {
    _name.dispose();
    _extra1.dispose();
    _extra2.dispose();
    _times.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (primary, e1, e2) = switch (widget.section) {
      _Section.conditions => ('Condition name', null, null),
      _Section.medications => ('Name', 'Strength / form', 'Instructions'),
      _Section.allergies => ('Substance', 'Reaction', 'Severity'),
      _Section.vaccinations => ('Vaccine', 'Given on (YYYY-MM-DD)', null),
      _Section.surgeries => ('Procedure', 'Performed on (YYYY-MM-DD)', null),
      _Section.familyHistory => ('Condition', 'Relation', null),
      _Section.emergency => ('Name', 'Relation', 'Phone'),
    };

    return AlertDialog(
      title: Text(widget.initial == null ? 'Add' : 'Edit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.section == _Section.medications) ...[
              DropdownButtonFormField<String>(
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
            ],
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: primary),
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
            ),
            if (e1 != null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _extra1,
                decoration: InputDecoration(labelText: e1),
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
            if (e2 != null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _extra2,
                decoration: InputDecoration(labelText: e2),
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
            if (widget.section == _Section.medications) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _times,
                decoration: const InputDecoration(
                  labelText: 'Times (optional)',
                  hintText: '08:00, 20:00',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            if (widget.section == _Section.familyHistory &&
                _extra1.text.trim().isEmpty) {
              return;
            }
            Navigator.pop(context, {
              'name': name,
              if (widget.section == _Section.medications) 'kind': _kind,
              if (_extra1.text.trim().isNotEmpty)
                'extra1': _extra1.text.trim(),
              if (_extra2.text.trim().isNotEmpty)
                'extra2': _extra2.text.trim(),
              if (_times.text.trim().isNotEmpty)
                'times': _times.text.trim(),
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 4.0;
      const gap = 3.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class ProcedureDetailScreen extends StatelessWidget {
  const ProcedureDetailScreen({
    super.key,
    required this.store,
    required this.item,
    required this.onChanged,
  });

  final LocalStore store;
  final MedicalItem item;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (item.subtitle?.isNotEmpty == true)
            Text(item.subtitle!, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          ClinicalAttachmentsSection(
            store: store,
            ownerType: 'procedure',
            ownerId: item.id,
            onChanged: onChanged,
            title: 'Treatment files',
            emptyHint:
                'Optional — attach discharge notes, operative summary, or a photo to open or share from this device.',
          ),
        ],
      ),
    );
  }
}
