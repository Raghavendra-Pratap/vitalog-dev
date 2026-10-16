import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../security/app_lock.dart';
import '../../sync/lan_sync_service.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/theme_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/report_title.dart';
import '../doctor/doctor_summary.dart';
import '../entry/manual_panel_screen.dart';
import '../family/family_screen.dart';
import '../home/home_screen.dart';
import '../import/import_text_screen.dart';
import '../import/report_review_screen.dart';
import '../profile/profile_screen.dart';
import '../records/records_screen.dart';
import '../settings/settings_screen.dart';
import '../tests/tests_screen.dart';
import '../visits/care_screen.dart';
import '../visits/visit_forms.dart';
import '../visits/reminders_screen.dart';
import '../medicines/medicines_screen.dart';
import '../medicines/dose_wait_controller.dart';
import '../medicines/dose_wait_header_chip.dart';
import '../doctor/doctors_screen.dart';
import '../tests/all_tests_screen.dart';
import '../today/today_screen.dart';
import '../today/habits_screen.dart';
import '../records/notes_screen.dart';
import 'app_shell.dart';

/// Parked for closed testing — re-enable when overlay chart is ready.
const bool kShowAllTests = false;

/// Desktop chrome: 248px sidebar + main pane (docs/mockups/desktop/).
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.store, required this.lock, required this.theme, required this.sync});

  final LocalStore store;
  final AppLockController lock;
  final ThemeController theme;
  final LanSyncService sync;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final GlobalKey<FamilyScreenState> _familyKey = GlobalKey<FamilyScreenState>();
  final GlobalKey<MedicinesScreenState> _medicinesKey = GlobalKey<MedicinesScreenState>();
  final GlobalKey<RemindersScreenState> _remindersKey = GlobalKey<RemindersScreenState>();
  final GlobalKey<CareScreenState> _visitsKey = GlobalKey<CareScreenState>();
  final GlobalKey<DoctorsScreenState> _doctorsKey = GlobalKey<DoctorsScreenState>();
  final GlobalKey<TodayScreenState> _todayKey = GlobalKey<TodayScreenState>();
  final GlobalKey<HabitsScreenState> _habitsKey = GlobalKey<HabitsScreenState>();
  final GlobalKey<NotesScreenState> _notesKey = GlobalKey<NotesScreenState>();
  String? _testsFocusCode;
  final TextEditingController _notesSearch = TextEditingController();
  static const _prefsKey = 'desktop_sidebar_collapsed';
  int _nav = 0;
  bool _familyOpen = false;
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    widget.sync.addListener(_onSync);
    _loadSidebarPref();
  }

  Future<void> _loadSidebarPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _sidebarCollapsed = prefs.getBool(_prefsKey) ?? false);
  }

  Future<void> _toggleSidebar() async {
    setState(() => _sidebarCollapsed = !_sidebarCollapsed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, _sidebarCollapsed);
  }

  @override
  void dispose() {
    _notesSearch.dispose();

    widget.sync.removeListener(_onSync);
    super.dispose();
  }

  void _onSync() {
    if (mounted) setState(() {});
  }

      Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          store: widget.store,
          lock: widget.lock,
          theme: widget.theme,
          sync: widget.sync,
          onChanged: _refresh,
          desktop: true,
        ),
      ),
    );
    _refresh();
  }

void _openRunningDoseWait() {
    final mode = DoseWaitController.instance.mode;
    setState(() {
      _familyOpen = false;
      _nav = 8;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _remindersKey.currentState?.openTool(mode);
    });
  }

