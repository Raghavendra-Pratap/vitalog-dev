import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../data/local_store.dart';
import '../../data/health_connect_service.dart';
import '../../data/models.dart';
import '../../data/ref_range_suggestions.dart';
import '../../data/panel_catalog.dart';
import '../../theme/tokens.dart';
import '../import/import_text_screen.dart';
import '../../widgets/clinical_attachments.dart';
import '../../widgets/month_year_date_picker.dart';
import '../../widgets/ref_range_fields.dart';

class ManualPanelScreen extends StatefulWidget {
  const ManualPanelScreen({
    super.key,
    required this.store,
    required this.onSaved,
    this.editReport,
    this.seedParameterCode,
  });

  final LocalStore store;
  final VoidCallback onSaved;

  /// When set, opens as Edit values: prefill, lock panel, update in place.
  final ReportRecord? editReport;

  /// When set (and not editing), open One test prefilled for this catalogue code.
  final String? seedParameterCode;

  bool get isEditing => editReport != null;

  @override
  State<ManualPanelScreen> createState() => _ManualPanelScreenState();
}

class _ManualPanelScreenState extends State<ManualPanelScreen> {
  List<PanelDef> _panels = List.of(seededPanels);
  PanelDef? _panel;
  final Map<String, TextEditingController> _values = {};
  final Map<String, RefRangeEditState> _refs = {};
  DateTime _collected = DateTime.now();
  var _loading = true;
  var _oneTest = false;
  ParamDef? _singleParam;
  final List<PendingClinicalFile> _pendingFiles = [];

  @override
  void initState() {
    super.initState();
    _loadPanels();
  }

