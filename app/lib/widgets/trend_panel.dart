import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/local_store.dart';
import '../data/models.dart';
import '../theme/tokens.dart';
import 'status_pill.dart';

enum TrendRange { y1, y3, all }

/// Embeddable trend body used by mobile TrendScreen and desktop master–detail.
///
/// Chart bands use the **selected** reading’s printed lab range (ADR-006),
/// not a single house range and not silently the latest for the whole series.
class TrendPanel extends StatefulWidget {
  const TrendPanel({
    super.key,
    required this.store,
    required this.parameterCode,
    required this.title,
    this.showHistory = true,
    this.showRangeSelector = true,
    this.compact = false,
    this.onEditReading,
    this.onAddReading,
  });

  final LocalStore store;
  final String parameterCode;
  final String title;
  final bool showHistory;
  final bool showRangeSelector;
  final bool compact;
  final void Function(ObservationRecord reading)? onEditReading;
  final VoidCallback? onAddReading;

  @override
  State<TrendPanel> createState() => _TrendPanelState();
}

class _TrendPanelState extends State<TrendPanel> {
  TrendRange _range = TrendRange.all;
  String? _selectedId;
  int? _selectedNoteIndex;
  List<Map<String, Object?>> _noteAnns = [];
  List<Map<String, Object?>> _habitAnns = [];
  Map<String, String?> _about = const {};
  var _aboutExpanded = false;

  @override
  void didUpdateWidget(covariant TrendPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parameterCode != widget.parameterCode ||
        oldWidget.store.activeProfileId != widget.store.activeProfileId) {
      _loadAnns();
      _loadAbout();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAnns();
    _loadAbout();
  }

  Future<void> _loadAbout() async {
    final info = Map<String, String?>.from(
      await widget.store.parameterInfo(widget.parameterCode),
    );
    final relatedRaw = info['often_tested_with'];
    if (relatedRaw != null && relatedRaw.isNotEmpty) {
      final codes = relatedRaw
          .split(RegExp(r'[;,]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty);
      final names = await widget.store.parameterDisplayNames(codes);
      if (names.isNotEmpty) {
        info['often_tested_with'] = names.join(' · ');
      }
    }
    if (!mounted) return;
    setState(() {
      _about = info;
      _aboutExpanded = false;
    });
  }

  Future<void> _loadAnns() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      if (mounted) setState(() { _noteAnns = []; _habitAnns = []; });
      return;
    }
    final notes = await widget.store.notesForChartCode(pid, widget.parameterCode);
    final habits = await widget.store.habitsForChartCode(pid, widget.parameterCode);
    if (!mounted) return;
    setState(() {
      _noteAnns = notes;
      _habitAnns = habits;
      if (_selectedNoteIndex != null &&
          (_selectedNoteIndex! < 0 || _selectedNoteIndex! >= notes.length)) {
        _selectedNoteIndex = null;
      }
    });
  }

