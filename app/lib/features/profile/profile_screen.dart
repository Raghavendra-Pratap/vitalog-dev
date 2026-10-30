import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../security/app_lock.dart';
import '../../theme/theme_controller.dart';
import '../../sync/lan_sync_service.dart';
// import '../doctor/doctor_summary.dart'; // Doctor summary hidden for now
import '../medicines/medicines_screen.dart';
import '../../notifications/reminder_notifications.dart';
import '../../widgets/clinical_attachments.dart';
import '../../data/models.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../medicines/dose_wait_header_chip.dart';
import '../../widgets/bodyline_dialog.dart';
import '../settings/settings_screen.dart';
import '../profiles/edit_profile_sheet.dart';
import 'medical_timeline.dart';

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
  List<MedicalTimelineEvent> _timelineEvents = [];

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
        _timelineEvents = [];
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
    final timeline = await loadMedicalTimelineEvents(widget.store, pid);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(map);
      _timelineEvents = timeline;
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

  String? _sexLabel(String? sex) {
    switch ((sex ?? '').trim().toLowerCase()) {
      case 'm':
      case 'male':
        return 'Male';
      case 'f':
      case 'female':
        return 'Female';
      case 'other':
        return 'Other';
      default:
        return null;
    }
  }

  Widget _mobileProfileCard(ProfileRecord profile) {
    final identityStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: BodylineColors.inkSubtle,
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Same width as the third fact tile (blood · height · weight).
          final tileW = (constraints.maxWidth - 16) / 3;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: _editDetails,
                borderRadius: BorderRadius.circular(12),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            profileRelationLabel(profile.relation),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: tileW,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _sexLabel(profile.sex) ?? 'Sex not set',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: identityStyle,
                          ),
                          Text(
                            () {
                              final age = (profile.dob == null ||
                                      profile.dob!.isEmpty)
                                  ? null
                                  : _ageFromDob(profile.dob!);
                              return age == null ? 'Age not set' : '$age yrs';
                            }(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: identityStyle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: BodylineColors.divider),
              const SizedBox(height: 12),
              _profileFactsGrid(profile),
            ],
          );
        },
      ),
    );
  }

  Widget _profileFactsGrid(ProfileRecord profile) {
    final w = _latestWeight(profile.id);
    final hObs = _latestHeightObs(profile.id);
    final heightCm = _effectiveHeightCm(profile);
    final heightVal = (heightCm != null)
        ? '${heightCm.toStringAsFixed(heightCm == heightCm.roundToDouble() ? 0 : 1)}\u00A0cm'
        : '—';
    final weightVal = () {
      if (w == null) return '—';
      final unit = w.unitReported.trim().isEmpty ? 'kg' : w.unitReported.trim();
      final n = w.valueNum ?? double.tryParse(w.valueReported.trim());
      if (n != null) {
        final s = (n == n.roundToDouble())
            ? n.toStringAsFixed(0)
            : n.toStringAsFixed(1);
        return '$s\u00A0$unit';
      }
      final raw = w.valueReported.trim();
      return raw.isEmpty ? '—' : '$raw\u00A0$unit';
    }();
    final bloodEmpty =
        profile.bloodGroup == null || profile.bloodGroup!.isEmpty;
    Widget cell(Widget child) => Expanded(child: child);
    return Row(
      children: [
        cell(
          _miniStat(
            'Blood group',
            bloodEmpty ? '—' : profile.bloodGroup!,
            bloodEmpty ? 'tap to set' : 'set by you',
            onTap: () => _setBloodGroup(profile),
          ),
        ),
        const SizedBox(width: 8),
        cell(
          _miniStat(
            'Height',
            heightVal,
            _heightSub(profile, hObs, heightCm),
            onTap: () => _setHeight(profile),
          ),
        ),
        const SizedBox(width: 8),
        cell(
          _miniStat(
            'Weight',
            weightVal,
            _weightSub(w),
            onTap: () => _setWeight(profile),
          ),
        ),
      ],
    );
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

    return Stack(
      children: [
        SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          widget.desktop ? 32 : 20,
          widget.desktop ? 8 : 12,
          widget.desktop ? 32 : 20,
          widget.desktop ? 24 : 100,
        ),
        children: [
          if (!widget.desktop)
            TabPageHeader(
              title: 'Health profile',
              trailing: [
                IconButton(
                  tooltip: 'Settings',
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
          if (profile != null) ...[
            const SizedBox(height: 8),
            _mobileProfileCard(profile),
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
            Text(
              'Medical timeline',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Newest first · conditions, medicines, vaccinations, surgeries and visits',
              style: TextStyle(fontSize: 12, color: BodylineColors.inkSubtle),
            ),
            const SizedBox(height: 12),
            MedicalTimelineView(
              events: _timelineEvents,
              onEventTap: _onTimelineEventTap,
            ),
          ],
        ],
      ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'profile-health-add',
            tooltip: 'Add',
            onPressed: _openSectionPicker,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }



  Future<void> _openSettings() async {
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
          desktop: widget.desktop,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _editDetails() async {
    final profile = _profile;
    if (profile == null) return;
    final ok = await showEditProfileDialog(
      context: context,
      store: widget.store,
      profile: profile,
    );
    if (ok) {
      widget.onChanged();
      await _reload();
    }
  }


  void _onTimelineEventTap(MedicalTimelineEvent e) {
    switch (e.category) {
      case MedicalTimelineCategory.conditions:
        _openSection(_Section.conditions, 'Conditions');
      case MedicalTimelineCategory.medicines:
        if (_openCareTab(6)) return;
        _openSection(_Section.medications, 'Medicines & remedies');
      case MedicalTimelineCategory.vaccinations:
        _openSection(_Section.vaccinations, 'Vaccinations');
      case MedicalTimelineCategory.surgeries:
        _openSection(_Section.surgeries, 'Surgeries & procedures');
      case MedicalTimelineCategory.visits:
        if (_openCareTab(10)) return;
        // Fallback: Care visits live in Care nav on desktop.
        break;
    }
  }

  Widget _desktopTimelineBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: DesktopLayout.testsMasterCol,
          child: ListView(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                decoration: BoxDecoration(
                  color: BodylineColors.surface,
                  borderRadius: BorderRadius.circular(BodylineRadii.card),
                  border: Border.all(color: BodylineColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Medical history',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Used in your doctor summary and emergency card.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: BodylineColors.inkSubtle),
                    ),
                    const SizedBox(height: 12),
                    _historyBlock(
                      _Section.conditions,
                      'Conditions',
                      Icons.healing_outlined,
                      '+ Add condition',
                    ),
                    _historyBlock(
                      _Section.allergies,
                      'Allergies',
                      Icons.warning_amber_outlined,
                      '+ Add allergy',
                    ),
                    _historyBlock(
                      _Section.vaccinations,
                      'Vaccinations',
                      Icons.vaccines_outlined,
                      '+ Add vaccination',
                    ),
                    _historyBlock(
                      _Section.surgeries,
                      'Surgeries & procedures',
                      Icons.local_hospital_outlined,
                      '+ Add surgery',
                    ),
                    _historyBlock(
                      _Section.familyHistory,
                      'Family history',
                      Icons.account_tree_outlined,
                      '+ Add note',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DesktopLayout.mainGap),
              _richSection(
                _Section.emergency,
                'Emergency contacts',
                (n) => n == 1 ? '1 contact' : '$n contacts',
                '+ Add contact',
              ),
            ],
          ),
        ),
        const SizedBox(width: DesktopLayout.mainGap),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            decoration: BoxDecoration(
              color: BodylineColors.paper,
              borderRadius: BorderRadius.circular(BodylineRadii.card),
              border: Border.all(color: BodylineColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Medical timeline',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Newest first · conditions, medicines, vaccinations, surgeries and visits',
                  style: TextStyle(
                    fontSize: 12,
                    color: BodylineColors.inkSubtle,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      MedicalTimelineView(
                        events: _timelineEvents,
                        onEventTap: _onTimelineEventTap,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopProfile(ProfileRecord? profile) {
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
          Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            decoration: BoxDecoration(
              color: BodylineColors.surface,
              borderRadius: BorderRadius.circular(BodylineRadii.card),
              border: Border.all(color: BodylineColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
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
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 168),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.name ?? 'Profile',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontSize: 24),
                      ),
                      Text(
                        profile == null ? '' : _metaLine(profile),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                            ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: profile == null ? null : _editDetails,
                        style: TextButton.styleFrom(
                          foregroundColor: BodylineColors.tealDark,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Edit details'),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _profileSummaryStrip(profile),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _desktopTimelineBody(),
          ),
        ],
      ),
    );
  }

  Widget _historyBlock(
    _Section section,
    String title,
    IconData icon,
    String addLabel,
  ) {
    final items = _items[section] ?? const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: BodylineColors.tealDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _openSection(section, title),
                style: TextButton.styleFrom(
                  foregroundColor: BodylineColors.tealDark,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(addLabel),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            Text(
              'None yet',
              style: TextStyle(
                fontSize: 13,
                color: BodylineColors.inkSubtle,
              ),
            )
          else
            for (final item in items.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
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
                            fontSize: 12,
                            color: BodylineColors.inkSubtle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          if (items.length > 4)
            Text(
              '+${items.length - 4} more',
              style: TextStyle(
                fontSize: 12,
                color: BodylineColors.inkSubtle,
              ),
            ),
          const Divider(height: 18),
        ],
      ),
    );
  }


  ObservationRecord? _latestVital(String? profileId, String code) {
    if (profileId == null) return null;
    return widget.store.latestObservation(
      profileId: profileId,
      parameterCode: code,
    );
  }

  ObservationRecord? _latestWeight(String? profileId) =>
      _latestVital(profileId, 'weight');

  ObservationRecord? _latestHeightObs(String? profileId) =>
      _latestVital(profileId, 'height');

  /// Prefer newest height observation; fall back to profile field.
  double? _effectiveHeightCm(ProfileRecord? profile) {
    final fromObs = _latestHeightObs(profile?.id);
    if (fromObs != null) {
      final cm = LocalStore.heightCmFromObservation(fromObs);
      if (cm != null && cm >= 50 && cm <= 280) return cm;
    }
    final h = profile?.heightCm;
    if (h != null && h > 0) return h;
    return null;
  }

  String _vitalWhenSub(ObservationRecord? o, {String empty = 'tap to set'}) {
    if (o == null) return empty;
    final now = DateTime.now();
    final sameDay = o.observedAt.year == now.year &&
        o.observedAt.month == now.month &&
        o.observedAt.day == now.day;
    final when = sameDay
        ? 'today'
        : DateFormat('MMM yyyy').format(o.observedAt);
    final src = o.source;
    final phone = src == 'health_connect' || src == 'healthkit';
    if (phone) return '$when · phone';
    if (src == 'manual') return '$when · manual';
    if (o.reportId.isNotEmpty) return '$when · report';
    return when;
  }

  String _weightSub(ObservationRecord? w) =>
      _vitalWhenSub(w, empty: 'tap to set');

  String _heightSub(ProfileRecord? profile, ObservationRecord? hObs, double? cm) {
    if (cm == null) return 'tap to set';
    if (hObs != null) return _vitalWhenSub(hObs);
    return 'set by you';
  }

  ({String value, String sub}) _bmiTile(
    ProfileRecord? profile,
    ObservationRecord? w,
  ) {
    final h = _effectiveHeightCm(profile);
    final kg = w?.valueNum ?? double.tryParse(w?.valueReported ?? '');
    if (h == null || h <= 0 || kg == null || kg <= 0) {
      if (h == null && kg == null) {
        return (value: '—', sub: 'needs height + weight');
      }
      if (h == null) return (value: '—', sub: 'needs height');
      return (value: '—', sub: 'needs weight');
    }
    final m = h / 100.0;
    final bmi = kg / (m * m);
    final value = bmi.toStringAsFixed(1);
    if (bmi >= 23) {
      return (value: value, sub: 'above cut-off (23)');
    }
    return (value: value, sub: 'vs cut-off 23');
  }

  Widget _profileSummaryStrip(ProfileRecord? profile) {
    final w = _latestWeight(profile?.id);
    final hObs = _latestHeightObs(profile?.id);
    final heightCm = _effectiveHeightCm(profile);
    final bmi = _bmiTile(profile, w);
    final heightVal = (heightCm != null)
        ? '${heightCm.toStringAsFixed(heightCm == heightCm.roundToDouble() ? 0 : 1)}\u00A0cm'
        : '—';
    final weightVal = () {
      if (w == null) return '—';
      final unit = w.unitReported.trim().isEmpty ? 'kg' : w.unitReported.trim();
      final n = w.valueNum ?? double.tryParse(w.valueReported.trim());
      if (n != null) {
        final s = (n == n.roundToDouble())
            ? n.toStringAsFixed(0)
            : n.toStringAsFixed(1);
        return '$s\u00A0$unit';
      }
      final raw = w.valueReported.trim();
      return raw.isEmpty ? '—' : '$raw\u00A0$unit';
    }();

    // Equal tile width — sized for longest footer ("above cut-off (23)").
    const tileW = 128.0;
    const gap = 8.0;
    Widget tile(Widget child) => SizedBox(width: tileW, child: child);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        tile(
          _miniStat(
            'Blood group',
            (profile?.bloodGroup == null || profile!.bloodGroup!.isEmpty)
                ? '—'
                : profile.bloodGroup!,
            (profile?.bloodGroup == null || profile!.bloodGroup!.isEmpty)
                ? 'tap to set'
                : 'set by you',
            onTap: profile == null ? null : () => _setBloodGroup(profile),
          ),
        ),
        const SizedBox(width: gap),
        tile(
          _miniStat(
            'Height',
            heightVal,
            _heightSub(profile, hObs, heightCm),
            onTap: profile == null ? null : () => _setHeight(profile),
          ),
        ),
        const SizedBox(width: gap),
        tile(
          _miniStat(
            'Weight',
            weightVal,
            _weightSub(w),
            onTap: profile == null ? null : () => _setWeight(profile),
          ),
        ),
        const SizedBox(width: gap),
        tile(
          _miniStat(
            'BMI',
            bmi.value,
            bmi.sub,
          ),
        ),
      ],
    );
  }

  Future<void> _setHeight(ProfileRecord profile) async {
    final ctrl = TextEditingController(
      text: profile.heightCm == null
          ? ''
          : (profile.heightCm == profile.heightCm!.roundToDouble()
              ? profile.heightCm!.toStringAsFixed(0)
              : profile.heightCm!.toString()),
    );
    final ok = await showBodylineDialog<bool>(
      context: context,
      title: 'Height',
      subtitle: 'Centimetres · also saved with your reports on this device.',
      showLockup: false,
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Height (cm)',
          hintText: 'e.g. 172',
        ),
      ),
      actionsBuilder: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: BodylineColors.teal),
          child: const Text('Save'),
        ),
      ],
    );
    final raw = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    if (raw.isEmpty) {
      await widget.store.updateProfile(id: profile.id, clearHeightCm: true);
    } else {
      final v = double.tryParse(raw);
      if (v == null || v < 50 || v > 280) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a height between 50 and 280 cm.'),
          ),
        );
        return;
      }
      await widget.store.updateProfile(id: profile.id, heightCm: v);
      final reported = v == v.roundToDouble()
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(1);
      await widget.store.recordVital(
        profileId: profile.id,
        parameterCode: 'height',
        parameterName: 'Height',
        valueReported: reported,
        unitReported: 'cm',
        title: 'Height',
      );
    }
    widget.onChanged();
    await _reload();
  }

  Future<void> _setWeight(ProfileRecord profile) async {
    final current = _latestWeight(profile.id);
    final ctrl = TextEditingController(
      text: () {
        if (current == null) return '';
        final n = current.valueNum ??
            double.tryParse(current.valueReported.trim());
        if (n == null) return current.valueReported.trim();
        return n == n.roundToDouble()
            ? n.toStringAsFixed(0)
            : n.toStringAsFixed(1);
      }(),
    );
    final ok = await showBodylineDialog<bool>(
      context: context,
      title: 'Weight',
      subtitle: 'Kilograms · also saved with your reports on this device.',
      showLockup: false,
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Weight (kg)',
          hintText: 'e.g. 72.5',
        ),
      ),
      actionsBuilder: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: BodylineColors.teal),
          child: const Text('Save'),
        ),
      ],
    );
    final raw = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    if (raw.isEmpty) return;
    final v = double.tryParse(raw);
    if (v == null || v < 15 || v > 400) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a weight between 15 and 400 kg.'),
        ),
      );
      return;
    }
    final reported = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
    await widget.store.recordVital(
      profileId: profile.id,
      parameterCode: 'weight',
      parameterName: 'Weight',
      valueReported: reported,
      unitReported: 'kg',
      title: 'Weight',
    );
    widget.onChanged();
    await _reload();
  }

  Widget _miniStat(
    String label,
    String value,
    String sub, {
    VoidCallback? onTap,
  }) {
    final child = Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: BodylineColors.chip,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: BodylineColors.inkSubtle,
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: BodylineColors.ink,
                  height: 1.15,
                ),
              ),
            ),
          ),
          Text(
            sub,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: BodylineColors.inkSubtle,
            ),
          ),
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

  List<({_Section section, String title, IconData icon})> _healthSections() => [
        (
          section: _Section.conditions,
          title: 'Conditions',
          icon: Icons.healing_outlined,
        ),
        (
          section: _Section.allergies,
          title: 'Allergies',
          icon: Icons.warning_amber_outlined,
        ),
        (
          section: _Section.vaccinations,
          title: 'Vaccinations',
          icon: Icons.vaccines_outlined,
        ),
        (
          section: _Section.surgeries,
          title: 'Surgeries & procedures',
          icon: Icons.local_hospital_outlined,
        ),
        (
          section: _Section.familyHistory,
          title: 'Family history',
          icon: Icons.account_tree_outlined,
        ),
        (
          section: _Section.emergency,
          title: 'Emergency contact',
          icon: Icons.contact_phone_outlined,
        ),
      ];

  Future<void> _openSectionPicker() async {
    final tiles = _healthSections();
    final picked = await showModalBottomSheet<_Section>(
      context: context,
      backgroundColor: BodylineColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Text(
                    'Add',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                for (final tile in tiles)
                  ListTile(
                    leading: Icon(tile.icon, color: BodylineColors.tealDark),
                    title: Text(tile.title),
                    onTap: () => Navigator.pop(ctx, tile.section),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    final title = tiles.firstWhere((tile) => tile.section == picked).title;
    await _openSection(picked, title);
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