  Future<void> _loadPanels() async {
    try {
      final fromDb = await widget.store.catalogPanels();
      if (fromDb.isNotEmpty) _panels = fromDb;
    } catch (_) {
      // Fall back to seed list (offline / catalog missing).
    }
    if (!mounted) return;
    final edit = widget.editReport;
    if (edit != null) {
      await _bindEdit(edit);
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final seed = widget.seedParameterCode?.trim();
    if (seed != null && seed.isNotEmpty) {
      final p = await widget.store.catalogParameter(seed);
      if (!mounted) return;
      if (p != null) {
        setState(() {
          _oneTest = true;
          _bindSingle(p);
          _loading = false;
        });
        return;
      }
    }
    setState(() {
      if (_panels.isNotEmpty) _bindPanel(_panels.first);
      _loading = false;
    });
  }

  PanelDef _resolvePanelForEdit(
    ReportRecord report,
    List<ObservationRecord> obs,
  ) {
    final title = report.title.trim().toLowerCase();
    for (final p in _panels) {
      if (p.name.trim().toLowerCase() == title) {
        return _withOrphanParams(p, obs);
      }
    }
    // Soft match: "Diabetes Panel" vs title "Diabetes"
    for (final p in _panels) {
      final n = p.name.trim().toLowerCase();
      if (n.startsWith(title) || title.startsWith(n.split(' ').first)) {
        final codes = {for (final o in obs) o.parameterCode};
        final hit = p.parameters.where((x) => codes.contains(x.code)).length;
        if (hit > 0) return _withOrphanParams(p, obs);
      }
    }
    final codes = {for (final o in obs) o.parameterCode};
    PanelDef? best;
    var bestScore = 0;
    for (final p in _panels) {
      final score = p.parameters.where((x) => codes.contains(x.code)).length;
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }
    if (best != null && bestScore > 0) {
      return _withOrphanParams(best, obs);
    }
    return PanelDef(
      '_edit',
      report.title,
      [
        for (final o in obs)
          ParamDef(o.parameterCode, o.parameterName, o.unitReported),
      ],
    );
  }

  PanelDef _withOrphanParams(PanelDef panel, List<ObservationRecord> obs) {
    final known = {for (final p in panel.parameters) p.code};
    final extras = <ParamDef>[
      for (final o in obs)
        if (!known.contains(o.parameterCode))
          ParamDef(o.parameterCode, o.parameterName, o.unitReported),
    ];
    if (extras.isEmpty) return panel;
    return PanelDef(panel.code, panel.name, [...panel.parameters, ...extras]);
  }

  Future<void> _bindEdit(ReportRecord report) async {
    final obs = widget.store.observations
        .where((o) => o.reportId == report.id && !o.deleted)
        .toList();
    final panel = _resolvePanelForEdit(report, obs);
    final byCode = <String, ObservationRecord>{
      for (final o in obs) o.parameterCode: o,
    };

    for (final c in _values.values) {
      c.dispose();
    }
    for (final r in _refs.values) {
      r.dispose();
    }
    _values.clear();
    _refs.clear();
    _panel = panel;
    _oneTest = false;
    _singleParam = null;
    _collected = report.collectedAt;
    _pendingFiles.clear();

    final emptyCodes = <String>[];
    for (final p in panel.parameters) {
      final o = byCode[p.code];
      _values[p.code] = TextEditingController(text: o?.valueReported ?? '');
      _refs[p.code] = _refStateForEdit(p.code, o);
      if (o == null) emptyCodes.add(p.code);
    }
    if (emptyCodes.isNotEmpty) {
      await _fillCatalogueDefaults(emptyCodes);
    }
  }

  RefRangeEditState _refStateForEdit(String parameterCode, ObservationRecord? o) {
    final pid = widget.store.activeProfileId;
    final rangeSug = pid == null
        ? const <RefRangeSuggestion>[]
        : widget.store.refRangeSuggestions(pid, parameterCode);
    final bandSug = pid == null
        ? const <RefBandSetSuggestion>[]
        : widget.store.refBandSetSuggestions(pid, parameterCode);

    if (o != null && o.refBands != null && o.refBands!.isNotEmpty) {
      final state = RefRangeEditState(
        initialBands: o.refBands,
        rangeSuggestions: rangeSug,
        bandSetSuggestions: bandSug,
      );
      if (state.mode == RefRangeMode.condition) {
        var matched = false;
        for (var i = 0; i < (state.parsedBands?.length ?? 0); i++) {
          final b = state.parsedBands![i];
          if (b.low == o.refLow && b.high == o.refHigh) {
            state.selectedConditionIndex = i;
            matched = true;
            break;
          }
        }
        if (!matched) state.selectedConditionIndex = 0;
      }
      return state;
    }

    final low = TextEditingController(
      text: o?.refLow == null ? '' : formatRefNum(o!.refLow!),
    );
    final high = TextEditingController(
      text: o?.refHigh == null ? '' : formatRefNum(o!.refHigh!),
    );
    final state = RefRangeEditState(
      low: low,
      high: high,
      rangeSuggestions: rangeSug,
      bandSetSuggestions: bandSug,
    );
    if (o == null) {
      if (bandSug.isNotEmpty &&
          refsAndBandsEmpty(
            lowText: state.low.text,
            highText: state.high.text,
            bands: state.parsedBands,
          )) {
        autofillBandsFromHistory(state: state);
      } else {
        autofillRefsFromHistory(
          low: state.low,
          high: state.high,
          suggestions: rangeSug,
        );
      }
    }
    return state;
  }

  void _bindPanel(PanelDef panel) {
    for (final c in _values.values) {
      c.dispose();
    }
    for (final r in _refs.values) {
      r.dispose();
    }
    _values.clear();
    _refs.clear();
    for (final p in panel.parameters) {
      _values[p.code] = TextEditingController();
      _refs[p.code] = _newRefState(p.code);
    }
    _panel = panel;
    _singleParam = null;
    _fillCatalogueDefaults([for (final p in panel.parameters) p.code]);
  }

  RefRangeEditState _newRefState(String parameterCode) {
    final pid = widget.store.activeProfileId;
    final rangeSug = pid == null
        ? const <RefRangeSuggestion>[]
        : widget.store.refRangeSuggestions(pid, parameterCode);
    final bandSug = pid == null
        ? const <RefBandSetSuggestion>[]
        : widget.store.refBandSetSuggestions(pid, parameterCode);
    final state = RefRangeEditState(
      rangeSuggestions: rangeSug,
      bandSetSuggestions: bandSug,
      preferStages: bandSug.isNotEmpty && rangeSug.isEmpty,
    );
    if (bandSug.isNotEmpty &&
        refsAndBandsEmpty(
          lowText: state.low.text,
          highText: state.high.text,
          bands: state.parsedBands,
        )) {
      autofillBandsFromHistory(state: state);
    } else {
      autofillRefsFromHistory(
        low: state.low,
        high: state.high,
        suggestions: rangeSug,
      );
    }
    return state;
  }

  void _bindSingle(ParamDef p) {
    for (final c in _values.values) {
      c.dispose();
    }
    for (final r in _refs.values) {
      r.dispose();
    }
    _values
      ..clear()
      ..[p.code] = TextEditingController();
    _refs
      ..clear()
      ..[p.code] = _newRefState(p.code);
    _singleParam = p;
    _panel = null;
    _fillCatalogueDefaults([p.code]);
  }

  /// Prefill Low/High from catalogue defaults when empty (history already applied).
  Future<void> _fillCatalogueDefaults(List<String> codes) async {
    final pid = widget.store.activeProfileId;
    String? sex;
    if (pid != null) {
      for (final p in widget.store.profiles) {
        if (p.id == pid) {
          sex = p.sex;
          break;
        }
      }
    }
    var changed = false;
    for (final code in codes) {
      final state = _refs[code];
      if (state == null || state.stages) continue;
      if (state.low.text.trim().isNotEmpty || state.high.text.trim().isNotEmpty) {
        continue;
      }
      final def = await widget.store.defaultRefRange(code, sex: sex);
      if (def == null) continue;
      if (def.low != null) state.low.text = formatRefNum(def.low!);
      if (def.high != null) state.high.text = formatRefNum(def.high!);
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in _values.values) {
      c.dispose();
    }
    for (final r in _refs.values) {
      r.dispose();
    }
    super.dispose();
  }

  /// First parameter whose name/code/shortName contains [q] (case-insensitive).
  ParamDef? _panelParamMatch(PanelDef panel, String q) {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final param in panel.parameters) {
      final short = param.shortName?.toLowerCase() ?? '';
      if (param.name.toLowerCase().contains(needle) ||
          param.code.toLowerCase().contains(needle) ||
          (short.isNotEmpty && short.contains(needle))) {
        return param;
      }
    }
    return null;
  }