  Future<void> _promptNoteForDay(DateTime day) async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;
    final title = TextEditingController();
    final body = TextEditingController();
    var whenKind = 'day';
    DateTime? start = day;
    DateTime? end = day;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('New note'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: body,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      hintText: 'Things reports and prescriptions don’t say',
                    ),
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    autofocus: true,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Title (optional)',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'When',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'day', label: Text('One day')),
                      ButtonSegment(value: 'period', label: Text('Period')),
                    ],
                    selected: {whenKind},
                    onSelectionChanged: (s) => setLocal(() {
                      whenKind = s.first;
                      if (whenKind == 'day') {
                        end = start;
                      } else {
                        end ??= start;
                      }
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            whenKind == 'period' ? 'From' : 'Date',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            start == null
                                ? 'Pick a date'
                                : DateFormat.yMMMd().format(start!),
                          ),
                          trailing: const Icon(Icons.calendar_today_outlined, size: 18),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: start ?? day,
                              firstDate: DateTime(2000),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );
                            if (d != null) {
                              setLocal(() {
                                start = d;
                                if (whenKind == 'day') end = d;
                                if (end != null && end!.isBefore(d)) end = d;
                              });
                            }
                          },
                        ),
                      ),
                      if (whenKind == 'period') ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('To', style: TextStyle(fontSize: 14)),
                            subtitle: Text(
                              end == null
                                  ? 'Pick end date'
                                  : DateFormat.yMMMd().format(end!),
                            ),
                            trailing: const Icon(Icons.calendar_today_outlined, size: 18),
                            onTap: () async {
                              final d = await showDatePicker(
                                context: ctx,
                                initialDate: end ?? start ?? day,
                                firstDate: start ?? DateTime(2000),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)),
                              );
                              if (d != null) setLocal(() => end = d);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    whenKind == 'period'
                        ? 'Shows as a shaded band across this period on the chart.'
                        : 'Shows as a pin on this day on the chart.',
                    style: TextStyle(
                      fontSize: 12,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pins are for context, not cause and effect.',
                    style: TextStyle(
                      fontSize: 12,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save note'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) {
      title.dispose();
      body.dispose();
      return;
    }

    var titleText = title.text.trim();
    final bodyText = body.text.trim();
    if (titleText.isEmpty && bodyText.isEmpty) {
      title.dispose();
      body.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add a title or note text to save.')),
        );
      }
      return;
    }
    if (titleText.isEmpty) {
      final line = bodyText.split('\n').first.trim();
      titleText = line.length <= 60
          ? line
          : '${line.substring(0, 57)}...';
    }

    if (start == null) {
      title.dispose();
      body.dispose();
      return;
    }
    final startY = DateFormat('yyyy-MM-dd').format(start!);
    final endY = whenKind == 'period'
        ? DateFormat('yyyy-MM-dd').format(end ?? start!)
        : startY;

    await widget.store.addNote(
      profileId: pid,
      title: titleText,
      body: bodyText,
      whenKind: whenKind,
      startYmd: startY,
      endYmd: endY,
      chartCodes: [widget.parameterCode],
    );
    title.dispose();
    body.dispose();
    await _loadAnns();
  }

  List<ObservationRecord> get _series {
    final now = DateTime.now();
    DateTime? since;
    if (_range == TrendRange.y1) {
      since = DateTime(now.year - 1, now.month, now.day);
    } else if (_range == TrendRange.y3) {
      since = DateTime(now.year - 3, now.month, now.day);
    }
    final pid = widget.store.activeProfileId;
    if (pid == null) return const [];
    var rows = widget.store.trendFor(pid, widget.parameterCode);
    if (since != null) {
      rows = rows.where((o) => !o.observedAt.isBefore(since!)).toList();
    }
    return rows;
  }

  ObservationRecord? _selectedOf(List<ObservationRecord> series) {
    if (series.isEmpty) return null;
    if (_selectedId != null) {
      for (final o in series) {
        if (o.id == _selectedId) return o;
      }
    }
    return series.last;
  }

  ReportRecord? _reportFor(ObservationRecord o) {
    for (final r in widget.store.reports) {
      if (r.id == o.reportId) return r;
    }
    return null;
  }

  String _rangeAttribution(ObservationRecord o) {
    final report = _reportFor(o);
    final title = report?.title.trim();
    if (title != null && title.isNotEmpty) {
      return 'Range as printed · $title';
    }
    return 'Range as printed on this reading';
  }

  String _rangeBoundsLabel(ObservationRecord o) {
    if (o.refLow == null && o.refHigh == null) {
      return 'No printed range on this reading';
    }
    final lo = o.refLow?.toString() ?? '-';
    final hi = o.refHigh?.toString() ?? '-';
    return 'Lab $lo-$hi';
  }

  @override
  Widget build(BuildContext context) {
    final series = _series;
    final selected = _selectedOf(series);
    // Keep selection valid when the time filter drops the old id.
    if (selected != null && _selectedId != selected.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedId = selected.id);
      });
    }

    final nums = series
        .where((o) => o.valueNum != null)
        .map((o) => o.valueNum!)
        .toList();
    final selectedIndex = selected == null || selected.valueNum == null
        ? null
        : nums.isEmpty
            ? null
            : () {
                var j = 0;
                for (final o in series) {
                  if (o.valueNum == null) continue;
                  if (o.id == selected.id) return j;
                  j++;
                }
                return null;
              }();

    final fmt = DateFormat('d MMM yyyy');
    final short = DateFormat('MMM yy');

    ObservationRecord? highest;
    ObservationRecord? lowest;
    for (final o in series) {
      if (o.valueNum == null) continue;
      if (highest == null || o.valueNum! > highest.valueNum!) highest = o;
      if (lowest == null || o.valueNum! < lowest.valueNum!) lowest = o;
    }

    final chartH = widget.compact ? 248.0 : 236.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        widget.compact ? 0 : 20,
        widget.compact ? 0 : 8,
        widget.compact ? 0 : 20,
        widget.compact ? 8 : 32,
      ),
      children: [
        if (selected != null) ...[
          Text(
            widget.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: widget.compact ? 24 : 22,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                selected.valueReported,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: widget.compact ? 40 : 44,
                      height: 1,
                    ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  selected.unitReported,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 10),
              if (selected.flag != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: StatusPill(flag: selected.flag!),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              fmt.format(selected.observedAt),
              _rangeBoundsLabel(selected),
            ].join(' \u00b7 '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            _rangeAttribution(selected),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: BodylineColors.inkSubtle,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'No readings for ${widget.title} yet.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),

        if (widget.showRangeSelector) ...[
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: BodylineColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: BodylineColors.border),
            ),
            child: Row(
              children: [
                _rangeBtn('1Y', TrendRange.y1),
                _rangeBtn('3Y', TrendRange.y3),
                _rangeBtn('All', TrendRange.all),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        Container(
          height: chartH,
          decoration: BoxDecoration(
            color: BodylineChartColors.surface,
            borderRadius: BorderRadius.circular(BodylineRadii.card),
            border: Border.all(color: BodylineChartColors.border),
            boxShadow: BodylineChartColors.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: nums.isEmpty
              ? Center(
                  child: Text(
                    'No numeric value to chart yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: BodylineChartColors.ink,
                        ),
                  ),
                )
              : _InteractiveTrendChart(
                  points: [
                    for (final o in series)
                      if (o.valueNum != null)
                        _TrendPoint(
                          value: o.valueNum!,
                          label: o.valueReported,
                          unit: o.unitReported,
                          date: o.observedAt,
                          id: o.id,
                        ),
                  ],
                  noteAnns: _noteAnns,
                  habitAnns: _habitAnns,
                  refLow: selected?.refLow,
                  refHigh: selected?.refHigh,
                  bands: selected?.refBands,
                  selectedIndex: selectedIndex,
                  onSelectIndex: (i) {
                    final numeric = [
                      for (final o in series)
                        if (o.valueNum != null) o,
                    ];
                    if (i < 0 || i >= numeric.length) return;
                    setState(() => _selectedId = numeric[i].id);
                  },
                  onLongPressDate: (day) => _promptNoteForDay(day),
                  onTapNoteIndex: (i) {
                    if (i < 0 || i >= _noteAnns.length) return;
                    setState(() => _selectedNoteIndex = i);
                  },
                ),
        ),
        if (selected != null &&
            (selected.refLow != null || selected.refHigh != null) &&
            nums.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            nums.length == 1
                ? 'Single reading shown with this lab’s reference band. More points will draw a trend line.'
                : 'Chart band is for the selected reading only. Each history row keeps its own lab range and flag.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _statCard(
                'Highest',
                highest?.valueReported ?? '\u2014',
                highest != null ? short.format(highest.observedAt) : '',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                'Lowest',
                lowest?.valueReported ?? '\u2014',
                lowest != null ? short.format(lowest.observedAt) : '',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                'Tests',
                '${series.length}',
                series.isEmpty ? '' : 'since ${series.first.observedAt.year}',
              ),
            ),
          ],
        ),

        
        if (nums.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.sticky_note_2_outlined,
                  size: 16, color: BodylineColors.inkSubtle),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tap a pin to read it. Long-press the chart to add a note.',
                  style: TextStyle(
                    fontSize: 12,
                    color: BodylineColors.inkSubtle,
                  ),
                ),
              ),
            ],
          ),
        ],

        if (_selectedNoteIndex != null &&
            _selectedNoteIndex! >= 0 &&
            _selectedNoteIndex! < _noteAnns.length) ...[
          const SizedBox(height: 12),
          Builder(builder: (_) {
            final i = _selectedNoteIndex!;
            final n = _noteAnns[i];
            final kind = (n['when_kind'] as String?) ?? 'none';
            String whenLabel;
            if (kind == 'period') {
              whenLabel = '${n['start_ymd']} → ${n['end_ymd']}';
            } else if (kind == 'day') {
              whenLabel = '${n['start_ymd']}';
            } else {
              whenLabel = 'undated';
            }
            final body = (n['body'] as String?) ?? '';
            final title = (n['title'] as String?) ?? 'Note';
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BodylineColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE07A3D), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Note ${i + 1} · $whenLabel',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body.isEmpty ? title : body,
                    style: const TextStyle(fontSize: 14, height: 1.35),
                  ),
                  if (body.isNotEmpty && title.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        color: BodylineColors.inkSubtle,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'Only you see this — for context, not cause and effect.',
                    style: TextStyle(
                      fontSize: 11,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],

        if (_noteAnns.isNotEmpty || _habitAnns.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            _noteAnns.isEmpty
                ? 'Habits on this chart'
                : 'All ${_noteAnns.length} note${_noteAnns.length == 1 ? '' : 's'} on this chart',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: BodylineColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Shown for context only — not cause and effect.',
            style: TextStyle(fontSize: 12, color: BodylineColors.inkSubtle),
          ),
          const SizedBox(height: 8),
          for (final h in _habitAnns)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.loop, size: 16, color: BodylineColors.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Habit · ${h['title']}'
                      '${h['ended_on'] != null ? " (ended)" : ""}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          for (var i = 0; i < _noteAnns.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: _selectedNoteIndex == i
                    ? const Color(0xFFE07A3D).withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _selectedNoteIndex = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _selectedNoteIndex == i
                            ? const Color(0xFFE07A3D)
                            : BodylineChartColors.border,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: const Color(0xFFE07A3D),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Builder(builder: (_) {
                            final n = _noteAnns[i];
                            final kind = (n['when_kind'] as String?) ?? 'none';
                            final when = kind == 'period'
                                ? '${n['start_ymd']} → ${n['end_ymd']}'
                                : kind == 'day'
                                    ? '${n['start_ymd']}'
                                    : 'undated';
                            final preview = ((n['body'] as String?) ?? '').trim();
                            final title = (n['title'] as String?) ?? 'Note';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Note ${i + 1} · $when',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  preview.isEmpty ? title : preview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: BodylineColors.inkSubtle,
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],

        if (widget.showHistory) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Saved results',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (widget.onAddReading != null)
                IconButton(
                  tooltip: 'Add result for this test',
                  onPressed: widget.onAddReading,
                  icon: const Icon(Icons.add),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a reading to show that report’s printed range on the chart.',
            style: Theme.of(context).textTheme.bodySmall,
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
                for (var i = 0; i < series.reversed.length; i++) ...[
                  _historyRow(
                    series.reversed.elementAt(i),
                    fmt,
                    selected: selected?.id == series.reversed.elementAt(i).id,
                  ),
                  if (i < series.length - 1)
                    Divider(height: 1, color: BodylineColors.divider),
                ],
              ],
            ),
          ),
        ],

        if (_hasAboutContent) ...[
          const SizedBox(height: 20),
          _aboutThisTest(),
        ],
      ],
    );
  }

  bool get _hasAboutContent {
    for (final k in const [
      'what_it_measures',
      'why_its_tested',
      'before_the_test',
      'what_can_shift_it',
      'above_range_general',
      'below_range_general',
      'often_tested_with',
      'closing_line',
    ]) {
      final v = _about[k];
      if (v != null && v.isNotEmpty) return true;
    }
    return false;
  }

  String? get _aboutLead => _about['what_it_measures'];

  Widget _aboutThisTest() {
    final draft = (_about['review_status'] ?? '')
        .toLowerCase()
        .contains('draft');
    final blocks = <({String label, String body})>[
      if ((_about['why_its_tested'] ?? '').isNotEmpty)
        (label: 'Why it’s checked', body: _about['why_its_tested']!),
      if ((_about['before_the_test'] ?? '').isNotEmpty)
        (label: 'Before you measure', body: _about['before_the_test']!),
      if ((_about['what_can_shift_it'] ?? '').isNotEmpty)
        (label: 'What can change it', body: _about['what_can_shift_it']!),
      if ((_about['above_range_general'] ?? '').isNotEmpty)
        (label: 'When it’s higher', body: _about['above_range_general']!),
      if ((_about['below_range_general'] ?? '').isNotEmpty)
        (label: 'When it’s lower', body: _about['below_range_general']!),
      if ((_about['often_tested_with'] ?? '').isNotEmpty)
        (label: 'Often checked with', body: _about['often_tested_with']!),
    ];

    return Container(
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        border: Border.all(color: BodylineColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _aboutExpanded = !_aboutExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'About this test',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (!_aboutExpanded &&
                            (_aboutLead ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _aboutLead!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: BodylineColors.inkSubtle,
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    _aboutExpanded ? Icons.expand_less : Icons.expand_more,
                    color: BodylineColors.inkSubtle,
                  ),
                ],
              ),
            ),
          ),
          if (_aboutExpanded) ...[
            Divider(height: 1, color: BodylineColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((_aboutLead ?? '').isNotEmpty) ...[
                    Text(
                      _aboutLead!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                          ),
                    ),
                    if (blocks.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Divider(height: 1, color: BodylineColors.divider),
                      const SizedBox(height: 4),
                    ],
                  ],
                  for (var i = 0; i < blocks.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: BodylineColors.divider),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            blocks[i].label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: BodylineColors.inkSubtle,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            blocks[i].body,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      height: 1.45,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if ((_about['closing_line'] ?? '').isNotEmpty) ...[
                    Divider(height: 1, color: BodylineColors.divider),
                    const SizedBox(height: 12),
                    Text(
                      _about['closing_line']!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.4,
                            color: BodylineColors.inkSubtle,
                          ),
                    ),
                  ],
                  if (draft) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Educational only — not a diagnosis.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: BodylineColors.inkSubtle,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _rangeBtn(String label, TrendRange value) {
    final selected = _range == value;
    return Expanded(
      child: Material(
        color: selected ? BodylineColors.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => setState(() => _range = value),
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 36,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? BodylineColors.onInk : BodylineColors.inkSubtle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, String sub) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: BodylineColors.chip,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 22,
                ),
          ),
          if (sub.isNotEmpty)
            Text(sub, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _historyRow(
    ObservationRecord o,
    DateFormat fmt, {
    required bool selected,
  }) {
    return Material(
      color: selected ? BodylineColors.selectedWash : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedId = o.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${o.valueReported} ${o.unitReported}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? BodylineColors.tealDark
                            : BodylineColors.ink,
                      ),
                    ),
                    Text(
                      [
                        fmt.format(o.observedAt),
                        if (o.refLow != null || o.refHigh != null)
                          _rangeBoundsLabel(o)
                        else
                          'No printed range',
                      ].join(' \u00b7 '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (o.flag != null) StatusPill(flag: o.flag!),
              if (widget.onEditReading != null)
                IconButton(
                  tooltip: 'Edit this result',
                  onPressed: () => widget.onEditReading!(o),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ),
    );
  }
}


