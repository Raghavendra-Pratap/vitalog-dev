import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../../widgets/report_title.dart';
import '../../widgets/clinical_attachments.dart';
import 'report_detail_screen.dart';
import 'notes_screen.dart';
import 'timeline_screen.dart';
import '../entry/manual_panel_screen.dart';

enum _RecFilter { all, reports, visits, documents, byDay }

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({
    super.key,
    required this.store,
    required this.onAdd,
    this.desktop = false,
    this.asPage = false,
  });

  final LocalStore store;
  final VoidCallback onAdd;
  final bool desktop;
  /// Pushed from Profile — AppBar + back instead of tab-root header.
  final bool asPage;

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  _RecFilter _filter = _RecFilter.all;
  String? _selectedId;
  List<VisitRecord> _visits = [];
  List<AttachmentRecord> _docs = [];
  var _extraLoading = false;

  List<ReportRecord> get _reports {
    return widget.store.reports
        .where((r) => r.profileId == widget.store.activeProfileId)
        .toList()
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
  }

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  @override
  void didUpdateWidget(covariant RecordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      if (!mounted) return;
      setState(() {
        _visits = [];
        _docs = [];
      });
      return;
    }
    setState(() => _extraLoading = true);
    final visits = await widget.store.listVisits(pid);
    final docs = await widget.store.listAllAttachmentsForProfile(pid);
    if (!mounted) return;
    setState(() {
      _visits = visits;
      _docs = docs;
      _extraLoading = false;
    });
  }

  Future<void> _setFilter(_RecFilter f) async {
    setState(() => _filter = f);
    if (f == _RecFilter.visits ||
        f == _RecFilter.documents ||
        f == _RecFilter.all) {
      await _loadExtras();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.desktop) return _buildDesktop(context);
    return _buildMobile(context);
  }

  Widget _buildDesktop(BuildContext context) {
    final reports = _reports;
    final ids = reports.map((r) => r.id).toSet();
    final selectedId = (_selectedId != null && ids.contains(_selectedId))
        ? _selectedId
        : (reports.isEmpty ? null : reports.first.id);
    if (selectedId != _selectedId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedId = selectedId);
      });
    }
    ReportRecord? selected;
    for (final r in reports) {
      if (r.id == selectedId) selected = r;
    }

    final groups = <String, List<ReportRecord>>{};
    final monthFmt = DateFormat('MMMM yyyy');
    for (final r in reports) {
      final key = monthFmt.format(r.collectedAt);
      groups.putIfAbsent(key, () => []).add(r);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(DesktopLayout.mainPaddingH, 8, DesktopLayout.mainPaddingH, DesktopLayout.mainPaddingV),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: DesktopLayout.recordsMasterCol,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    _chip('All', _filter == _RecFilter.all, () {
                      _setFilter(_RecFilter.all);
                    }),
                    _chip('Reports', _filter == _RecFilter.reports, () {
                      _setFilter(_RecFilter.reports);
                    }),
                    _chip('Visits', _filter == _RecFilter.visits, () {
                      _setFilter(_RecFilter.visits);
                    }),
                    _chip('Documents', _filter == _RecFilter.documents, () {
                      _setFilter(_RecFilter.documents);
                    }),
                    _chip('By day', _filter == _RecFilter.byDay, () {
                      _setFilter(_RecFilter.byDay);
                    }),
                    _chip('Notes', false, () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NotesScreen(
                            store: widget.store,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                      );
                    }),
                    _chip('Timeline', false, () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TimelineScreen(store: widget.store),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _extraLoading &&
                          (_filter == _RecFilter.visits ||
                              _filter == _RecFilter.documents)
                      ? const Center(child: CircularProgressIndicator())
                      : _filter == _RecFilter.byDay
                          ? (_daysGrouped.isEmpty
                              ? Center(
                                  child: Text(
                                    'No day reports yet.',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                )
                              : ListView(
                                  children: [
                                    for (final e in (_daysGrouped.entries
                                          .toList()
                                        ..sort((a, b) =>
                                            b.key.compareTo(a.key))))
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: _dayCard(e.key, e.value),
                                      ),
                                  ],
                                ))
                          : _filter == _RecFilter.visits
                          ? (_visits.isEmpty
                              ? Center(
                                  child: Text(
                                    'No visits yet.',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _visits.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, i) {
                                    final v = _visits[i];
                                    return _visitCard(v);
                                  },
                                ))
                          : _filter == _RecFilter.documents
                              ? (_docs.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No documents yet.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: _docs.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 8),
                                      itemBuilder: (context, i) {
                                        final d = _docs[i];
                                        return _docCard(d);
                                      },
                                    ))
                              : reports.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No records yet.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                    )
                                  : ListView(
                                      children: [
                                        for (final entry
                                            in groups.entries) ...[
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                4, 8, 4, 6),
                                            child: Text(
                                              entry.key,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                          for (final r in entry.value) ...[
                                            _timelineCard(
                                              r,
                                              selected: r.id == _selectedId,
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
                      'Select a report to inspect values.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : _ReportDetailPane(
                    key: ValueKey(selected.id),
                    store: widget.store,
                    report: selected,
                    onChanged: () => setState(() {}),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _timelineCard(ReportRecord r, {required bool selected}) {
    final obs = widget.store.observations
        .where((o) => o.reportId == r.id)
        .toList();
    final flagged = obs
        .where((o) => o.flag != null && o.flag != ObservationFlag.normal)
        .length;
    final dateFmt = DateFormat('d MMM');

    return Material(
      color: selected ? BodylineColors.selectedWash : BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        onTap: () => setState(() => _selectedId = r.id),
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
              ReportTitleText(
                r.title,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? BodylineColors.tealDark
                      : BodylineColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${dateFmt.format(r.collectedAt)} · ${obs.length} values',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (flagged > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '$flagged flagged',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: BodylineColors.orange,
                  ),
                ),
              ] else if (obs.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'In range',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: BodylineColors.tealDark,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final reports = _reports;
    final groups = <String, List<ReportRecord>>{};
    final monthFmt = DateFormat('MMMM yyyy');
    for (final r in reports) {
      final key = monthFmt.format(r.collectedAt);
      groups.putIfAbsent(key, () => []).add(r);
    }

    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.asPage)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Records',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(
                    'Reports, visits and documents',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Wrap(
              spacing: 8,
              children: [
                _chip('All', _filter == _RecFilter.all, () {
                  _setFilter(_RecFilter.all);
                }),
                _chip('Reports', _filter == _RecFilter.reports, () {
                  _setFilter(_RecFilter.reports);
                }),
                _chip('Visits', _filter == _RecFilter.visits, () {
                  _setFilter(_RecFilter.visits);
                }),
                _chip('Documents', _filter == _RecFilter.documents, () {
                  _setFilter(_RecFilter.documents);
                }),
                _chip('By day', _filter == _RecFilter.byDay, () {
                  _setFilter(_RecFilter.byDay);
                }),
                _chip('Notes', false, () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NotesScreen(
                        store: widget.store,
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  );
                }),
                _chip('Timeline', false, () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TimelineScreen(store: widget.store),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _filter == _RecFilter.byDay
                ? (_daysGrouped.isEmpty
                    ? Center(
                        child: Text(
                          'No day reports yet.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        children: [
                          for (final e in (_daysGrouped.entries.toList()
                            ..sort((a, b) => b.key.compareTo(a.key))))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _dayCard(e.key, e.value),
                            ),
                        ],
                      ))
                : _filter == _RecFilter.visits
                ? (_visits.isEmpty
                    ? Center(
                        child: Text(
                          'No visits yet.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        itemCount: _visits.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _visitCard(_visits[i]),
                      ))
                : _filter == _RecFilter.documents
                    ? (_docs.isEmpty
                        ? Center(
                            child: Text(
                              'No documents yet.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(20, 0, 20, 100),
                            itemCount: _docs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) => _docCard(_docs[i]),
                          ))
                    : reports.isEmpty
                        ? Center(
                            child: Text(
                              'No records yet.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : ListView(
                            padding:
                                const EdgeInsets.fromLTRB(20, 0, 20, 100),
                            children: [
                              for (final entry in groups.entries) ...[
                                Text(
                                  entry.key,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                for (final r in entry.value) ...[
                                  _reportCardMobile(r),
                                  const SizedBox(height: 8),
                                ],
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
          ),
        ],
    );

    if (widget.asPage) {
      return Scaffold(
        backgroundColor: BodylineColors.paper,
        appBar: AppBar(title: const Text('Records')),
        floatingActionButton: FloatingActionButton(
          heroTag: 'page-records-fab',
          onPressed: widget.onAdd,
          tooltip: 'Add report',
          backgroundColor: BodylineColors.ink,
          foregroundColor: BodylineColors.onInk,
          child: const Icon(Icons.add),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        body: SafeArea(child: body),
      );
    }
    return SafeArea(child: body);
  }

  Widget _reportCardMobile(ReportRecord r) {
    return Material(
      color: BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReportDetailScreen(
                store: widget.store,
                report: r,
                onChanged: () => setState(() {}),
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
            border: Border.all(color: BodylineColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ReportTitleText(
                      r.title,
                        maxLines: 2,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      DateFormat('d MMM yyyy').format(r.collectedAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }



  Map<String, List<ReportRecord>> get _daysGrouped {
    final map = <String, List<ReportRecord>>{};
    final keyFmt = DateFormat('yyyy-MM-dd');
    for (final r in _reports) {
      final k = keyFmt.format(r.collectedAt);
      map.putIfAbsent(k, () => []).add(r);
    }
    return map;
  }

  Widget _dayCard(String dayKey, List<ReportRecord> reports) {
    final label = DateFormat('d MMM yyyy').format(DateTime.parse(dayKey));
    final obsCount = widget.store.observations
        .where((o) => reports.any((r) => r.id == o.reportId))
        .length;
    return Material(
      color: BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        onTap: () => _openDayReport(dayKey, reports),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
            border: Border.all(color: BodylineColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      '${reports.length} package${reports.length == 1 ? '' : 's'} · $obsCount values',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDayReport(
    String dayKey,
    List<ReportRecord> reports,
  ) async {
    final label = DateFormat('d MMM yyyy').format(DateTime.parse(dayKey));
    final obs = widget.store.observations
        .where((o) => reports.any((r) => r.id == o.reportId))
        .toList()
      ..sort((a, b) => a.parameterName.compareTo(b.parameterName));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Complete report · $label'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'Merged from ${reports.map((r) => r.title).join(', ')}',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final o in obs)
                ListTile(
                  dense: true,
                  title: Text(o.parameterName),
                  trailing: Text(
                    '${o.valueReported} ${o.unitReported}'.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _visitCard(VisitRecord v) {
    final when = DateFormat('d MMM yyyy').format(v.visitedAt);
    final sub = [
      if (v.providerName?.isNotEmpty == true) v.providerName!,
      if (v.providerClinic?.isNotEmpty == true) v.providerClinic!,
    ].join(' · ');
    return Material(
      color: BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
          border: Border.all(color: BodylineColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              v.reason?.isNotEmpty == true ? v.reason! : 'Visit',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              sub.isEmpty ? when : '$when · $sub',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _docCard(AttachmentRecord d) {
    final name = (d.fileName?.trim().isNotEmpty == true)
        ? d.fileName!
        : '${d.ownerType} file';
    final kb = (d.byteSize / 1024).toStringAsFixed(0);
    return Material(
      color: BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        onTap: () async {
          try {
            final file = await widget.store.materializeAttachment(d);
            await OpenFilex.open(file.path);
          } catch (_) {}
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
            border: Border.all(color: BodylineColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.attach_file, color: BodylineColors.tealDark),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      '${d.ownerType} · $kb KB',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? BodylineColors.ink : BodylineColors.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? BodylineColors.ink : BodylineColors.outlineSoft,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? BodylineColors.onInk : BodylineColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportDetailPane extends StatefulWidget {
  const _ReportDetailPane({
    super.key,
    required this.store,
    required this.report,
    required this.onChanged,
  });

  final LocalStore store;
  final ReportRecord report;
  final VoidCallback onChanged;

  @override
  State<_ReportDetailPane> createState() => _ReportDetailPaneState();
}

class _ReportDetailPaneState extends State<_ReportDetailPane> {
  List<AttachmentRecord> _atts = const [];
  VisitRecord? _linkedVisit;

  LocalStore get store => widget.store;
  ReportRecord get report => widget.report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ReportDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.id != widget.report.id) _load();
  }

  Future<void> _load() async {
    final atts = await store.listAttachments(
      ownerType: 'report',
      ownerId: report.id,
    );
    VisitRecord? linked;
    try {
      final visits = await store.listVisits(report.profileId);
      if (visits.isNotEmpty) {
        visits.sort((a, b) =>
            (a.visitedAt.difference(report.collectedAt).abs())
                .compareTo(b.visitedAt.difference(report.collectedAt).abs()));
        final best = visits.first;
        if (best.visitedAt.difference(report.collectedAt).abs().inDays <= 30) {
          linked = best;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _atts = atts;
      _linkedVisit = linked;
    });
  }

  Future<void> _openOriginal() async {
    if (_atts.isEmpty) {
      await _attachOriginal();
      return;
    }
    try {
      final file = await store.materializeAttachment(_atts.first);
      await OpenFilex.open(file.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that file.')),
      );
    }
  }

  Future<void> _attachOriginal() async {
    final files = await pickClinicalFiles();
    if (files.isEmpty) return;
    await attachPendingFiles(
      store: store,
      ownerType: 'report',
      ownerId: report.id,
      files: files,
    );
    widget.onChanged();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('File saved encrypted on this device.')),
    );
  }


  Future<void> _editValues() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualPanelScreen(
          store: store,
          editReport: report,
          onSaved: widget.onChanged,
        ),
      ),
    );
    if (changed == true && mounted) {
      widget.onChanged();
      setState(() {});
    }
  }

  void _openFullReport() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportDetailScreen(
          store: store,
          report: report,
          onChanged: () {
            widget.onChanged();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this report?'),
        content: const Text(
          'Values and the original file on this report are removed from this device. This cannot be undone here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: BodylineColors.danger,
              foregroundColor: BodylineColors.onInk,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await store.deleteReport(report.id);
    widget.onChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report deleted.')),
    );
  }

  Color _valueColor(ObservationRecord o) {
    if (o.flag == ObservationFlag.high ||
        o.flag == ObservationFlag.criticalHigh ||
        o.flag == ObservationFlag.abnormal) {
      return BodylineColors.orange;
    }
    if (o.flag == ObservationFlag.low ||
        o.flag == ObservationFlag.criticalLow) {
      return BodylineColors.blue;
    }
    return BodylineColors.ink;
  }

  @override
  Widget build(BuildContext context) {
    final obs = store.observations
        .where((o) => o.reportId == report.id)
        .toList()
      ..sort((a, b) => a.parameterName.compareTo(b.parameterName));
    final flagged = obs
        .where((o) => o.flag != null && o.flag != ObservationFlag.normal)
        .toList();
    final fmt = DateFormat('d MMM yyyy');
    final short = DateFormat('d MMM');
    final preview = obs;

    final linkedLabel = _linkedVisit == null
        ? 'None linked'
        : '${short.format(_linkedVisit!.visitedAt)}'
            '${_linkedVisit!.reason != null && _linkedVisit!.reason!.isNotEmpty ? ' · ${_linkedVisit!.reason}' : ''}';

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
          ReportTitleText(
            report.title,
            maxLines: 2,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 24,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Collected ${fmt.format(report.collectedAt)} · ${obs.length} values'
            '${_atts.isEmpty ? '' : ' · ${_atts.length} file${_atts.length == 1 ? '' : 's'}'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _openOriginal,
                style: OutlinedButton.styleFrom(
                  foregroundColor: BodylineColors.ink,
                  side: BorderSide(color: BodylineColors.border),
                  minimumSize: const Size(0, 40),
                  shape: const StadiumBorder(),
                ),
                icon: const Icon(Icons.description_outlined, size: 16),
                label: Text(_atts.isEmpty ? 'Attach original' : 'Open original',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              OutlinedButton(
                onPressed: _editValues,
                style: OutlinedButton.styleFrom(
                  foregroundColor: BodylineColors.ink,
                  side: BorderSide(color: BodylineColors.border),
                  minimumSize: const Size(0, 40),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Edit values',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              OutlinedButton(
                onPressed: _openFullReport,
                style: OutlinedButton.styleFrom(
                  foregroundColor: BodylineColors.ink,
                  side: BorderSide(color: BodylineColors.border),
                  minimumSize: const Size(0, 40),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Full report',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              OutlinedButton(
                onPressed: _confirmDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: BodylineColors.danger,
                  side: BorderSide(color: BodylineColors.danger),
                  minimumSize: const Size(0, 40),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Delete',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat('Values', '${obs.length}', 'all verified'),
              const SizedBox(width: 10),
              _stat(
                'Flagged',
                '${flagged.length}',
                flagged.isEmpty
                    ? 'none'
                    : flagged
                        .take(2)
                        .map((o) =>
                            '${o.parameterName.split(' ').first} ${o.flag == ObservationFlag.low || o.flag == ObservationFlag.criticalLow ? 'low' : 'high'}')
                        .join(' · '),
                accent: flagged.isNotEmpty ? BodylineColors.orange : null,
              ),
              const SizedBox(width: 10),
              _stat('Linked visit', '', linkedLabel),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Parameter',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              SizedBox(
                width: 72,
                child: Text(
                  'Value',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 56,
                child: Text(
                  'Unit',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              SizedBox(
                width: 100,
                child: Text(
                  'Lab range',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          Divider(color: BodylineColors.divider),
          Expanded(
            child: obs.isEmpty
                ? Center(
                    child: Text(
                      'No values on this report.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: preview.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: BodylineColors.divider),
                    itemBuilder: (context, i) {
                      final o = preview[i];
                      final range = (o.refLow != null || o.refHigh != null)
                          ? '${o.refLow ?? '\u2014'}\u2013${o.refHigh ?? '\u2014'}'
                          : '\u2014';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                o.parameterName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 72,
                              child: Text(
                                o.valueReported,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: _valueColor(o),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 56,
                              child: Text(
                                o.unitReported,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: Text(
                                range,
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.bodySmall,
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

  Widget _stat(String label, String value, String sub, {Color? accent}) {
    return Expanded(
      child: Container(
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
            if (value.isNotEmpty)
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: accent ?? BodylineColors.ink,
                ),
              ),
            Text(
              sub,
              maxLines: value.isEmpty ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: accent ?? BodylineColors.inkSubtle,
                fontWeight: accent != null ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
