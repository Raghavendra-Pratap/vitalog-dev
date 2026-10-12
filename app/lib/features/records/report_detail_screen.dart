import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../desktop.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../../widgets/clinical_attachments.dart';
import '../../widgets/report_title.dart';
import '../../widgets/status_pill.dart';
import '../entry/manual_panel_screen.dart';

/// Full-report view — same information architecture as the Records detail pane,
/// with room to show every value (Parameter / Value / Unit / Lab range).
class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({
    super.key,
    required this.store,
    required this.report,
    required this.onChanged,
  });

  final LocalStore store;
  final ReportRecord report;
  final VoidCallback onChanged;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  List<AttachmentRecord> _atts = const [];
  VisitRecord? _linkedVisit;

  LocalStore get store => widget.store;
  ReportRecord get report => widget.report;

  @override
  void initState() {
    super.initState();
    _load();
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
        visits.sort((a, b) => (a.visitedAt.difference(report.collectedAt).abs())
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
    Navigator.of(context).pop();
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
    final wide = useWideShell(context);
    final fmt = DateFormat('d MMM yyyy');
    final short = DateFormat('d MMM');
    final obs = store.observations
        .where((o) => o.reportId == report.id)
        .toList()
      ..sort((a, b) => a.parameterName.compareTo(b.parameterName));
    final flagged = obs
        .where((o) => o.flag != null && o.flag != ObservationFlag.normal)
        .toList();
    final linkedLabel = _linkedVisit == null
        ? 'None linked'
        : '${short.format(_linkedVisit!.visitedAt)}'
            '${_linkedVisit!.reason != null && _linkedVisit!.reason!.isNotEmpty ? ' · ${_linkedVisit!.reason}' : ''}';

    final hPad = wide ? DesktopLayout.mainPaddingH : 20.0;

    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(
        title: ReportTitleText(report.title, maxLines: 1),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 40),
        children: [
          ReportTitleText(
            report.title,
            maxLines: 2,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: wide ? 28 : 24,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Collected ${fmt.format(report.collectedAt)} · ${obs.length} values'
            '${_atts.isEmpty ? '' : ' · ${_atts.length} file${_atts.length == 1 ? '' : 's'}'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 12),
          wide
              ? Wrap(
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
                      label: Text(
                        _atts.isEmpty ? 'Attach original' : 'Open original',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
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
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    OutlinedButton(
                      onPressed: _confirmDelete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BodylineColors.danger,
                        side: BorderSide(color: BodylineColors.danger),
                        minimumSize: const Size(0, 40),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Delete report',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Flexible(
                      child: OutlinedButton.icon(
                        onPressed: _openOriginal,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: BodylineColors.ink,
                          side: BorderSide(color: BodylineColors.border),
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: const StadiumBorder(),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.description_outlined, size: 15),
                        label: Text(
                          _atts.isEmpty ? 'Attach original' : 'Open original',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: OutlinedButton(
                        onPressed: _editValues,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: BodylineColors.ink,
                          side: BorderSide(color: BodylineColors.border),
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: const StadiumBorder(),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Edit values',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: OutlinedButton(
                        onPressed: _confirmDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: BodylineColors.danger,
                          side: BorderSide(color: BodylineColors.danger),
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: const StadiumBorder(),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Delete report',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: BodylineColors.surface,
              borderRadius: BorderRadius.circular(BodylineRadii.card),
              border: Border.all(color: BodylineColors.border),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              children: [
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
                      width: wide ? 88 : 72,
                      child: Text(
                        'Value',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    SizedBox(width: wide ? 16 : 12),
                    SizedBox(
                      width: wide ? 72 : 56,
                      child: Text(
                        'Unit',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    SizedBox(
                      width: wide ? 120 : 100,
                      child: Text(
                        'Lab range',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (wide) const SizedBox(width: 88),
                  ],
                ),
                Divider(color: BodylineColors.divider),
                if (obs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No values on this report.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  for (var i = 0; i < obs.length; i++) ...[
                    _valueRow(obs[i], wide: wide),
                    if (i < obs.length - 1)
                      Divider(height: 1, color: BodylineColors.divider),
                  ],
              ],
            ),
          ),
          if (_atts.isEmpty) ...[
            const SizedBox(height: 20),
            ClinicalAttachmentsSection(
              store: store,
              ownerType: 'report',
              ownerId: report.id,
              onChanged: () {
                widget.onChanged();
                _load();
              },
              title: 'Original file',
              emptyHint:
                  'Import usually attaches the PDF automatically. Add one here if it is missing.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _valueRow(ObservationRecord o, {required bool wide}) {
    final range = (o.refLow != null || o.refHigh != null)
        ? '${o.refLow ?? '\u2014'}\u2013${o.refHigh ?? '\u2014'}'
        : '\u2014';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
            width: wide ? 88 : 72,
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
          SizedBox(width: wide ? 16 : 12),
          SizedBox(
            width: wide ? 72 : 56,
            child: Text(
              o.unitReported,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SizedBox(
            width: wide ? 120 : 100,
            child: Text(
              range,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (wide) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 76,
              child: o.flag == null
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.centerRight,
                      child: StatusPill(flag: o.flag!),
                    ),
            ),
          ],
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
