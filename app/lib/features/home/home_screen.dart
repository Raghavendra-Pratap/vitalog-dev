import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../desktop.dart';
import '../../data/attention_prefs.dart';
import '../../data/body_panel_prefs.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../../widgets/report_title.dart';
import '../../widgets/body_map.dart';
import '../family/family_sheet.dart';
import 'customize_attention_sheet.dart';
import 'needs_attention_screen.dart';
import 'customize_body_sheet.dart';
import '../organ/organ_detail_screen.dart';
import '../records/report_detail_screen.dart';
import '../../widgets/trend_panel.dart';
import '../presenter/presenter_setup_screen.dart';
import '../visits/care_screen.dart';
import '../visits/reminders_screen.dart';
import '../today/today_screen.dart';
import '../insights/patterns_screen.dart';
import '../medicines/medicines_screen.dart';
import '../medicines/dose_wait_screen.dart';
import '../medicines/dose_wait_controller.dart';
import '../doctor/doctors_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.onChanged,
    this.desktop = false,
    this.onAddReport,
    this.onSeeAllTests,
  });

  final LocalStore store;
  final VoidCallback onChanged;
  final bool desktop;
  final VoidCallback? onAddReport;
  final VoidCallback? onSeeAllTests;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, ObservationFlag?> _flags = {};
  List<OrganSummary> _allOrgans = [];
  List<OrganSummary> _organs = [];
  List<ReminderRecord> _due = [];
  BodyPanelPrefs _bodyPrefs = BodyPanelPrefs(order: const [], hidden: {});
  AttentionPrefs _attentionPrefs = AttentionPrefs(hidden: {});
  int _needsTab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  Future<void> _load() async {
    final flags = await widget.store.organFlags();
    final organs = await widget.store.organSummaries();
    final prefs = await BodyPanelPrefs.load(
      profileId: widget.store.activeProfileId,
      catalogCodes: [for (final o in organs) o.code],
    );
    final attention = await AttentionPrefs.load(widget.store.activeProfileId);
    List<ReminderRecord> due = const [];
    final pid = widget.store.activeProfileId;
    if (pid != null) {
      due = await widget.store.dueReminders(pid);
    }
    if (!mounted) return;
    setState(() {
      _flags = flags;
      _allOrgans = organs;
      _bodyPrefs = prefs;
      _attentionPrefs = attention;
      _organs = prefs.applyToSummaries(organs, codeOf: (o) => o.code);
      _due = due;
      final visible = [
        for (final o in _flaggedLatest)
          if (!attention.hidden.contains(o.parameterCode)) o,
      ];
      if (visible.isEmpty) {
        _needsTab = 0;
      } else if (_needsTab >= visible.length) {
        _needsTab = visible.length - 1;
      }
    });
  }

  Future<void> _customizeBody() async {
    final next = await showCustomizeBodySheet(
      context: context,
      prefs: _bodyPrefs,
      allOrgans: _allOrgans,
    );
    if (next == null || !mounted) return;
    final pid = widget.store.activeProfileId;
    if (pid != null) await next.save(pid);
    setState(() {
      _bodyPrefs = next;
      _organs = next.applyToSummaries(_allOrgans, codeOf: (o) => o.code);
    });
  }

  Future<void> _customizeAttention() async {
    final next = await showCustomizeAttentionSheet(
      context: context,
      prefs: _attentionPrefs,
      flaggedLatest: _flaggedLatest,
    );
    if (next == null || !mounted) return;
    final pid = widget.store.activeProfileId;
    if (pid != null) await next.save(pid);
    setState(() {
      _attentionPrefs = next;
      final visible = _needsAttention;
      if (visible.isEmpty) {
        _needsTab = 0;
      } else if (_needsTab >= visible.length) {
        _needsTab = visible.length - 1;
      }
    });
  }

  ProfileRecord? get _profile {
    final id = widget.store.activeProfileId;
    for (final p in widget.store.profiles) {
      if (p.id == id) return p;
    }
    return widget.store.profiles.isEmpty ? null : widget.store.profiles.first;
  }

  List<ObservationRecord> get _flaggedLatest {
    final id = widget.store.activeProfileId;
    final flagged = widget.store.observations
        .where((o) =>
            o.profileId == id &&
            o.flag != null &&
            o.flag != ObservationFlag.normal)
        .toList()
      ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
    final seen = <String>{};
    final out = <ObservationRecord>[];
    for (final o in flagged) {
      if (seen.add(o.parameterCode)) out.add(o);
    }
    return out;
  }

  List<ObservationRecord> get _needsAttention => [
        for (final o in _flaggedLatest)
          if (!_attentionPrefs.hidden.contains(o.parameterCode)) o,
      ];

  DateTime? get _latestDate {
    final id = widget.store.activeProfileId;
    DateTime? latest;
    for (final o in widget.store.observations) {
      if (o.profileId != id) continue;
      if (latest == null || o.observedAt.isAfter(latest)) latest = o.observedAt;
    }
    return latest;
  }

  List<ReportRecord> get _recentReports {
    return widget.store.reports
        .where((r) => r.profileId == widget.store.activeProfileId)
        .toList()
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
  }


  Widget _todayPatternsRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TodayScreen(
                      store: widget.store,
                      onChanged: widget.onChanged,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.today_outlined),
              label: const Text('Today'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PatternsScreen(store: widget.store),
                  ),
                );
              },
              icon: const Icon(Icons.insights_outlined),
              label: const Text('Patterns'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    BodylineColors.syncFrom(context);
    if (widget.desktop) return _buildDesktop(context);
    return _buildMobile(context);
  }

  Widget _buildMobile(BuildContext context) {
    final profile = _profile;
    final needs = _needsAttention;
    final latest = _latestDate;
    final initial = (profile?.name.isNotEmpty == true)
        ? profile!.name[0].toUpperCase()
        : '?';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          _todayPatternsRow(context),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => showFamilySheet(
                    context: context,
                    store: widget.store,
                    onChanged: () {
                      widget.onChanged();
                      _load();
                    },
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: BodylineColors.teal,
                          child: Text(
                            initial,
                            style: TextStyle(
                              color: BodylineColors.onInk,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Viewing',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      profile?.name ?? 'Profile',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  const Icon(Icons.expand_more, size: 18),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (profile != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PresenterSetupScreen(store: widget.store),
                      ),
                    );
                  },
                  icon: const Icon(Icons.present_to_all_outlined, size: 18),
                  label: const Text('Present'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _yourBodyCard(latest, mapBesideList: true),
          const SizedBox(height: 16),
          _careShortcuts(),
          const SizedBox(height: 12),
          _needsAttentionEntry(needs),
          if (_due.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Due now', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final r in _due) _reminderTile(r),
          ],
        ],
      ),
    );
  }

  Widget _careShortcuts() {
    final items = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: Icons.event_note_outlined,
        label: 'Visit',
        onTap: () => _openCarePage(
          CareScreen(
            store: widget.store,
            onChanged: () {
              widget.onChanged();
              _load();
            },
            includeReminders: false,
          ),
        ),
      ),
      (
        icon: Icons.medical_information_outlined,
        label: 'Doctor',
        onTap: () => _openCarePage(
          DoctorsScreen(
            store: widget.store,
            onChanged: () {
              widget.onChanged();
              _load();
            },
          ),
        ),
      ),
      (
        icon: Icons.notifications_none,
        label: 'Reminder',
        onTap: () => _openCarePage(
          RemindersScreen(
            store: widget.store,
            onChanged: () {
              widget.onChanged();
              _load();
            },
          ),
        ),
      ),
      (
        icon: Icons.medication_outlined,
        label: 'Medicine',
        onTap: () => _openCarePage(
          MedicinesScreen(
            store: widget.store,
            onChanged: () {
              widget.onChanged();
              _load();
            },
          ),
        ),
      ),
      (
        icon: Icons.hourglass_bottom,
        label: 'Timer',
        onTap: () => _openCarePage(
          const DoseWaitScreen(mode: DoseWaitMode.countdown),
        ),
      ),
      (
        icon: Icons.timer_outlined,
        label: 'Stopwatch',
        onTap: () => _openCarePage(
          const DoseWaitScreen(mode: DoseWaitMode.stopwatch),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Care',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final item in items.take(3))
              Expanded(child: _careShortcutTile(item.icon, item.label, item.onTap)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final item in items.skip(3))
              Expanded(child: _careShortcutTile(item.icon, item.label, item.onTap)),
          ],
        ),
      ],
    );
  }

  Widget _careShortcutTile(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        child: InkWell(
          borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
              border: Border.all(color: BodylineColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: BodylineColors.ink),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCarePage(Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted) _load();
  }

    Widget _needsAttentionEntry(List<ObservationRecord> needs) {
    final subtitle = needs.isEmpty
        ? 'Nothing flagged right now'
        : needs.length == 1
            ? '1 flagged result'
            : '${needs.length} flagged results';
    return Material(
      color: BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NeedsAttentionScreen(
                store: widget.store,
                onChanged: () {
                  widget.onChanged();
                  _load();
                },
              ),
            ),
          );
          if (mounted) _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
            border: Border.all(color: BodylineColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: needs.isEmpty
                      ? BodylineColors.chip
                      : BodylineColors.orange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  needs.isEmpty
                      ? Icons.check_rounded
                      : Icons.priority_high_rounded,
                  size: 20,
                  color: needs.isEmpty
                      ? BodylineColors.tealDark
                      : BodylineColors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Needs attention',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                    ),
                    Text(
                      subtitle,
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
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final needs = _needsAttention;
    final latest = _latestDate;
    final reports = _recentReports.take(4).toList();

    // Tablet landscape: natural card heights for Your body + Needs attention.
    // Scroll to see Upcoming / Recent — do not stretch top cards to ~78% viewport.
    if (!isDesktopPlatform) {
      const topH = 520.0;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          DesktopLayout.mainPaddingH,
          12,
          DesktopLayout.mainPaddingH,
          DesktopLayout.mainPaddingV,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: topH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: DesktopLayout.overviewBodyCol,
                    child: _yourBodyCard(latest, mapBesideList: false),
                  ),
                  const SizedBox(width: DesktopLayout.mainGap),
                  Expanded(child: _desktopNeedsCard(needs)),
                ],
              ),
            ),
            const SizedBox(height: DesktopLayout.mainGap),
            SizedBox(
              height: 260,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _upcomingCard()),
                  const SizedBox(width: DesktopLayout.mainGap),
                  Expanded(child: _recentRecordsCard(reports)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesktopLayout.mainPaddingH,
        12,
        DesktopLayout.mainPaddingH,
        DesktopLayout.mainPaddingV,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: DesktopLayout.overviewBodyCol,
            child: _yourBodyCard(latest, mapBesideList: false),
          ),
          const SizedBox(width: DesktopLayout.mainGap),
          Expanded(child: _desktopNeedsCard(needs)),
          const SizedBox(width: DesktopLayout.mainGap),
          SizedBox(
            width: DesktopLayout.overviewRailCol,
            child: Column(
              children: [
                Expanded(flex: 5, child: _upcomingCard()),
                const SizedBox(height: DesktopLayout.mainGap),
                Expanded(flex: 5, child: _recentRecordsCard(reports)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopNeedsCard(List<ObservationRecord> needs) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Needs attention',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: BodylineColors.inkSubtle,
                    ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Customize',
                onPressed: _customizeAttention,
                icon: const Icon(Icons.tune, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 4),
              if (needs.isNotEmpty)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < needs.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _needsTabChip(needs[i], i),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: needs.isEmpty
                ? Center(
                    child: Text(
                      _flaggedLatest.isEmpty
                          ? 'No flagged values. Add a report with the lab\u2019s printed range to see what needs attention.'
                          : 'All flagged tests are hidden. Tap Customize to show them again.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : TrendPanel(
                    key: ValueKey(needs[_needsTab.clamp(0, needs.length - 1)].parameterCode),
                    store: widget.store,
                    parameterCode:
                        needs[_needsTab.clamp(0, needs.length - 1)].parameterCode,
                    title: needs[_needsTab.clamp(0, needs.length - 1)].parameterName,
                    compact: true,
                    showHistory: false,
                    showRangeSelector: false,
                  ),
          ),
          if (widget.onSeeAllTests != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: widget.onSeeAllTests,
                style: TextButton.styleFrom(
                  foregroundColor: BodylineColors.tealDark,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'See all tests',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _needsTabChip(ObservationRecord o, int i) {
    final selected = i == _needsTab;
    final short = o.parameterName.split(' ').take(2).join(' ');
    final flag = switch (o.flag) {
      ObservationFlag.high ||
      ObservationFlag.criticalHigh ||
      ObservationFlag.abnormal =>
        'High',
      ObservationFlag.low || ObservationFlag.criticalLow => 'Low',
      _ => 'Out',
    };
    return Material(
      color: selected ? BodylineColors.ink : BodylineColors.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? BodylineColors.ink : BodylineColors.outlineSoft,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _needsTab = i),
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            '$short · $flag',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? BodylineColors.onInk : BodylineColors.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _upcomingCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Upcoming · family',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _due.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No reminders due. Add care reminders from Health profile.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: _due.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: BodylineColors.divider),
                    itemBuilder: (context, i) {
                      final r = _due[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: BodylineColors.tealTint,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                                color: BodylineColors.teal,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ReportTitleText(
                                    r.title,
                                      maxLines: 1,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Due ${DateFormat('d MMM').format(r.dueAt)}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
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

  Widget _recentRecordsCard(List<ReportRecord> reports) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Recent records',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: reports.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No reports yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: reports.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: BodylineColors.divider),
                    itemBuilder: (context, i) {
                      final r = reports[i];
                      final obs = widget.store.observations
                          .where((o) => o.reportId == r.id)
                          .toList();
                      final flagged = obs
                          .where((o) =>
                              o.flag != null &&
                              o.flag != ObservationFlag.normal)
                          .length;
                      return InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReportDetailScreen(
                                store: widget.store,
                                report: r,
                                onChanged: widget.onChanged,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ReportTitleText(
                                      r.title,
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      DateFormat('d MMM yyyy')
                                          .format(r.collectedAt),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: flagged > 0
                                      ? BodylineColors.orangeTint
                                      : BodylineColors.tealTint,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  flagged > 0
                                      ? '$flagged flagged'
                                      : 'In range',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: flagged > 0
                                        ? BodylineColors.orangeText
                                        : BodylineColors.tealDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _yourBodyCard(DateTime? latest, {required bool mapBesideList}) {
    final mapFlags = _bodyPrefs.mapFlags(_flags);
    final list = Column(
      children: [for (final organ in _organs) _organRow(organ)],
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Your body',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
              ),
              const Spacer(),
              if (latest != null && mapBesideList)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Latest: ${DateFormat('d MMM yyyy').format(latest)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              IconButton(
                tooltip: 'Customize',
                onPressed: _customizeBody,
                icon: const Icon(Icons.tune, size: 20),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (mapBesideList)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BodyMapView(flags: mapFlags, width: 180, height: 300),
                const SizedBox(width: 12),
                Expanded(child: list),
              ],
            )
          else ...[
            Center(
              child: BodyMapView(flags: mapFlags, width: 180, height: 300),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(child: list),
            ),
          ],
        ],
      ),
    );
  }


  Widget _surfaceBox({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        border: Border.all(color: BodylineColors.border),
      ),
      child: child,
    );
  }

  Widget _reminderTile(ReminderRecord r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _surfaceBox(
        child: Text(
          r.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }


  Widget _organRow(OrganSummary organ) {
    final color = switch (organ.flag) {
      null => BodylineColors.untested,
      ObservationFlag.normal => BodylineColors.teal,
      ObservationFlag.high ||
      ObservationFlag.criticalHigh ||
      ObservationFlag.abnormal =>
        BodylineColors.orange,
      ObservationFlag.low || ObservationFlag.criticalLow => BodylineColors.blue,
    };
    final statusColor = switch (organ.flag) {
      null => BodylineColors.inkSubtle,
      ObservationFlag.normal => BodylineColors.inkSubtle,
      ObservationFlag.high ||
      ObservationFlag.criticalHigh ||
      ObservationFlag.abnormal =>
        BodylineColors.orange,
      ObservationFlag.low || ObservationFlag.criticalLow => BodylineColors.blue,
    };

    return InkWell(
      onTap: () {
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => OrganDetailScreen(
                  store: widget.store,
                  systemCode: organ.code,
                  desktop: widget.desktop,
                ),
              ),
            )
            .then((_) => _load());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: BodylineColors.divider)),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                organ.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: organ.flag == null
                      ? BodylineColors.inkSubtle
                      : BodylineColors.ink,
                  decoration: organ.flag == null
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: BodylineColors.inkSubtle,
                ),
              ),
            ),
            if (organ.flag == null)
              Tooltip(
                message: 'Not tested',
                child: InkWell(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Not tested — no results for this area yet.',
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                ),
              )
            else ...[
              const SizedBox(width: 8),
              Text(
                organ.statusText,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: organ.flag == ObservationFlag.normal
                      ? FontWeight.w500
                      : FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

}
