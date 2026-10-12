import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../entry/manual_panel_screen.dart';
import '../../widgets/sparkline.dart';
import '../../widgets/trend_panel.dart';
import 'trend_screen.dart';
import '../visits/reminder_form.dart';

enum _Filter { all, flagged }
enum _SortMode { alpha, popular, crucial }

class TestsScreen extends StatefulWidget {
  const TestsScreen({
    super.key,
    required this.store,
    required this.onChanged,
    this.desktop = false,
    this.initialParameterCode,
  });

  final LocalStore store;
  final VoidCallback onChanged;
  final bool desktop;
  final String? initialParameterCode;

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  _SortMode _sort = _SortMode.popular;
  String? _selectedCode;
  Map<String, String> _systemByParam = {};

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.initialParameterCode;
    _loadSystems();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSystems() async {
    // Best-effort: parameter → system from organ summaries / observations names
    final map = <String, String>{};
    for (final o in widget.store.observations) {
      map.putIfAbsent(o.parameterCode, () => 'Other');
    }
    if (!mounted) return;
    setState(() => _systemByParam = map);
  }

  ProfileRecord? get _profile {
    final id = widget.store.activeProfileId;
    for (final p in widget.store.profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<ObservationRecord> get _latest {
    final id = widget.store.activeProfileId;
    final byCode = <String, ObservationRecord>{};
    final rows = widget.store.observations.where((o) => o.profileId == id).toList()
      ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
    for (final o in rows) {
      byCode.putIfAbsent(o.parameterCode, () => o);
    }
    return byCode.values.toList()
      ..sort((a, b) => a.parameterName.compareTo(b.parameterName));
  }

  List<ObservationRecord> get _filtered {
    var rows = _latest;
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows = rows
          .where((o) =>
              o.parameterName.toLowerCase().contains(q) ||
              o.parameterCode.toLowerCase().contains(q))
          .toList();
    }
    if (_filter == _Filter.flagged) {
      rows = rows
          .where((o) => o.flag != null && o.flag != ObservationFlag.normal)
          .toList();
    }
    final pid = widget.store.activeProfileId;
    final freq = <String, int>{};
    if (pid != null) {
      for (final o in widget.store.observations) {
        if (o.profileId != pid) continue;
        freq[o.parameterCode] = (freq[o.parameterCode] ?? 0) + 1;
      }
    }
    rows = [...rows];
    switch (_sort) {
      case _SortMode.alpha:
        rows.sort((a, b) => a.parameterName.compareTo(b.parameterName));
      case _SortMode.popular:
        rows.sort((a, b) {
          final c = (freq[b.parameterCode] ?? 0)
              .compareTo(freq[a.parameterCode] ?? 0);
          return c != 0 ? c : a.parameterName.compareTo(b.parameterName);
        });
      case _SortMode.crucial:
        int rank(ObservationRecord o) {
          if (o.flag == null || o.flag == ObservationFlag.normal) return 2;
          if (o.flag == ObservationFlag.criticalHigh ||
              o.flag == ObservationFlag.criticalLow) {
            return 0;
          }
          return 1;
        }
        rows.sort((a, b) {
          final c = rank(a).compareTo(rank(b));
          return c != 0 ? c : a.parameterName.compareTo(b.parameterName);
        });
    }
    return rows;
  }

  Map<String, List<double>> _historyMap(List<ObservationRecord> rows) {
    final pid = widget.store.activeProfileId;
    final out = <String, List<double>>{};
    if (pid == null) return out;
    for (final o in rows) {
      out[o.parameterCode] = widget.store
          .trendFor(pid, o.parameterCode)
          .where((x) => x.valueNum != null)
          .map((x) => x.valueNum!)
          .toList();
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.desktop) return _buildDesktop(context);
    return _buildMobile(context);
  }

  Widget _buildDesktop(BuildContext context) {
    final rows = _filtered;
    final history = _historyMap(rows);
    final fmt = DateFormat('d MMM');
    final flaggedCount = _latest
        .where((o) => o.flag != null && o.flag != ObservationFlag.normal)
        .length;

    final codes = rows.map((o) => o.parameterCode).toSet();
    final selectedCode = (_selectedCode != null && codes.contains(_selectedCode))
        ? _selectedCode
        : (rows.isEmpty ? null : rows.first.parameterCode);
    if (selectedCode != _selectedCode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedCode = selectedCode);
      });
    }
    ObservationRecord? selected;
    for (final o in rows) {
      if (o.parameterCode == selectedCode) {
        selected = o;
        break;
      }
    }

    // Group
    final groups = <String, List<ObservationRecord>>{};
    for (final o in rows) {
      final g = _systemByParam[o.parameterCode] ?? 'Other';
      groups.putIfAbsent(g, () => []).add(o);
    }
    final groupNames = groups.keys.toList()..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(DesktopLayout.mainPaddingH, 8, DesktopLayout.mainPaddingH, DesktopLayout.mainPaddingV),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: DesktopLayout.testsMasterCol,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search tests, e.g. TSH, HbA1c',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: BodylineColors.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: BodylineColors.outlineSoft),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: BodylineColors.outlineSoft),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    _chip('All', _filter == _Filter.all, () {
                      setState(() => _filter = _Filter.all);
                    }),
                    _chip(
                      'Flagged · $flaggedCount',
                      _filter == _Filter.flagged,
                      () => setState(() => _filter = _Filter.flagged),
                    ),
                    _chip('A–Z', _sort == _SortMode.alpha, () {
                      setState(() => _sort = _SortMode.alpha);
                    }),
                    _chip('Popular', _sort == _SortMode.popular, () {
                      setState(() => _sort = _SortMode.popular);
                    }),
                    _chip('Crucial', _sort == _SortMode.crucial, () {
                      setState(() => _sort = _SortMode.crucial);
                    }),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text(
                            'No tests yet.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : ListView(
                          children: [
                            for (final g in groupNames) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                                child: Text(
                                  g,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: BodylineColors.surface,
                                  borderRadius: BorderRadius.circular(
                                    BodylineRadii.card,
                                  ),
                                  border: Border.all(
                                    color: BodylineColors.border,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    for (var i = 0;
                                        i < groups[g]!.length;
                                        i++) ...[
                                      _desktopRow(
                                        groups[g]![i],
                                        history,
                                        fmt,
                                        selected:
                                            groups[g]![i].parameterCode ==
                                                _selectedCode,
                                      ),
                                      if (i < groups[g]!.length - 1)
                                        Divider(
                                          height: 1,
                                          color: BodylineColors.divider,
                                        ),
                                    ],
                                  ],
                                ),
                              ),
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
                      'Select a test to see its trend.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: BodylineColors.surface,
                      borderRadius: BorderRadius.circular(BodylineRadii.card),
                      border: Border.all(color: BodylineColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final row = selected;
                              if (row == null) return;
                              await showAddReminderDialog(
                                context,
                                store: widget.store,
                                initialTitle: 'Retest ${row.parameterName}',
                                targetCode: row.parameterCode,
                                kind: 'retest',
                              );
                              widget.onChanged();
                            },
                            icon: const Icon(Icons.notifications_none, size: 18),
                            label: const Text('Set reminder'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: TrendPanel(
                            key: ValueKey(selected.parameterCode),
                            store: widget.store,
                            parameterCode: selected.parameterCode,
                            title: selected.parameterName,
                            compact: true,
                            showHistory: true,
                            showRangeSelector: false,
                            onAddReading: () => _addReading(selected!.parameterCode),
                            onEditReading: _editReading,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }


  Future<void> _addReading(String parameterCode) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualPanelScreen(
          store: widget.store,
          onSaved: widget.onChanged,
          seedParameterCode: parameterCode,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editReading(ObservationRecord o) async {
    ReportRecord? report;
    for (final r in widget.store.reports) {
      if (r.id == o.reportId) {
        report = r;
        break;
      }
    }
    if (report == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualPanelScreen(
          store: widget.store,
          onSaved: widget.onChanged,
          editReport: report,
        ),
      ),
    );
    if (mounted) setState(() {});
  }


  bool _isTextResult(ObservationRecord o) {
    final raw = o.valueReported.trim();
    if (raw.isEmpty) return true;
    if (o.valueNum == null) return true;
    // Numeric-looking short values stay in the compact column.
    if (raw.length <= 6 && RegExp(r'^[<>]?\d').hasMatch(raw)) return false;
    // Longer / wordy results (Not Detected, Pale Yellow, …).
    return RegExp(r'[A-Za-z]').hasMatch(raw) && raw.length > 6;
  }

  Widget _resultValue(ObservationRecord o, Color valueColor) {
    final text = _isTextResult(o);
    final narrow = MediaQuery.sizeOf(context).width < 900;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: text ? (narrow ? 96 : 88) : 44,
        maxWidth: text ? (narrow ? 200 : 160) : 56,
      ),
      child: Text(
        o.valueReported,
        textAlign: TextAlign.right,
        maxLines: text ? 2 : 1,
        softWrap: text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: text ? 13 : 15,
          fontWeight: FontWeight.w700,
          height: text ? 1.25 : null,
          color: valueColor,
        ),
      ),
    );
  }

  Widget _sparkOrGap(List<double> spark, Color sparkColor, {required bool textResult}) {
    if (textResult) return const SizedBox.shrink();
    return Sparkline(values: spark, color: sparkColor);
  }

  Widget _desktopRow(
    ObservationRecord o,
    Map<String, List<double>> history,
    DateFormat fmt, {
    required bool selected,
  }) {
    final spark = history[o.parameterCode] ?? const <double>[];
    Color valueColor = BodylineColors.ink;
    Color sparkColor = BodylineColors.teal;
    if (o.flag == ObservationFlag.high ||
        o.flag == ObservationFlag.criticalHigh ||
        o.flag == ObservationFlag.abnormal) {
      valueColor = BodylineColors.orange;
      sparkColor = BodylineColors.orange;
    } else if (o.flag == ObservationFlag.low ||
        o.flag == ObservationFlag.criticalLow) {
      valueColor = BodylineColors.blue;
      sparkColor = BodylineColors.blue;
    }

    return Material(
      color: selected ? BodylineColors.selectedWash : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedCode = o.parameterCode),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.parameterName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? BodylineColors.tealDark
                            : BodylineColors.ink,
                      ),
                    ),
                    Text(
                      '${o.unitReported} · ${fmt.format(o.observedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _sparkOrGap(spark, sparkColor, textResult: _isTextResult(o)),
              if (!_isTextResult(o)) const SizedBox(width: 8),
              _resultValue(o, valueColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final profile = _profile;
    final rows = _filtered;
    final history = _historyMap(rows);
    final fmt = DateFormat('d MMM');
    final latest = _latest;

    final groups = <String, List<ObservationRecord>>{};
    for (final o in rows) {
      final g = _systemByParam[o.parameterCode] ?? 'Other';
      groups.putIfAbsent(g, () => []).add(o);
    }
    final groupNames = groups.keys.toList()..sort();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tests', style: Theme.of(context).textTheme.headlineMedium),
                Text(
                  '${latest.length} parameters tracked'
                  '${profile != null ? ' for ${profile.name}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search tests',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Wrap(
              spacing: 8,
              children: [
                _chip('All', _filter == _Filter.all, () {
                  setState(() => _filter = _Filter.all);
                }),
                _chip('Flagged', _filter == _Filter.flagged, () {
                  setState(() => _filter = _Filter.flagged);
                }),
                _chip('A–Z', _sort == _SortMode.alpha, () {
                  setState(() => _sort = _SortMode.alpha);
                }),
                _chip('Popular', _sort == _SortMode.popular, () {
                  setState(() => _sort = _SortMode.popular);
                }),
                _chip('Crucial', _sort == _SortMode.crucial, () {
                  setState(() => _sort = _SortMode.crucial);
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      'No tests yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    children: [
                      for (final g in groupNames) ...[
                        Text(
                          g,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: BodylineColors.surface,
                            borderRadius:
                                BorderRadius.circular(BodylineRadii.card),
                            border: Border.all(color: BodylineColors.border),
                          ),
                          child: Column(
                            children: [
                              for (var i = 0; i < groups[g]!.length; i++) ...[
                                _mobileRow(groups[g]![i], history, fmt),
                                if (i < groups[g]!.length - 1)
                                  Divider(
                                    height: 1,
                                    color: BodylineColors.divider,
                                  ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _mobileRow(
    ObservationRecord o,
    Map<String, List<double>> history,
    DateFormat fmt,
  ) {
    final spark = history[o.parameterCode] ?? const <double>[];
    Color valueColor = BodylineColors.ink;
    Color sparkColor = BodylineColors.teal;
    if (o.flag == ObservationFlag.high ||
        o.flag == ObservationFlag.criticalHigh ||
        o.flag == ObservationFlag.abnormal) {
      valueColor = BodylineColors.orange;
      sparkColor = BodylineColors.orange;
    } else if (o.flag == ObservationFlag.low ||
        o.flag == ObservationFlag.criticalLow) {
      valueColor = BodylineColors.blue;
      sparkColor = BodylineColors.blue;
    }

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TrendScreen(
              store: widget.store,
              parameterCode: o.parameterCode,
              title: o.parameterName,
              onChanged: widget.onChanged,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.parameterName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${o.unitReported} · ${fmt.format(o.observedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            _sparkOrGap(spark, sparkColor, textResult: _isTextResult(o)),
            if (!_isTextResult(o)) const SizedBox(width: 8),
            _resultValue(o, valueColor),
          ],
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
