import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../theme/desktop_layout.dart';
import '../../desktop.dart';
import '../../notifications/reminder_notifications.dart';
import '../../widgets/clinical_attachments.dart';
import '../../widgets/report_title.dart';
import 'visit_forms.dart';
import 'reminder_form.dart';

class CareScreen extends StatefulWidget {
  const CareScreen({
    super.key,
    required this.store,
    required this.onChanged,
    this.embedded = false,
    this.includeReminders = true,
  });

  final LocalStore store;
  final VoidCallback onChanged;
  final bool embedded;
  /// When false (Care → Visits tab), only the visits list is shown.
  final bool includeReminders;

  @override
  CareScreenState createState() => CareScreenState();
}

class CareScreenState extends State<CareScreen> {
  Future<void> promptAdd() => _addVisit();

  List<VisitRecord> _visits = [];
  List<ReminderRecord> _reminders = [];
  var _loading = true;
  String? _selectedVisitId;
  var _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CareScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Shell IndexedStack keeps this State; reload after visits added elsewhere
    // (e.g. Doctors → Add visit).
    _load();
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _visits = [];
        _reminders = [];
        _loading = false;
      });
      return;
    }
    final ensured = await widget.store.ensureVisitFollowUpReminders(pid);
    for (final rem in ensured) {
      await ReminderNotifications.instance.scheduleReminder(rem);
    }
    final v = await widget.store.listVisits(pid);
    final r = await widget.store.listReminders(pid);
    if (!mounted || gen != _loadGen) return;
    setState(() {
      _visits = v;
      _reminders = r;
      _loading = false;
      final ids = {for (final x in v) x.id};
      if (_selectedVisitId != null && !ids.contains(_selectedVisitId)) {
        _selectedVisitId = v.isEmpty ? null : v.first.id;
      } else if (_selectedVisitId == null && v.isNotEmpty) {
        _selectedVisitId = v.first.id;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.embedded && useWideShell(context)) {
      return _buildDesktop(context);
    }
    return _buildMobile(context);
  }

  Widget _buildMobile(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final showRem = widget.includeReminders;
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(showRem ? 'Visits & reminders' : 'Visits'),
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: widget.embedded
            ? (showRem ? 'care-tab-visits-reminders-fab' : 'care-tab-visits-fab')
            : (showRem ? 'page-visits-reminders-fab' : 'page-visits-fab'),
        onPressed: showRem ? _addMenu : _addVisit,
        tooltip: showRem ? 'Add' : 'Add visit',
        backgroundColor: BodylineColors.teal,
        foregroundColor: BodylineColors.isDark
            ? const Color(0xFF04201C)
            : Colors.white,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              children: [
                if (showRem) ...[
                  Text('Reminders', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Only reminders you create appear here — nothing is invented.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (_reminders.isEmpty)
                    Text('No reminders yet.',
                        style: Theme.of(context).textTheme.bodyMedium)
                  else
                    for (final r in _reminders)
                      _card(
                        title: displayReportTitle(r.title),
                        subtitle: 'Due ${fmt.format(r.dueAt)}',
                        trailing: TextButton(
                          onPressed: () async {
                            final next = await widget.store.completeReminder(r.id);
                            if (next == null) {
                              await ReminderNotifications.instance.cancelReminder(r.id);
                            } else {
                              await ReminderNotifications.instance.scheduleReminder(next);
                            }
                            widget.onChanged();
                            await _load();
                          },
                          child: const Text('Done'),
                        ),
                      ),
                  const SizedBox(height: 24),
                  Text('Visits', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                ],
                if (_visits.isEmpty)
                  Text('No visits logged yet.',
                      style: Theme.of(context).textTheme.bodyMedium)
                else
                  for (final v in _visits)
                    InkWell(
                      onTap: () => _openVisit(v),
                      borderRadius:
                          BorderRadius.circular(BodylineRadii.cardSmall),
                      child: _card(
                        title: v.reason?.isNotEmpty == true
                            ? v.reason!
                            : 'Visit',
                        subtitle: [
                          fmt.format(v.visitedAt),
                          if (v.providerName?.isNotEmpty == true)
                            v.providerName!,
                          if (v.diagnosis?.isNotEmpty == true)
                            v.diagnosis!,
                          if (v.followUpDate != null)
                            'Follow-up ${v.followUpDate}',
                          if (v.notes?.isNotEmpty == true) v.notes!,
                        ].join(' · '),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                      ),
                    ),
              ],
            ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final monthFmt = DateFormat('MMMM yyyy');
    VisitRecord? selected;
    for (final v in _visits) {
      if (v.id == _selectedVisitId) {
        selected = v;
        break;
      }
    }

    final groups = <String, List<VisitRecord>>{};
    for (final v in _visits) {
      final key = monthFmt.format(v.visitedAt);
      groups.putIfAbsent(key, () => []).add(v);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesktopLayout.mainPaddingH,
        8,
        DesktopLayout.mainPaddingH,
        DesktopLayout.mainPaddingV,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: DesktopLayout.testsMasterCol,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Date-wise visits. Select one to see full details.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: BodylineColors.inkSubtle,
                      ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _visits.isEmpty
                      ? Center(
                          child: Text(
                            'No visits logged yet.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : ListView(
                          children: [
                            for (final entry in groups.entries) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                                child: Text(
                                  entry.key,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              for (final v in entry.value) ...[
                                _visitCard(
                                  v,
                                  fmt,
                                  selected: v.id == _selectedVisitId,
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: selected == null
                ? Center(
                    child: Text(
                      'Select a visit to see details and remarks.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: BodylineColors.surface,
                      borderRadius: BorderRadius.circular(BodylineRadii.card),
                      border: Border.all(color: BodylineColors.border),
                    ),
                    child: VisitDetailPane(
                      key: ValueKey(selected.id),
                      store: widget.store,
                      visit: selected,
                      onChanged: () {
                        widget.onChanged();
                        _load();
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _visitCard(
    VisitRecord v,
    DateFormat fmt, {
    required bool selected,
  }) {
    return Material(
      color: selected ? BodylineColors.selectedWash : BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        onTap: () => setState(() => _selectedVisitId = v.id),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BodylineRadii.card),
            border: Border.all(
              color: selected ? BodylineColors.teal : BodylineColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                v.reason?.isNotEmpty == true ? v.reason! : 'Visit',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? BodylineColors.tealDark
                      : BodylineColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  fmt.format(v.visitedAt),
                  if (v.providerName?.isNotEmpty == true) v.providerName!,
                  if (v.providerClinic?.isNotEmpty == true) v.providerClinic!,
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        border: Border.all(color: BodylineColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Future<void> _openVisit(VisitRecord visit) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VisitDetailScreen(
          store: widget.store,
          visit: visit,
          onChanged: () {
            widget.onChanged();
            _load();
          },
        ),
      ),
    );
    await _load();
  }

  Future<void> _addMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Add visit'),
              onTap: () => Navigator.pop(ctx, 'visit'),
            ),
            ListTile(
              title: const Text('Add reminder'),
              onTap: () => Navigator.pop(ctx, 'reminder'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'visit') await _addVisit();
    if (choice == 'reminder') await _addReminder();
  }

  Future<void> _addVisit({String? prefillDoctor}) async {
    final ok = await promptAddVisit(
      context,
      store: widget.store,
      onChanged: widget.onChanged,
      prefillDoctor: prefillDoctor,
    );
    if (ok) await _load();
  }

  Future<void> _addReminder() async {
    final rem = await showAddReminderDialog(context, store: widget.store);
    if (rem == null) return;
    widget.onChanged();
    await _load();
  }
}


class VisitDetailScreen extends StatelessWidget {
  const VisitDetailScreen({
    super.key,
    required this.store,
    required this.visit,
    required this.onChanged,
  });

  final LocalStore store;
  final VisitRecord visit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          visit.reason?.isNotEmpty == true ? visit.reason! : 'Visit',
        ),
      ),
      body: VisitDetailPane(
        store: store,
        visit: visit,
        onChanged: onChanged,
      ),
    );
  }
}

class VisitDetailPane extends StatefulWidget {
  const VisitDetailPane({
    super.key,
    required this.store,
    required this.visit,
    required this.onChanged,
  });

  final LocalStore store;
  final VisitRecord visit;
  final VoidCallback onChanged;

  @override
  State<VisitDetailPane> createState() => _VisitDetailPaneState();
}

class _VisitDetailPaneState extends State<VisitDetailPane> {
  List<MedicalItem> _meds = [];
  var _loadingMeds = true;
  var _medsGen = 0;
  late VisitRecord _visit;

  @override
  void initState() {
    super.initState();
    _visit = widget.visit;
    _loadMeds();
  }

  @override
  void didUpdateWidget(covariant VisitDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visit.id != widget.visit.id ||
        oldWidget.visit.reason != widget.visit.reason ||
        oldWidget.visit.visitedAt != widget.visit.visitedAt ||
        oldWidget.visit.providerName != widget.visit.providerName) {
      _visit = widget.visit;
    }
    _loadMeds();
  }

  Future<void> _loadMeds() async {
    final gen = ++_medsGen;
    setState(() => _loadingMeds = true);
    final meds = await widget.store.listMedicationsForVisit(_visit.id);
    if (!mounted || gen != _medsGen) return;
    setState(() {
      _meds = meds;
      _loadingMeds = false;
    });
  }

  Future<void> _edit() async {
    final updated = await promptEditVisit(
      context,
      store: widget.store,
      visit: _visit,
      onChanged: widget.onChanged,
    );
    if (updated != null && mounted) {
      setState(() => _visit = updated);
      widget.onChanged();
      await _loadMeds();
    }
  }

  Widget _section(String title, String? body) {
    final text = (body == null || body.trim().isEmpty) ? '—' : body.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            text,
            style: TextStyle(
              color: text == '—'
                  ? BodylineColors.inkSubtle
                  : BodylineColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visit = _visit;
    final fmt = DateFormat('d MMM yyyy');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                visit.reason?.isNotEmpty == true ? visit.reason! : 'Visit',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            IconButton(
              tooltip: 'Edit visit',
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          fmt.format(visit.visitedAt),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        _section('Doctor', visit.providerName),
        _section('Hospital / clinic', visit.providerClinic),
        _section('Diagnosis / findings', visit.diagnosis),
        _section('Remarks / notes', visit.notes),
        _section(
          'Follow-up',
          visit.followUpDate == null
              ? null
              : () {
                  try {
                    final p = visit.followUpDate!.split('-');
                    if (p.length == 3) {
                      return DateFormat('d MMM yyyy').format(
                        DateTime(
                          int.parse(p[0]),
                          int.parse(p[1]),
                          int.parse(p[2]),
                        ),
                      );
                    }
                  } catch (_) {}
                  return visit.followUpDate;
                }(),
        ),
        const SizedBox(height: 16),
        Text(
          'Prescribed medicines',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        if (_loadingMeds)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (_meds.isEmpty)
          Text(
            'None linked to this visit. Edit the visit to add one, or add from Medicines.',
            style: TextStyle(color: BodylineColors.inkSubtle),
          )
        else
          for (final m in _meds)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(BodylineRadii.cardSmall),
                  border: Border.all(color: BodylineColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (m.subtitle != null && m.subtitle!.isNotEmpty)
                      Text(
                        m.subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          color: BodylineColors.inkSubtle,
                        ),
                      ),
                    if (m.instructions != null &&
                        m.instructions!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(m.instructions!),
                    ],
                  ],
                ),
              ),
            ),
        const SizedBox(height: 24),
        ClinicalAttachmentsSection(
          store: widget.store,
          ownerType: 'visit',
          ownerId: visit.id,
          onChanged: widget.onChanged,
          title: 'Appointment files',
          emptyHint:
              'Optional — attach the doctor’s note, findings, or prescription (PDF or photo) to open or share from this device.',
        ),
      ],
    );
  }
}
