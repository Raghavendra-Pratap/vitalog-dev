import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/trend_panel.dart';
import '../tests/trend_screen.dart';
import '../entry/manual_panel_screen.dart';

class OrganDetailScreen extends StatefulWidget {
  const OrganDetailScreen({
    super.key,
    required this.store,
    required this.systemCode,
    this.desktop = false,
  });

  final LocalStore store;
  final String systemCode;
  final bool desktop;

  @override
  State<OrganDetailScreen> createState() => _OrganDetailScreenState();
}

class _OrganDetailScreenState extends State<OrganDetailScreen> {
  String _title = '';
  List<ObservationRecord> _rows = [];
  List<MedicalItem> _meds = [];
  List<MedicalItem> _family = [];
  var _loading = true;
  String? _selectedCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = widget.store;
    final systems = await store.bodySystems();
    final match = systems.where((s) => s.code == widget.systemCode);
    final title = match.isEmpty
        ? widget.systemCode[0].toUpperCase() + widget.systemCode.substring(1)
        : match.first.name;

    final byCode = <String, ObservationRecord>{};
    for (final o in store.observations) {
      if (o.profileId != store.activeProfileId || o.deleted) continue;
      final prev = byCode[o.parameterCode];
      if (prev == null || o.observedAt.isAfter(prev.observedAt)) {
        byCode[o.parameterCode] = o;
      }
    }

    final codes = <String>{};
    for (final o in byCode.values) {
      final sys = await store.systemForParameter(o.parameterCode);
      if (sys == widget.systemCode) codes.add(o.parameterCode);
    }
    final rows = [for (final c in codes) byCode[c]!]
      ..sort((a, b) {
        final aw = _weight(a.flag);
        final bw = _weight(b.flag);
        if (aw != bw) return bw.compareTo(aw);
        return a.parameterName.compareTo(b.parameterName);
      });

    List<MedicalItem> meds = const [];
    List<MedicalItem> family = const [];
    final pid = store.activeProfileId;
    if (pid != null) {
      meds = await store.listMedications(pid);
      family = await store.listFamilyHistory(pid);
    }

