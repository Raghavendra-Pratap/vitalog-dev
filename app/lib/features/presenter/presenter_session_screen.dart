import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/report_title.dart';
import 'presenter_filter.dart';

class PresenterSessionScreen extends StatefulWidget {
  const PresenterSessionScreen({
    super.key,
    required this.store,
    required this.filter,
  });

  final LocalStore store;
  final PresenterFilter filter;

  @override
  State<PresenterSessionScreen> createState() => _PresenterSessionScreenState();
}

class _PresenterSessionScreenState extends State<PresenterSessionScreen> {
  var _loading = true;
  String _profileName = '';
  final _labRows = <_LabRow>[];
  final _visitRows = <_VisitRow>[];
  final _procRows = <_ProcRow>[];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _load() async {
    final store = widget.store;
    final filter = widget.filter;
    final profile = store.profiles.where((p) => p.id == filter.profileId);
    _profileName = profile.isEmpty ? 'Patient' : profile.first.name;

    final links = <String, String>{};
    for (final o in store.observations) {
      if (o.profileId != filter.profileId) continue;
      if (links.containsKey(o.parameterCode)) continue;
      final sys = await store.systemForParameter(o.parameterCode);
      if (sys != null) links[o.parameterCode] = sys;
    }

    if (filter.includeLabs) {
      final reports = store.reports
          .where(
            (r) =>
                r.profileId == filter.profileId &&
                filter.includesDate(r.collectedAt),
          )
          .toList()
        ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
      for (final r in reports) {
        final obs = store.observations
            .where((o) => o.reportId == r.id && !o.deleted)
            .where((o) => filter.includesSystem(links[o.parameterCode]))
            .toList();
        if (obs.isEmpty) continue;
        List<AttachmentRecord> atts = const [];
        if (filter.includeAttachments) {
          atts = await store.listAttachments(
            ownerType: 'report',
            ownerId: r.id,
          );
        }
        _labRows.add(_LabRow(report: r, observations: obs, attachments: atts));
      }
    }

    if (filter.includeVisits) {
      final visits = await store.listVisits(filter.profileId);
      for (final v in visits) {
        if (!filter.includesDate(v.visitedAt)) continue;
        List<AttachmentRecord> atts = const [];
        if (filter.includeAttachments) {
          atts = await store.listAttachments(
            ownerType: 'visit',
            ownerId: v.id,
          );
        }
        _visitRows.add(_VisitRow(visit: v, attachments: atts));
      }
    }

    if (filter.includeProcedures) {
      final procs = await store.listProcedures(filter.profileId);
      for (final p in procs) {
        List<AttachmentRecord> atts = const [];
        if (filter.includeAttachments) {
          atts = await store.listAttachments(
            ownerType: 'procedure',
            ownerId: p.id,
          );
        }
        _procRows.add(_ProcRow(item: p, attachments: atts));
      }
    }

    // Attachments-only: if labs/visits/procs off but attachments on,
    // still surface orphaned files is out of scope — kinds gate owners.
    if (mounted) setState(() => _loading = false);
  }

  Future<bool> _confirmEnd() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End presentation?'),
        content: const Text('Returns to the normal Vitalog screens.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep presenting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _end() async {
    if (!await _confirmEnd()) return;
    if (!mounted) return;
    // Pop session; leave setup underneath so user can adjust filters.
    Navigator.of(context).pop();
  }

  Future<void> _openAtt(AttachmentRecord a) async {
    try {
      final file = await widget.store.materializeAttachment(a);
      await OpenFilex.open(file.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that file on this device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    final empty = !_loading &&
        _labRows.isEmpty &&
        _visitRows.isEmpty &&
        _procRows.isEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!await _confirmEnd()) return;
        if (!mounted) return;
        Navigator.of(this.context).pop();
      },
      child: Scaffold(
        backgroundColor: BodylineColors.paper,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vitalog · Presenting',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: BodylineColors.tealDark,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _profileName,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'On this device only · values vs the lab’s printed range',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: _end,
                      style: FilledButton.styleFrom(
                        backgroundColor: BodylineColors.ink,
                        foregroundColor: BodylineColors.onInk,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('End presentation'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : empty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'No records match these filters.\nGo back and widen systems, kinds, or dates.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 17, height: 1.4),
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
                            children: [
                              if (_labRows.isNotEmpty) ...[
                                Text('Labs', style: _sectionStyle(context)),
                                const SizedBox(height: 12),
                                for (final row in _labRows) ...[
                                  Text(
                                    '${displayReportTitle(row.report.title)} · ${df.format(row.report.collectedAt)}',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  for (final o in row.observations)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  o.parameterName,
                                                  style: const TextStyle(
                                                    fontSize: 17,
                                                    height: 1.25,
                                                  ),
                                                ),
                                                if (o.flag != null)
                                                  Text(
                                                    flagLabel(o.flag!),
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: BodylineColors
                                                          .inkSubtle,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '${o.valueReported} ${o.unitReported}'
                                                .trim(),
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          if (o.refLow != null ||
                                              o.refHigh != null)
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                '  ${o.refLow ?? '—'}–${o.refHigh ?? '—'}',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color:
                                                      BodylineColors.inkSubtle,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  if (row.attachments.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    for (final a in row.attachments)
                                      _attTile(a),
                                  ],
                                  const SizedBox(height: 20),
                                ],
                              ],
                              if (_visitRows.isNotEmpty) ...[
                                Text('Visits', style: _sectionStyle(context)),
                                const SizedBox(height: 12),
                                for (final row in _visitRows) ...[
                                  Text(
                                    df.format(row.visit.visitedAt),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                  if ((row.visit.reason ?? '').isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        row.visit.reason!,
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ),
                                  if ((row.visit.diagnosis ?? '').isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        row.visit.diagnosis!,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  for (final a in row.attachments) _attTile(a),
                                  const SizedBox(height: 16),
                                ],
                              ],
                              if (_procRows.isNotEmpty) ...[
                                Text(
                                  'Treatments',
                                  style: _sectionStyle(context),
                                ),
                                const SizedBox(height: 12),
                                for (final row in _procRows) ...[
                                  Text(
                                    [
                                      row.item.title,
                                      if ((row.item.subtitle ?? '').isNotEmpty)
                                        row.item.subtitle!,
                                    ].join(' — '),
                                    style: const TextStyle(
                                      fontSize: 17,
                                      height: 1.3,
                                    ),
                                  ),
                                  for (final a in row.attachments) _attTile(a),
                                  const SizedBox(height: 12),
                                ],
                              ],
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attTile(AttachmentRecord a) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.attach_file, size: 20),
      title: Text(
        a.fileName ?? 'Attachment',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15),
      ),
      trailing: const Text('Open', style: TextStyle(fontSize: 13)),
      onTap: () => _openAtt(a),
    );
  }

  TextStyle _sectionStyle(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall!.copyWith(
            fontWeight: FontWeight.w800,
            color: BodylineColors.tealDark,
          );
}

class _LabRow {
  _LabRow({
    required this.report,
    required this.observations,
    required this.attachments,
  });
  final ReportRecord report;
  final List<ObservationRecord> observations;
  final List<AttachmentRecord> attachments;
}

class _VisitRow {
  _VisitRow({required this.visit, required this.attachments});
  final VisitRecord visit;
  final List<AttachmentRecord> attachments;
}

class _ProcRow {
  _ProcRow({required this.item, required this.attachments});
  final MedicalItem item;
  final List<AttachmentRecord> attachments;
}