void _refresh() {
    setState(() {});
    widget.sync.scheduleSyncSoon();
    // IndexedStack keeps panes alive — push habit/today reloads so logs sync.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _habitsKey.currentState?.reload();
      _todayKey.currentState?.reload();
    });
  }

  String _todayDateLabel() {
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final n = DateTime.now();
    return '${days[n.weekday - 1]}, ${n.day} ${months[n.month - 1]}';
  }

  ProfileRecord? get _profile {
    final id = widget.store.activeProfileId;
    for (final p in widget.store.profiles) {
      if (p.id == id) return p;
    }
    return widget.store.profiles.isEmpty ? null : widget.store.profiles.first;
  }

  String get _pageTitle {
    if (_familyOpen) return 'Family';
    return switch (_nav) {
      0 => 'Overview',
      1 => 'Today',
      2 => 'All tests',
      3 => 'Tests',
      4 => 'Records',
      5 => 'Notes',
      6 => 'Medicines & schedule',
      7 => 'Habits',
      8 => 'Reminders',
      9 => 'Visits',
      10 => 'Doctors',
      11 => 'Health profile',
      _ => 'Vitalog',
    };
  }

  String get _pageSubtitle {
    final p = _profile;
    if (_familyOpen) {
      return '${widget.store.profiles.length} profiles on this device · tap a profile to switch';
    }
    final n = widget.store.observations
        .where((o) => o.profileId == widget.store.activeProfileId)
        .map((o) => o.parameterCode)
        .toSet()
        .length;
    final reports = widget.store.reports
        .where((r) => r.profileId == widget.store.activeProfileId)
        .toList()
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
    if (_nav == 0) {
      if (reports.isEmpty) {
        return n == 0
            ? 'Add a report to start tracking'
            : '$n parameters tracked';
      }
      final r = reports.first;
      return 'Latest report · ${displayReportTitle(r.title)} · $n parameters tracked';
    }
    if (_nav == 1) {
      final name = p?.name ?? 'Profile';
      return '${_todayDateLabel()} · $name';
    }
    if (_nav == 2 || _nav == 3) {
      return '$n parameters tracked${p != null ? ' for ${p.name}' : ''} · grouped by body system';
    }
    if (_nav == 4) {
      return 'Reports, doctor visits and documents${p != null ? ' for ${p.name}' : ''}';
    }
    if (_nav == 5) {
      return 'Things reports and prescriptions don’t say${p != null ? ' · ${p.name}' : ''}';
    }
    if (_nav == 6) return 'Schedule and stock on this device. Dose Taken / Skip is under Reminders.';
    if (_nav == 7) {
      final name = p?.name ?? 'you';
      return 'Habits for $name · progress counted in days, never streaks';
    }
    if (_nav == 8) return 'Retests, follow-ups, and the dose wait timer';
    if (_nav == 9) return 'Doctor visits and follow-ups';
    if (_nav == 10) return 'Doctors from visits plus notes and files';
    if (_nav == 11) return 'The complete picture, not just test history';
    return 'Your data lives on this device and in your own cloud. We never see it.';
  }

  @override
  Widget build(BuildContext context) {
    BodylineColors.syncFrom(context);
    final profile = _profile;
    final initial = (profile?.name.isNotEmpty == true)
        ? profile!.name[0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            profileName: profile?.name ?? 'Profile',
            initial: initial,
            selected: _familyOpen ? -1 : _nav,
            collapsed: _sidebarCollapsed,
            onToggleCollapsed: _toggleSidebar,
            onSelect: (i) {
              setState(() {
                _familyOpen = false;
                _nav = i;
              });
              if (i == 5) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _notesKey.currentState?.reload();
                });
              }
              if (i == 1) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _todayKey.currentState?.reload();
                });
              }
              if (i == 7) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _habitsKey.currentState?.reload();
                });
              }
            },
            onSwitchProfile: () => setState(() => _familyOpen = true),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DesktopTopBar(
                  title: _pageTitle,
                  subtitle: _pageSubtitle,
                  mode: _familyOpen
                      ? _TopMode.family
                      : switch (_nav) {
                          1 => _TopMode.today,
                          4 => _TopMode.records,
                          5 => _TopMode.notes,
                          6 => _TopMode.careMedicine,
                          7 => _TopMode.habits,
                          8 => _TopMode.careReminder,
                          9 => _TopMode.careVisit,
                          10 => _TopMode.careDoctor,
                          11 => _TopMode.health,
                          12 => _TopMode.none,
                          _ => _TopMode.addReport,
                        },
                  onAddHabit: () {
                    if (_nav == 7) {
                      _habitsKey.currentState?.promptAdd();
                    } else {
                      _todayKey.currentState?.promptAdd();
                    }
                  },
                  onAddNote: () => _notesKey.currentState?.promptAdd(),
                  notesSearch: _notesSearch,
                  onAddReport: _openAdd,
                  onAddVisit: () async {
                    final ok = await promptAddVisit(
                      context,
                      store: widget.store,
                      onChanged: _refresh,
                    );
                    if (ok) {
                      _refresh();
                      _visitsKey.currentState; // keep keyed state warm
                    }
                  },
                  onAddMedicine: () => _medicinesKey.currentState?.promptAdd(),
                  onAddReminder: () => _remindersKey.currentState?.promptAdd(),
                  onAddVisitCare: () => _visitsKey.currentState?.promptAdd(),
                  onAddDoctor: () => _doctorsKey.currentState?.promptAdd(),
                  onAddFamily: () {
                    _familyKey.currentState?.promptAddMember();
                  },
                  onEmergency: () async {
                    // Stay on health profile — emergency card is in-profile.
                  },
                  onDoctorPdf: () => shareDoctorSummary(
                    context: context,
                    store: widget.store,
                  ),
                  onOpenDoseWait: _openRunningDoseWait,
                  onOpenSettings: _openSettings,
                ),
                Expanded(
                  child: _familyOpen
                      ? FamilyScreen(
                          key: _familyKey,
                          store: widget.store,
                          onChanged: () {
                            _refresh();
                            setState(() => _familyOpen = false);
                          },
                        )
                      : IndexedStack(
                          index: _nav.clamp(0, 11),
                          children: [
                            HomeScreen(
                              store: widget.store,
                              onChanged: _refresh,
                              desktop: true,
                              onAddReport: _openAdd,
                              onSeeAllTests: kShowAllTests
                                  ? () => setState(() => _nav = 2)
                                  : null,
                            ),
                            TodayScreen(
                              key: _todayKey,
                              store: widget.store,
                              onChanged: _refresh,
                              desktop: true,
                              onOpenHabits: () => setState(() => _nav = 7),
                              onOpenMedicines: () => setState(() => _nav = 6),
                            ),
                            AllTestsScreen(
                              store: widget.store,
                              onChanged: _refresh,
                              desktop: true,
                            ),
                            TestsScreen(
                              key: ValueKey('tests-${_testsFocusCode ?? 'default'}'),
                              store: widget.store,
                              onChanged: _refresh,
                              desktop: true,
                              initialParameterCode: _testsFocusCode,
                            ),
                            RecordsScreen(
                              store: widget.store,
                              onAdd: _openAdd,
                              onChanged: _refresh,
                              desktop: true,
                            ),
                            NotesScreen(
                              key: _notesKey,
                              store: widget.store,
                              onChanged: _refresh,
                              embedded: true,
                              searchController: _notesSearch,
                              onOpenChart: (raw) {
                                String code = raw;
                                final pid = widget.store.activeProfileId;
                                for (final o in widget.store.observations) {
                                  if (pid != null && o.profileId != pid) continue;
                                  if (o.parameterCode == raw ||
                                      o.parameterName == raw ||
                                      o.parameterName.toLowerCase() ==
                                          raw.toLowerCase()) {
                                    code = o.parameterCode;
                                    break;
                                  }
                                }
                                setState(() {
                                  _testsFocusCode = code;
                                  _nav = 3;
                                });
                              },
                            ),
                            MedicinesScreen(
                              key: _medicinesKey,
                              store: widget.store,
                              onChanged: _refresh,
                              embedded: true,
                            ),
                            HabitsScreen(
                              key: _habitsKey,
                              store: widget.store,
                              onChanged: _refresh,
                              embedded: true,
                            ),
                            RemindersScreen(
                              key: _remindersKey,
                              store: widget.store,
                              onChanged: _refresh,
                              embedded: true,
                            ),
                            CareScreen(
                              key: _visitsKey,
                              store: widget.store,
                              onChanged: _refresh,
                              embedded: true,
                            ),
                            DoctorsScreen(
                              key: _doctorsKey,
                              store: widget.store,
                              onChanged: _refresh,
                            ),
                            ProfileScreen(
                              store: widget.store,
                              onChanged: _refresh,
                              lock: widget.lock,
                              theme: widget.theme,
                              sync: widget.sync,
                              desktop: true,
                              onOpenDesktopNav: (i) => setState(() {
                                _familyOpen = false;
                                _nav = i;
                              }),
                            ),
                          ],
                        ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAdd() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add report'),
        content: const Text(
          'Import a PDF or photo, or enter a panel manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'manual'),
            child: const Text('Manual entry'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'image'),
            child: const Text('Open image'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'review'),
            style: FilledButton.styleFrom(
              backgroundColor: BodylineColors.ink,
              foregroundColor: BodylineColors.onInk,
            ),
            child: const Text('Review PDF'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'review') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReportReviewScreen(
            store: widget.store,
            onSaved: () {
              _refresh();
            },
          ),
        ),
      );
    } else if (choice == 'image') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImportTextScreen(
            store: widget.store,
            onSaved: () {
              _refresh();
            },
            autoOpenImage: true,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ManualPanelScreen(
            store: widget.store,
            onSaved: () {
              _refresh();
            },
          ),
        ),
      );
    }
    _refresh();
  }
}