class _TrendPoint {
  const _TrendPoint({
    required this.value,
    required this.label,
    required this.unit,
    required this.date,
    required this.id,
  });

  final double value;
  final String label;
  final String unit;
  final DateTime date;
  final String id;
}

class _InteractiveTrendChart extends StatefulWidget {
  const _InteractiveTrendChart({
    required this.points,
    required this.onSelectIndex,
    this.refLow,
    this.refHigh,
    this.bands,
    this.selectedIndex,
    this.noteAnns = const [],
    this.habitAnns = const [],
    this.onLongPressDate,
    this.onTapNoteIndex,
  });

  final List<_TrendPoint> points;
  final double? refLow;
  final double? refHigh;
  final List<RefBand>? bands;
  final int? selectedIndex;
  final ValueChanged<int> onSelectIndex;
  final List<Map<String, Object?>> noteAnns;
  final List<Map<String, Object?>> habitAnns;
  final ValueChanged<DateTime>? onLongPressDate;
  final ValueChanged<int>? onTapNoteIndex;

  @override
  State<_InteractiveTrendChart> createState() => _InteractiveTrendChartState();
}

class _InteractiveTrendChartState extends State<_InteractiveTrendChart> {
  int? _hoverIndex;
  Offset? _hoverLocal;

  static const _pad = EdgeInsets.fromLTRB(16, 44, 16, 18);