    if (!mounted) return;
    setState(() {
      _title = title;
      _rows = rows;
      _meds = meds;
      _family = family;
      _loading = false;
      if (_selectedCode == null && rows.isNotEmpty) {
        _selectedCode = rows.first.parameterCode;
      } else if (_selectedCode != null &&
          !rows.any((o) => o.parameterCode == _selectedCode)) {
        _selectedCode = rows.isEmpty ? null : rows.first.parameterCode;
      }
    });
  }

  int _weight(ObservationFlag? f) {
    if (f == null) return 0;
    return switch (f) {
      ObservationFlag.criticalHigh ||
      ObservationFlag.criticalLow ||
      ObservationFlag.abnormal =>
        3,
      ObservationFlag.high || ObservationFlag.low => 2,
      ObservationFlag.normal => 1,
    };
  }

  ObservationRecord? get _selected {
    for (final o in _rows) {
      if (o.parameterCode == _selectedCode) return o;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(
        title: Text(_loading ? '…' : _title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : widget.desktop
              ? _buildDesktop(context)
              : _buildMobile(context),
    );
  }

  Widget _statusChips() {
    final high = _rows
        .where((o) =>
            o.flag == ObservationFlag.high ||
            o.flag == ObservationFlag.criticalHigh ||
            o.flag == ObservationFlag.abnormal)
        .length;
    final low = _rows
        .where((o) =>
            o.flag == ObservationFlag.low ||
            o.flag == ObservationFlag.criticalLow)
        .length;
    final inRange = _rows
        .where((o) => o.flag == null || o.flag == ObservationFlag.normal)
        .length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (high > 0)
          _countChip(
            '$high high',
            BodylineColors.orangeTint,
            BodylineColors.orangeText,
          ),
        if (low > 0)
          _countChip(
            '$low low',
            BodylineColors.blueTint,
            BodylineColors.blueText,
          ),
        if (inRange > 0)
          _countChip(
            '$inRange in range',
            BodylineColors.tealTint,
            BodylineColors.tealDark,
          ),
        if (_rows.isEmpty)
          _countChip(
            'Not tested yet',
            BodylineColors.border,
            BodylineColors.inkSubtle,
          ),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final selected = _selected;

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
                _statusChips(),
                const SizedBox(height: 16),
                Text(
                  'Linked tests',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _rows.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: BodylineColors.surface,
                            borderRadius:
                                BorderRadius.circular(BodylineRadii.cardSmall),
                            border: Border.all(color: BodylineColors.border),
                          ),
                          child: Text(
                            'No results linked yet. Add a panel that covers this area.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: BodylineColors.surface,
                            borderRadius:
                                BorderRadius.circular(BodylineRadii.cardSmall),
                            border: Border.all(color: BodylineColors.border),
                          ),
                          child: ListView.separated(
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: BodylineColors.divider,
                            ),
                            itemBuilder: (context, i) => _testRow(
                              _rows[i],
                              fmt,
                              selected:
                                  _rows[i].parameterCode == _selectedCode,
                              desktop: true,
                            ),
                          ),
                        ),
                ),
                if (_meds.isNotEmpty || _family.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Related in your profile',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: Container(
                      decoration: BoxDecoration(
                        color: BodylineColors.surface,
                        borderRadius:
                            BorderRadius.circular(BodylineRadii.cardSmall),
                        border: Border.all(color: BodylineColors.border),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (var i = 0; i < _meds.length; i++) ...[
                            _relatedRow(
                              _meds[i].title,
                              [
                                if (_meds[i].subtitle?.isNotEmpty == true)
                                  _meds[i].subtitle!,
                                'Medication',
                              ].join(' · '),
                              Icons.medication_outlined,
                            ),
                            if (i < _meds.length - 1 || _family.isNotEmpty)
                              Divider(
                                height: 1,
                                color: BodylineColors.divider,
                              ),
                          ],
                          for (var i = 0; i < _family.length; i++) ...[
                            _relatedRow(
                              [
                                if (_family[i].subtitle?.isNotEmpty == true)
                                  _family[i].subtitle!,
                                _family[i].title,
                              ].join(' · '),
                              'Family history',
                              Icons.account_tree_outlined,
                            ),
                            if (i < _family.length - 1)
                              Divider(
                                height: 1,
                                color: BodylineColors.divider,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
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
                    child: TrendPanel(
                      key: ValueKey(selected.parameterCode),
                      store: widget.store,
                      parameterCode: selected.parameterCode,
                      title: selected.parameterName,
                      compact: true,
                      showHistory: true,
                      showRangeSelector: true,
                      onAddReading: () => _addReading(selected.parameterCode),
                      onEditReading: _editReading,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _statusChips(),
        const SizedBox(height: 20),
        Text(
          'Linked tests',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (_rows.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: BodylineColors.surface,
              borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
              border: Border.all(color: BodylineColors.border),
            ),
            child: Text(
              'No results linked yet. Add a panel that covers this area.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: BodylineColors.surface,
              borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
              border: Border.all(color: BodylineColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _rows.length; i++) ...[
                  _testRow(_rows[i], fmt, selected: false, desktop: false),
                  if (i < _rows.length - 1)
                    Divider(height: 1, color: BodylineColors.divider),
                ],
              ],
            ),
          ),
        if (_meds.isNotEmpty || _family.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Related in your profile',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: BodylineColors.surface,
              borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
              border: Border.all(color: BodylineColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _meds.length; i++) ...[
                  _relatedRow(
                    _meds[i].title,
                    [
                      if (_meds[i].subtitle?.isNotEmpty == true)
                        _meds[i].subtitle!,
                      'Medication',
                    ].join(' · '),
                    Icons.medication_outlined,
                  ),
                  if (i < _meds.length - 1 || _family.isNotEmpty)
                    Divider(height: 1, color: BodylineColors.divider),
                ],
                for (var i = 0; i < _family.length; i++) ...[
                  _relatedRow(
                    [
                      if (_family[i].subtitle?.isNotEmpty == true)
                        _family[i].subtitle!,
                      _family[i].title,
                    ].join(' · '),
                    'Family history',
                    Icons.account_tree_outlined,
                  ),
                  if (i < _family.length - 1)
                    Divider(height: 1, color: BodylineColors.divider),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _addReading(String parameterCode) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualPanelScreen(
          store: widget.store,
          onSaved: () => _load(),
          seedParameterCode: parameterCode,
        ),
      ),
    );
    if (mounted) await _load();
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
          onSaved: () => _load(),
          editReport: report,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Widget _countChip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(BodylineRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _testRow(
    ObservationRecord o,
    DateFormat fmt, {
    required bool selected,
    required bool desktop,
  }) {
    Color valueColor = BodylineColors.ink;
    if (o.flag == ObservationFlag.high ||
        o.flag == ObservationFlag.criticalHigh ||
        o.flag == ObservationFlag.abnormal) {
      valueColor = BodylineColors.orange;
    } else if (o.flag == ObservationFlag.low ||
        o.flag == ObservationFlag.criticalLow) {
      valueColor = BodylineColors.blue;
    }

    return Material(
      color: selected ? BodylineColors.selectedWash : Colors.transparent,
      child: InkWell(
        onTap: () {
          if (desktop) {
            setState(() => _selectedCode = o.parameterCode);
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TrendScreen(
                store: widget.store,
                parameterCode: o.parameterCode,
                title: o.parameterName,
                onChanged: () {
                  _load();
                },
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                        fontWeight: FontWeight.w600,
                        color: selected ? BodylineColors.tealDark : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (o.flag != null) ...[
                          StatusPill(flag: o.flag!),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            fmt.format(o.observedAt),
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    o.valueReported,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: valueColor,
                    ),
                  ),
                  Text(
                    o.unitReported,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _relatedRow(String title, String subtitle, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: BodylineColors.tealDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
