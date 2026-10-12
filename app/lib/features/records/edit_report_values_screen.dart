import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../desktop.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../../widgets/report_title.dart';

/// Edit values (and units / lab range) on an imported or manual report.
class EditReportValuesScreen extends StatefulWidget {
  const EditReportValuesScreen({
    super.key,
    required this.store,
    required this.report,
    required this.onChanged,
  });

  final LocalStore store;
  final ReportRecord report;
  final VoidCallback onChanged;

  @override
  State<EditReportValuesScreen> createState() => _EditReportValuesScreenState();
}

class _RowEditors {
  _RowEditors(ObservationRecord o)
      : observation = o,
        value = TextEditingController(text: o.valueReported),
        unit = TextEditingController(text: o.unitReported),
        refLow = TextEditingController(
          text: o.refLow == null ? '' : _fmtNum(o.refLow!),
        ),
        refHigh = TextEditingController(
          text: o.refHigh == null ? '' : _fmtNum(o.refHigh!),
        );

  final ObservationRecord observation;
  final TextEditingController value;
  final TextEditingController unit;
  final TextEditingController refLow;
  final TextEditingController refHigh;

  void dispose() {
    value.dispose();
    unit.dispose();
    refLow.dispose();
    refHigh.dispose();
  }

  static String _fmtNum(double n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toString();
  }
}

class _EditReportValuesScreenState extends State<EditReportValuesScreen> {
  late final List<_RowEditors> _rows;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final obs = widget.store.observations
        .where((o) => o.reportId == widget.report.id && !o.deleted)
        .toList()
      ..sort((a, b) => a.parameterName.compareTo(b.parameterName));
    _rows = [for (final o in obs) _RowEditors(o)];
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  double? _parseOpt(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', ''));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      for (final r in _rows) {
        final v = r.value.text.trim();
        if (v.isEmpty) continue;
        final low = _parseOpt(r.refLow.text);
        final high = _parseOpt(r.refHigh.text);
        final clearRefs = r.refLow.text.trim().isEmpty && r.refHigh.text.trim().isEmpty;
        await widget.store.updateObservation(
          id: r.observation.id,
          valueReported: v,
          unitReported: r.unit.text.trim(),
          refLow: low,
          refHigh: high,
          clearRefs: clearRefs,
        );
      }
      widget.onChanged();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save those values. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = useWideShell(context);
    final hPad = wide ? DesktopLayout.mainPaddingH : 20.0;

    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(
        title: const Text('Edit values'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: _rows.isEmpty
          ? Center(
              child: Text(
                'No values on this report.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 40),
              children: [
                ReportTitleText(
                  widget.report.title,
                  maxLines: 2,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Change a value, unit, or lab range. Flags update from the range you set.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                for (final r in _rows) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    decoration: BoxDecoration(
                      color: BodylineColors.surface,
                      borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
                      border: Border.all(color: BodylineColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          r.observation.parameterName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: r.value,
                                decoration: const InputDecoration(
                                  labelText: 'Value',
                                  isDense: true,
                                ),
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: r.unit,
                                decoration: const InputDecoration(
                                  labelText: 'Unit',
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: r.refLow,
                                decoration: const InputDecoration(
                                  labelText: 'Lab low',
                                  isDense: true,
                                ),
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,\-]'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: r.refHigh,
                                decoration: const InputDecoration(
                                  labelText: 'Lab high',
                                  isDense: true,
                                ),
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,\-]'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: BodylineColors.ink,
                    foregroundColor: BodylineColors.onInk,
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Save changes',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
    );
  }
}