enum _TopMode { none, addReport, records, health, family, careMedicine, careReminder, careVisit, careDoctor, careWait, today, habits, notes }


class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({
    required this.title,
    required this.subtitle,
    required this.mode,
    required this.onAddReport,
    this.onAddVisit,
    this.onAddMedicine,
    this.onAddReminder,
    this.onAddVisitCare,
    this.onAddDoctor,
    this.onAddHabit,
    this.onAddNote,
    this.onAddFamily,
    this.onEmergency,
    this.onDoctorPdf,
    this.onOpenDoseWait,
    this.onOpenSettings,
    this.notesSearch,
  });

  final String title;
  final String subtitle;
  final _TopMode mode;
  final VoidCallback onAddReport;
  final VoidCallback? onAddVisit;
  final VoidCallback? onAddMedicine;
  final VoidCallback? onAddReminder;
  final VoidCallback? onAddHabit;
  final VoidCallback? onAddNote;
  final VoidCallback? onAddVisitCare;
  final VoidCallback? onAddDoctor;
  final VoidCallback? onAddFamily;
  final VoidCallback? onEmergency;
  final VoidCallback? onDoctorPdf;
  final VoidCallback? onOpenDoseWait;
  final VoidCallback? onOpenSettings;
  final TextEditingController? notesSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesktopLayout.mainPaddingH,
        DesktopLayout.mainPaddingV,
        DesktopLayout.mainPaddingH,
        8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 14,
                        color: BodylineColors.inkSubtle,
                      ),
                ),
              ],
            ),
          ),
          if (onOpenDoseWait != null)
            DoseWaitHeaderChip(onOpen: onOpenDoseWait!),
          ..._actions(context),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    switch (mode) {
      case _TopMode.none:
      case _TopMode.careWait:
        return const [];
      case _TopMode.family:
        return [
          FilledButton.icon(
            onPressed: onAddFamily,
            style: _ink(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add family member',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ];
      case _TopMode.health:
        return [
          OutlinedButton.icon(
            onPressed: onOpenSettings,
            style: _outline(),
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('Settings',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ];
      case _TopMode.records:
        return [
          OutlinedButton.icon(
            onPressed: onAddVisit,
            style: _outline(),
            icon: const Icon(Icons.event_note_outlined, size: 18),
            label: const Text('Add visit',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: onAddReport,
            style: _ink(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add report',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ];
      case _TopMode.today:
        return [
          FilledButton.icon(
            onPressed: onAddHabit,
            icon: const Icon(Icons.add, size: 18),
            style: FilledButton.styleFrom(backgroundColor: BodylineColors.teal),
            label: const Text('New habit',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ];
      case _TopMode.habits:
        return [
          FilledButton.icon(
            onPressed: onAddHabit,
            icon: const Icon(Icons.add, size: 18),
            style: FilledButton.styleFrom(backgroundColor: BodylineColors.teal),
            label: const Text('New habit',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ];
      case _TopMode.notes:
        return [
          if (notesSearch != null) ...[
            SizedBox(
              width: 220,
              height: 40,
              child: TextField(
                controller: notesSearch,
                decoration: InputDecoration(
                  hintText: 'Search notes',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  filled: true,
                  fillColor: BodylineColors.chip,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          FilledButton.icon(
            onPressed: onAddNote,
            icon: const Icon(Icons.add, size: 18),
            style: FilledButton.styleFrom(backgroundColor: BodylineColors.ink),
            label: const Text('New note',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ];
      case _TopMode.careMedicine:
        return [
          FilledButton.icon(
            onPressed: onAddMedicine,
            style: _ink(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add medicine',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ];
      case _TopMode.careReminder:
        return [
          FilledButton.icon(
            onPressed: onAddReminder,
            style: _ink(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add reminder',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ];
      case _TopMode.careVisit:
        return [
          FilledButton.icon(
            onPressed: onAddVisitCare,
            style: _ink(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add visit',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ];
      case _TopMode.careDoctor:
        return [
          FilledButton.icon(
            onPressed: onAddDoctor,
            style: _ink(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add doctor',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ];
      case _TopMode.addReport:
        return [
          FilledButton.icon(
            onPressed: onAddReport,
            style: _ink(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add report',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ];
    }
  }

  ButtonStyle _ink() => FilledButton.styleFrom(
        backgroundColor: BodylineColors.ink,
        foregroundColor: BodylineColors.onInk,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: const StadiumBorder(),
      );

  ButtonStyle _outline() => OutlinedButton.styleFrom(
        foregroundColor: BodylineColors.ink,
        backgroundColor: BodylineColors.surface,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: BorderSide(color: BodylineColors.outlineSoft),
        shape: const StadiumBorder(),
      );
}


class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.profileName,
    required this.initial,
    required this.selected,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onSelect,
    required this.onSwitchProfile,
  });

  final String profileName;
  final String initial;
  final int selected;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<int> onSelect;
  final VoidCallback onSwitchProfile;

  @override
  Widget build(BuildContext context) {
    final width = collapsed
        ? DesktopLayout.sidebarCollapsedWidth
        : DesktopLayout.sidebarWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        border: Border(right: BorderSide(color: BodylineColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        collapsed ? 10 : 16,
        24,
        collapsed ? 10 : 16,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (collapsed)
            Column(
              children: [
                Tooltip(
                  message: 'Expand sidebar',
                  child: IconButton(
                    onPressed: onToggleCollapsed,
                    icon: const Icon(Icons.keyboard_double_arrow_right, size: 22),
                    color: BodylineColors.ink,
                    tooltip: 'Expand sidebar',
                  ),
                ),
                const SizedBox(height: 8),
                const BodylineMark(size: 28),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  const Expanded(
                    child: BodylineLockup(markSize: 28, wordSize: 22),
                  ),
                  Tooltip(
                    message: 'Collapse sidebar',
                    child: IconButton(
                      onPressed: onToggleCollapsed,
                      icon: const Icon(Icons.keyboard_double_arrow_left, size: 20),
                      color: BodylineColors.inkMuted,
                      tooltip: 'Collapse sidebar',
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          if (collapsed)
            Tooltip(
              message: 'Switch profile · $profileName',
              child: InkWell(
                onTap: onSwitchProfile,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: BodylineColors.teal,
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: BodylineColors.onInk,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            Material(
              color: BodylineColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: BodylineColors.border),
              ),
              child: InkWell(
                onTap: onSwitchProfile,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: BodylineColors.teal,
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: BodylineColors.onInk,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
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
                            Text(
                              profileName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: BodylineColors.ink,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.unfold_more, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          if (!collapsed)
            _NavSectionLabel(label: 'Overview'),
          _NavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: 'Home',
            selected: selected == 0,
            collapsed: collapsed,
            onTap: () => onSelect(0),
          ),
          _NavItem(
            icon: Icons.today_outlined,
            selectedIcon: Icons.today,
            label: 'Today',
            selected: selected == 1,
            collapsed: collapsed,
            onTap: () => onSelect(1),
          ),
          if (kShowAllTests)
            _NavItem(
              icon: Icons.grid_view_outlined,
              selectedIcon: Icons.grid_view,
              label: 'All tests',
              selected: selected == 2,
              collapsed: collapsed,
              onTap: () => onSelect(2),
            ),
          if (!collapsed)
            _NavSectionLabel(label: 'Labs'),
          _NavItem(
            icon: Icons.show_chart,
            selectedIcon: Icons.show_chart,
            label: 'Tests',
            selected: selected == 3,
            collapsed: collapsed,
            onTap: () => onSelect(3),
          ),
          _NavItem(
            icon: Icons.description_outlined,
            selectedIcon: Icons.description,
            label: 'Records',
            selected: selected == 4,
            collapsed: collapsed,
            onTap: () => onSelect(4),
          ),
          _NavItem(
            icon: Icons.sticky_note_2_outlined,
            selectedIcon: Icons.sticky_note_2,
            label: 'Notes',
            selected: selected == 5,
            collapsed: collapsed,
            onTap: () => onSelect(5),
          ),
          if (!collapsed)
            _NavSectionLabel(label: 'Care'),
          _NavItem(
            icon: Icons.medication_outlined,
            selectedIcon: Icons.medication,
            label: 'Medicines',
            selected: selected == 6,
            collapsed: collapsed,
            onTap: () => onSelect(6),
          ),
          _NavItem(
            icon: Icons.check_circle_outline,
            selectedIcon: Icons.check_circle,
            label: 'Habits',
            selected: selected == 7,
            collapsed: collapsed,
            onTap: () => onSelect(7),
          ),
          _NavItem(
            icon: Icons.notifications_none,
            selectedIcon: Icons.notifications,
            label: 'Reminders',
            selected: selected == 8,
            collapsed: collapsed,
            onTap: () => onSelect(8),
          ),
          _NavItem(
            icon: Icons.event_note_outlined,
            selectedIcon: Icons.event_note,
            label: 'Visits',
            selected: selected == 9,
            collapsed: collapsed,
            onTap: () => onSelect(9),
          ),
          _NavItem(
            icon: Icons.medical_services_outlined,
            selectedIcon: Icons.medical_services,
            label: 'Doctors',
            selected: selected == 10,
            collapsed: collapsed,
            onTap: () => onSelect(10),
          ),
                ],
              ),
            ),
          ),
          if (!collapsed)
            _NavSectionLabel(label: 'You'),
          _NavItem(
            icon: Icons.favorite_border,
            selectedIcon: Icons.favorite,
            label: 'Health profile',
            selected: selected == 11,
            collapsed: collapsed,
            onTap: () => onSelect(11),
          ),
          if (!collapsed) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: BodylineColors.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Encrypted · on this device',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: BodylineColors.inkSubtle,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Icon(
                Icons.lock_outline,
                size: 16,
                color: BodylineColors.teal,
              ),
            ),
        ],
      ),
    );
  }
}

class _NavSectionLabel extends StatelessWidget {
  const _NavSectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: BodylineColors.inkSubtle,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      selected ? selectedIcon : icon,
      size: 20,
      color: selected ? BodylineColors.teal : BodylineColors.inkMuted,
    );

    final tile = Material(
      color: selected ? BodylineColors.tealTint : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 44,
          child: collapsed
              ? Center(child: iconWidget)
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      iconWidget,
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w600,
                            color: selected
                                ? BodylineColors.tealDark
                                : BodylineColors.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: collapsed
          ? Tooltip(message: label, waitDuration: const Duration(milliseconds: 400), child: tile)
          : tile,
    );
  }
}