  List<Offset> _layout(Size size) {
    final values = [for (final p in widget.points) p.value];
    final all = [...values];
    if (widget.refLow != null) all.add(widget.refLow!);
    if (widget.refHigh != null) all.add(widget.refHigh!);
    final minV = all.reduce((a, b) => a < b ? a : b);
    final maxV = all.reduce((a, b) => a > b ? a : b);
    final pad = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV) * 0.18;
    final lo = minV - pad;
    final hi = maxV + pad;
    final span = hi - lo;
    final chart = _pad.deflateSize(size);
    double yFor(double v) =>
        _pad.top + chart.height - ((v - lo) / span) * chart.height;
    final n = values.length;
    return [
      for (var i = 0; i < n; i++)
        Offset(
          n == 1
              ? _pad.left + chart.width / 2
              : _pad.left + chart.width * (i / (n - 1)),
          yFor(values[i]),
        ),
    ];
  }

  int? _nearest(Offset local, Size size, {double maxDist = 28}) {
    final pts = _layout(size);
    if (pts.isEmpty) return null;
    var best = 0;
    var bestD = (pts[0] - local).distance;
    for (var i = 1; i < pts.length; i++) {
      final d = (pts[i] - local).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return bestD <= maxDist ? best : null;
  }

  /// Always pick the closest point (touch / drag tip).
  int _nearestAlways(Offset local, Size size) {
    final pts = _layout(size);
    if (pts.isEmpty) return 0;
    var best = 0;
    var bestD = (pts[0] - local).distance;
    for (var i = 1; i < pts.length; i++) {
      final d = (pts[i] - local).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }


  DateTime? _dateAtX(double x, Size size) {
    if (widget.points.isEmpty) return null;
    final chart = _pad.deflateSize(size);
    final t01 = ((x - _pad.left) / chart.width).clamp(0.0, 1.0);
    final first = widget.points.first.date;
    final last = widget.points.last.date;
    final ms = first.millisecondsSinceEpoch +
        ((last.millisecondsSinceEpoch - first.millisecondsSinceEpoch) * t01)
            .round();
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  int? _hitNotePin(Offset local, Size size) {
    if (widget.noteAnns.isEmpty || widget.points.isEmpty) return null;
    final chart = _pad.deflateSize(size);
    final dates = [for (final p in widget.points) p.date];
    final first = dates.first;
    final last = dates.last;
    final spanMs =
        (last.millisecondsSinceEpoch - first.millisecondsSinceEpoch).abs();
    final laneY = _pad.top - 18;

    double xForDate(DateTime d) {
      if (spanMs < 1) return _pad.left + chart.width / 2;
      final t01 = ((d.millisecondsSinceEpoch - first.millisecondsSinceEpoch) /
              spanMs)
          .clamp(0.0, 1.0);
      return _pad.left + chart.width * t01;
    }

    for (var i = 0; i < widget.noteAnns.length; i++) {
      final n = widget.noteAnns[i];
      final kind = (n['when_kind'] as String?) ?? 'none';
      if (kind == 'none') continue;
      final start = _parseYmd(n['start_ymd'] as String?);
      if (start == null) continue;
      final end = _parseYmd(n['end_ymd'] as String?) ?? start;
      final x0 = xForDate(start.isBefore(first) ? first : start);
      final x1 = kind == 'period'
          ? math.max(
              xForDate(end.isAfter(last) ? last : end),
              x0 + 6,
            )
          : x0;

      // Pin head hit
      final pin = Offset(x0, laneY + 2);
      if ((pin - local).distance <= 16) return i;

      // Period: anywhere in the shaded vertical band
      if (kind == 'period') {
        final band = Rect.fromLTRB(
          x0 - 4,
          laneY - 8,
          x1 + 4,
          _pad.top + chart.height,
        );
        if (band.contains(local)) return i;
      } else {
        // Day: near the dashed guide
        final guide = Rect.fromLTRB(
          x0 - 8,
          laneY - 8,
          x0 + 8,
          _pad.top + chart.height,
        );
        if (guide.contains(local)) return i;
      }
    }
    return null;
  }

  DateTime? _parseYmd(String? ymd) {
    if (ymd == null || ymd.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd').parse(ymd);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy');
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        // Tooltip only while the pointer is over a point — never for selection alone.
        final tipIndex = _hoverIndex;
        _TrendPoint? tip;
        Offset? tipAt;
        if (tipIndex != null &&
            tipIndex >= 0 &&
            tipIndex < widget.points.length) {
          tip = widget.points[tipIndex];
          tipAt = _layout(size)[tipIndex];
        }

        return MouseRegion(
          onHover: (e) {
            final i = _nearest(e.localPosition, size);
            if (i != _hoverIndex || e.localPosition != _hoverLocal) {
              setState(() {
                _hoverIndex = i;
                _hoverLocal = e.localPosition;
              });
            }
          },
          onExit: (_) => setState(() {
            _hoverIndex = null;
            _hoverLocal = null;
          }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final noteHit = _hitNotePin(d.localPosition, size);
              if (noteHit != null) {
                widget.onTapNoteIndex?.call(noteHit);
                return;
              }
              final i = _nearestAlways(d.localPosition, size);
              setState(() {
                _hoverIndex = i;
                _hoverLocal = d.localPosition;
              });
              widget.onSelectIndex(i);
            },
            onLongPressStart: (d) {
              final day = _dateAtX(d.localPosition.dx, size);
              if (day != null) widget.onLongPressDate?.call(day);
            },
            onPanUpdate: (d) {
              final i = _nearestAlways(d.localPosition, size);
              if (i != _hoverIndex || d.localPosition != _hoverLocal) {
                setState(() {
                  _hoverIndex = i;
                  _hoverLocal = d.localPosition;
                });
              }
            },
            onPanEnd: (_) {
              // Keep tip visible until next tap / hover exit.
            },
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: BandTrendPainter(
                      values: [for (final p in widget.points) p.value],
                      labels: [for (final p in widget.points) p.label],
                      dates: [for (final p in widget.points) p.date],
                      noteAnns: widget.noteAnns,
                      habitAnns: widget.habitAnns,
                      refLow: widget.refLow,
                      refHigh: widget.refHigh,
                      bands: widget.bands,
                      selectedIndex: widget.selectedIndex,
                      hoverIndex: _hoverIndex,
                      padding: _pad,
                    ),
                  ),
                ),
                if (tip != null && tipAt != null)
                  Positioned(
                    left: (tipAt.dx - 70).clamp(8.0, size.width - 148),
                    top: (tipAt.dy - 72).clamp(8.0, size.height - 78),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: BodylineChartColors.ink,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: DefaultTextStyle(
                            style: TextStyle(
                              color: BodylineChartColors.onInk,
                              fontSize: 12,
                              height: 1.25,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  tip.label +
                                      (tip.unit.trim().isEmpty
                                          ? ''
                                          : ' ${tip.unit}'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(dateFmt.format(tip.date)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class BandTrendPainter extends CustomPainter {
  BandTrendPainter({
    required this.values,
    required this.labels,
    required this.padding,
    this.dates = const [],
    this.noteAnns = const [],
    this.habitAnns = const [],
    this.refLow,
    this.refHigh,
    this.bands,
    this.selectedIndex,
    this.hoverIndex,
  });

  final List<double> values;
  final List<String> labels;
  final List<DateTime> dates;
  final List<Map<String, Object?>> noteAnns;
  final List<Map<String, Object?>> habitAnns;
  final EdgeInsets padding;
  final double? refLow;
  final double? refHigh;
  final List<RefBand>? bands;
  final int? selectedIndex;
  final int? hoverIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final chart = padding.deflateSize(size);
    final all = [...values];
    if (refLow != null) all.add(refLow!);
    if (refHigh != null) all.add(refHigh!);
    final minV = all.reduce((a, b) => a < b ? a : b);
    final maxV = all.reduce((a, b) => a > b ? a : b);
    final vPad = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV) * 0.18;
    final lo = minV - vPad;
    final hi = maxV + vPad;
    final span = hi - lo;

    double yFor(double v) =>
        padding.top + chart.height - ((v - lo) / span) * chart.height;
    double xFor(int i) => values.length == 1
        ? padding.left + chart.width / 2
        : padding.left + chart.width * (i / (values.length - 1));

    // Clip bands/line to rounded chart area (matches outer card radius).
    final clip = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(BodylineRadii.card),
    );
    canvas.save();
    canvas.clipRRect(clip);

    final stageBands = bands == null
        ? const <RefBand>[]
        : [for (final b in bands!) if (b.hasBounds) b];
    if (stageBands.isNotEmpty) {
      for (final b in stageBands) {
        final top = b.high != null ? yFor(b.high!) : padding.top;
        final bot = b.low != null ? yFor(b.low!) : padding.top + chart.height;
        final color = b.safe == true
            ? BodylineChartColors.inRangeBand.withValues(alpha: 0.85)
            : b.safe == false
                ? BodylineChartColors.highBand.withValues(alpha: 0.55)
                : BodylineChartColors.inRangeBand.withValues(alpha: 0.45);
        canvas.drawRect(
          Rect.fromLTRB(0, top, size.width, bot),
          Paint()..color = color,
        );
      }
    } else if (refLow != null && refHigh != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, yFor(refHigh!), size.width, yFor(refLow!)),
        Paint()
          ..color = BodylineChartColors.inRangeBand.withValues(alpha: 0.9),
      );
      canvas.drawRect(
        Rect.fromLTRB(0, padding.top, size.width, yFor(refHigh!)),
        Paint()
          ..color = BodylineChartColors.highBand.withValues(alpha: 0.7),
      );
      canvas.drawRect(
        Rect.fromLTRB(0, yFor(refLow!), size.width, size.height),
        Paint()
          ..color = BodylineChartColors.lowBand.withValues(alpha: 0.55),
      );
    }

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = xFor(i);
      final y = yFor(values[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = BodylineChartColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final labelStyle = TextStyle(
      color: BodylineChartColors.ink,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );

    for (var i = 0; i < values.length; i++) {
      final x = xFor(i);
      final y = yFor(values[i]);
      final isSelected = selectedIndex == i;
      final isHover = hoverIndex == i;
      canvas.drawCircle(
        Offset(x, y),
        isSelected || isHover ? 6.0 : 3.5,
        Paint()
          ..color = isSelected || isHover
              ? BodylineChartColors.teal
              : BodylineChartColors.ink,
      );
      canvas.drawCircle(
        Offset(x, y),
        isSelected || isHover ? 3.2 : 1.8,
        Paint()..color = BodylineChartColors.surface,
      );

      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final labelY = (y - 16 - tp.height).clamp(4.0, size.height - tp.height - 4);
      final labelX = (x - tp.width / 2).clamp(4.0, size.width - tp.width - 4);
      // Soft pill behind score — surface + ink so light and dark both read.
      final bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(labelX - 4, labelY - 2, tp.width + 8, tp.height + 4),
        const Radius.circular(6),
      );
      canvas.drawRRect(
        bg,
        Paint()..color = BodylineChartColors.surface.withValues(alpha: 0.95),
      );
      canvas.drawRRect(
        bg,
        Paint()
          ..color = BodylineChartColors.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      tp.paint(canvas, Offset(labelX, labelY));
    }


    // YOUR NOTES lane + period/day markers (drawn last so bands never cover them).
    if (dates.isNotEmpty && (noteAnns.isNotEmpty || habitAnns.isNotEmpty)) {
      final first = dates.first;
      final last = dates.last;
      final spanMs =
          (last.millisecondsSinceEpoch - first.millisecondsSinceEpoch).abs();
      double xForDate(DateTime d) {
        if (spanMs < 1) return padding.left + chart.width / 2;
        final t01 = ((d.millisecondsSinceEpoch - first.millisecondsSinceEpoch) /
                spanMs)
            .clamp(0.0, 1.0);
        return padding.left + chart.width * t01;
      }

      DateTime? parseYmd(String? ymd) {
        if (ymd == null || ymd.isEmpty) return null;
        try {
          return DateFormat('yyyy-MM-dd').parse(ymd);
        } catch (_) {
          return null;
        }
      }

      void drawDashedV(double x, double y0, double y1, Color c) {
        final paint = Paint()
          ..color = c
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        const dash = 4.0;
        const gap = 3.0;
        var y = y0;
        while (y < y1) {
          final yEnd = (y + dash).clamp(y0, y1);
          canvas.drawLine(Offset(x, y), Offset(x, yEnd), paint);
          y += dash + gap;
        }
      }

      void drawPin(Offset tip, int num, Color fill) {
        // Teardrop-ish: circle + small triangle pointing down to tip.
        final center = Offset(tip.dx, tip.dy - 7);
        canvas.drawCircle(center, 9, Paint()..color = fill);
        final tri = Path()
          ..moveTo(tip.dx - 5, tip.dy - 2)
          ..lineTo(tip.dx + 5, tip.dy - 2)
          ..lineTo(tip.dx, tip.dy + 3)
          ..close();
        canvas.drawPath(tri, Paint()..color = fill);
        final tp = TextPainter(
          text: TextSpan(
            text: '$num',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
        );
      }

      final laneY = padding.top - 18;
      final chartBottom = padding.top + chart.height;

      // Lane label
      final laneLabel = TextPainter(
        text: const TextSpan(
          text: 'YOUR NOTES',
          style: TextStyle(
            color: Color(0xFF8A7A6A),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      laneLabel.paint(canvas, Offset(padding.left, laneY - 14));

      // Habit periods — teal brackets in the lane only
      for (final h in habitAnns) {
        final createdMs = (h['created_at'] as int?) ?? 0;
        final start = createdMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(createdMs)
            : first;
        final ended = parseYmd(h['ended_on'] as String?) ?? last;
        final x0 = xForDate(start.isBefore(first) ? first : start);
        final x1 = xForDate(ended.isAfter(last) ? last : ended);
        final paint = Paint()
          ..color = const Color(0xFF0D6E6E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(x0, laneY + 6)
          ..lineTo(x0, laneY)
          ..lineTo(x1, laneY)
          ..lineTo(x1, laneY + 6);
        canvas.drawPath(path, paint);
      }

      const orange = Color(0xFFE07A3D);
      for (var i = 0; i < noteAnns.length; i++) {
        final n = noteAnns[i];
        final kind = (n['when_kind'] as String?) ?? 'none';
        if (kind == 'none') continue;
        final start = parseYmd(n['start_ymd'] as String?);
        if (start == null) continue;
        final end = parseYmd(n['end_ymd'] as String?) ?? start;
        final x0 = xForDate(start.isBefore(first) ? first : start);
        final x1Raw = xForDate(end.isAfter(last) ? last : end);
        final x1 = kind == 'period' ? math.max(x1Raw, x0 + 6) : x0;

        if (kind == 'period') {
          // Soft vertical band across the chart body (mockup).
          canvas.drawRect(
            Rect.fromLTRB(x0, padding.top, x1, chartBottom),
            Paint()..color = orange.withValues(alpha: 0.14),
          );
          drawDashedV(x0, laneY + 4, chartBottom, orange.withValues(alpha: 0.85));
          drawDashedV(x1, laneY + 4, chartBottom, orange.withValues(alpha: 0.85));
          drawPin(Offset(x0, laneY + 2), i + 1, orange);
        } else {
          drawDashedV(x0, laneY + 4, chartBottom, orange.withValues(alpha: 0.75));
          drawPin(Offset(x0, laneY + 2), i + 1, orange);
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BandTrendPainter oldDelegate) {
    return oldDelegate.noteAnns != noteAnns ||
        oldDelegate.habitAnns != habitAnns ||
        oldDelegate.dates != dates ||
        oldDelegate.values != values ||
        oldDelegate.labels != labels ||
        oldDelegate.refLow != refLow ||
        oldDelegate.refHigh != refHigh ||
        oldDelegate.bands != bands ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.hoverIndex != hoverIndex ||
        oldDelegate.padding != padding;
  }
}