  bool _panelMatchesQuery(PanelDef panel, String q) {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return true;
    if (panel.name.toLowerCase().contains(needle) ||
        panel.code.toLowerCase().contains(needle)) {
      return true;
    }
    return _panelParamMatch(panel, needle) != null;
  }

  Future<void> _pickPanel() async {
    final chosen = await showModalBottomSheet<PanelDef>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        var q = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = [
              for (final p in _panels)
                if (_panelMatchesQuery(p, q)) p,
            ];
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Search panels or tests',
                          helperText: 'Type a panel or a parameter name',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setLocal(() => q = v),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final p = filtered[i];
                          final hit = _panelParamMatch(p, q);
                          final subtitle = hit == null
                              ? '${p.parameters.length} tests · ${p.code}'
                              : 'Includes ${hit.name} · ${p.code}';
                          return ListTile(
                            title: Text(p.name),
                            subtitle: Text(subtitle),
                            onTap: () => Navigator.pop(ctx, p),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (chosen == null || !mounted) return;
    setState(() => _bindPanel(chosen));
  }

  Future<void> _pickSingleTest() async {
    final chosen = await showModalBottomSheet<ParamDef>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        var q = '';
        var results = <ParamDef>[];
        var searching = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> run(String v) async {
              setLocal(() {
                q = v;
                searching = true;
              });
              final rows = await widget.store.searchCatalogParameters(v);
              if (!ctx.mounted) return;
              setLocal(() {
                results = rows;
                searching = false;
              });
            }

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Search tests (catalogue)',
                          prefixIcon: Icon(Icons.search),
                          helperText: '193 parameters on this device',
                        ),
                        onChanged: run,
                      ),
                    ),
                    if (searching)
                      const LinearProgressIndicator(minHeight: 2)
                    else
                      const SizedBox(height: 2),
                    Expanded(
                      child: q.trim().isEmpty
                          ? const Center(
                              child: Text('Type a test name or code'),
                            )
                          : results.isEmpty
                              ? const Center(child: Text('No matches'))
                              : ListView.builder(
                                  itemCount: results.length,
                                  itemBuilder: (_, i) {
                                    final p = results[i];
                                    return ListTile(
                                      title: Text(p.name),
                                      subtitle: Text(
                                        '${p.subtitleCode}'
                                        '${p.unit.isEmpty ? '' : ' · ${p.unit}'}',
                                      ),
                                      onTap: () => Navigator.pop(ctx, p),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (chosen == null || !mounted) return;
    setState(() => _bindSingle(chosen));
  }

  void _maybeWriteHealth(List<ManualObservationInput> inputs) {
    final hc = HealthConnectService();
    for (final v in inputs) {
      final code = v.parameterCode.toLowerCase();
      final parsed = double.tryParse(v.valueReported.trim());
      if (parsed == null) continue;
      if (code == 'weight' ||
          code == 'glu_cap' ||
          code == 'glu_r' ||
          code == 'glu_f' ||
          code == 'glu_pp') {
        // ignore: unawaited_futures
        hc.writeReading(
          parameterCode: code,
          value: parsed,
          unit: v.unitReported,
          at: _collected,
        );
      }
    }
    final sys = inputs.where((v) => v.parameterCode.toLowerCase() == 'bp_sys');
    final dia = inputs.where((v) => v.parameterCode.toLowerCase() == 'bp_dia');
    if (sys.isNotEmpty && dia.isNotEmpty) {
      final s = int.tryParse(sys.first.valueReported.trim());
      final d = int.tryParse(dia.first.valueReported.trim());
      if (s != null && d != null) {
        // ignore: unawaited_futures
        hc.writeBloodPressure(systolic: s, diastolic: d, at: _collected);
      }
    }
  }

  Future<void> _save({bool continueAfter = false}) async {
    final profileId = widget.store.activeProfileId;
    if (profileId == null) return;

    final params = _oneTest
        ? (_singleParam == null ? <ParamDef>[] : [_singleParam!])
        : (_panel?.parameters ?? const <ParamDef>[]);
    if (params.isEmpty) return;

    final inputs = <ManualObservationInput>[];
    for (final p in params) {
      final raw = _values[p.code]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final snap = _refs[p.code]?.snapshot() ??
          (low: null, high: null, bands: null);
      inputs.add(
        ManualObservationInput(
          parameterCode: p.code,
          parameterName: p.name,
          valueReported: raw,
          unitReported: p.unit,
          refLow: snap.low,
          refHigh: snap.high,
          refBands: snap.bands,
        ),
      );
    }
    if (inputs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one value.')),
      );
      return;
    }

    for (final p in params) {
      final raw = _values[p.code]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final state = _refs[p.code];
      if (state != null &&
          state.mode == RefRangeMode.condition &&
          !state.hasSelectedCondition) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Select a condition for ${p.name}.'),
          ),
        );
        return;
      }
    }

    final edit = widget.editReport;
    if (edit != null) {
      await widget.store.updateManualPanel(
        reportId: edit.id,
        collectedAt: _collected,
        values: inputs,
      );
      _maybeWriteHealth(inputs);
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop(true);
      return;
    }

    final title = _oneTest
        ? (_singleParam?.name ?? 'Manual entry')
        : (_panel?.name ?? 'Manual panel');

    final report = await widget.store.addManualPanel(
      profileId: profileId,
      title: title,
      collectedAt: _collected,
      values: inputs,
    );
    if (report == null) return;
    if (_pendingFiles.isNotEmpty) {
      await attachPendingFiles(
        store: widget.store,
        ownerType: 'report',
        ownerId: report.id,
        files: _pendingFiles,
      );
    }
    _maybeWriteHealth(inputs);
    if (!mounted) return;
    widget.onSaved();
    if (continueAfter) {
      _pendingFiles.clear();
      if (_oneTest && _singleParam != null) {
        _bindSingle(_singleParam!);
      } else if (_panel != null) {
        _bindPanel(_panel!);
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved — add another')),
      );
      return;
    }
    Navigator.of(context).pop();
  }


  Widget _paramEntryCard(ParamDef p) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: BodylineColors.border),
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        color: BodylineColors.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              p.name,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              '${p.subtitleCode}${p.unit.isEmpty ? '' : ' · ${p.unit}'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: BodylineColors.inkSubtle,
                    height: 1.25,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _values[p.code],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: p.unit.isEmpty ? 'Value' : 'Value (${p.unit})',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),
            RefRangeEditor(
              state: _refs[p.code]!,
              dense: true,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final params = _oneTest
        ? (_singleParam == null ? <ParamDef>[] : [_singleParam!])
        : (_panel?.parameters ?? const <ParamDef>[]);

    final editing = widget.isEditing;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit values' : 'Add report'),
        actions: [
          if (!editing)
            TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ImportTextScreen(
                      store: widget.store,
                      onSaved: widget.onSaved,
                    ),
                  ),
                );
              },
              child: const Text('Paste / import'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            editing
                ? 'Update values and the lab’s printed range for this report. Panel stays fixed.'
                : 'Enter values and the lab’s printed range. We compare to that range — we do not diagnose.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Collection date'),
            subtitle: Text('${_collected.toLocal()}'.split(' ').first),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final d = await pickBodylineDate(
                context,
                initialDate: _collected,
                firstDate: DateTime(1990),
                lastDate: DateTime.now(),
                helpText: 'Collection date',
              );
              if (d != null) setState(() => _collected = d);
            },
          ),
          if (!editing) ...[
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Panel'), icon: Icon(Icons.view_list)),
                ButtonSegment(value: true, label: Text('One test'), icon: Icon(Icons.search)),
              ],
              selected: {_oneTest},
              onSelectionChanged: (s) {
                final next = s.first;
                setState(() {
                  _oneTest = next;
                  if (next) {
                    _panel = null;
                  } else if (_panels.isNotEmpty) {
                    _bindPanel(_panels.first);
                  }
                });
              },
            ),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 8),
          if (!editing && _oneTest) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _singleParam?.name ?? 'Choose a test',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _singleParam == null
                    ? 'Search all ${_panels.isEmpty ? '' : 'catalogue '}tests'
                    : '${_singleParam!.subtitleCode}'
                        '${_singleParam!.unit.isEmpty ? '' : ' · ${_singleParam!.unit}'}',
              ),
              trailing: const Icon(Icons.search),
              onTap: _pickSingleTest,
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _panel?.name ?? 'Choose a panel',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                editing
                    ? '${_panel?.parameters.length ?? 0} tests · panel locked'
                    : _panel == null
                        ? '${_panels.length} panels in catalogue'
                        : '${_panel!.parameters.length} tests · ${_panel!.code}',
              ),
              trailing: editing
                  ? const Icon(Icons.lock_outline, size: 18)
                  : const Icon(Icons.arrow_drop_down),
              onTap: editing ? null : _pickPanel,
            ),
          ],
          const SizedBox(height: 8),
          Divider(color: BodylineColors.divider),
          if (params.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                _oneTest
                    ? 'Search and pick a test to enter a value.'
                    : 'Pick a panel to enter values.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                // Responsive masonry: 1 / 2 / max 3 cols; tall Stage cards
                // reflow so shorter cards pack into open space.
                final w = constraints.maxWidth;
                final cols = w >= 1100 ? 3 : (w >= 640 ? 2 : 1);
                const gap = 14.0;
                return MasonryGridView.count(
                  key: ValueKey('params-$cols-${params.length}'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: cols,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  itemCount: params.length,
                  itemBuilder: (context, i) => _paramEntryCard(params[i]),
                );
              },
            ),
          if (!editing) ...[
            Text(
              'Original file (optional)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Attach the lab PDF or photo to open or share later. You can skip this.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (_pendingFiles.isNotEmpty)
              for (final f in _pendingFiles)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file, size: 18),
                  title: Text(f.fileName, style: const TextStyle(fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _pendingFiles.remove(f)),
                  ),
                ),
            OutlinedButton.icon(
              onPressed: () async {
                final files = await pickClinicalFiles();
                if (files.isEmpty) return;
                setState(() => _pendingFiles.addAll(files));
              },
              icon: const Icon(Icons.attach_file),
              label: Text(
                _pendingFiles.isEmpty
                    ? 'Attach PDF or image'
                    : 'Add another file',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: params.isEmpty
                        ? null
                        : () => _save(continueAfter: true),
                    child: const Text('Save and continue'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: params.isEmpty ? null : () => _save(),
                    child: const Text('Save report'),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 20),
            FilledButton(
              onPressed: params.isEmpty ? null : () => _save(),
              child: const Text('Save changes'),
            ),
          ],
        ],
      ),
    );
  }
}
