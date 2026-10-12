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
  List<Map<String, Object?>> _noteAnns = [];
  List<Map<String, Object?>> _habitAnns = [];

  @override
  void didUpdateWidget(covariant TrendPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parameterCode != widget.parameterCode ||
        oldWidget.store.activeProfileId != widget.store.activeProfileId) {
      _loadAnns();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAnns();
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
    });
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

    final chartH = widget.compact ? 220.0 : 204.0;

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

        
        if (_noteAnns.isNotEmpty || _habitAnns.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Alongside this chart',
            style: TextStyle(
              fontWeight: FontWeight.w600,
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: const Color(0xFFE07A3D),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
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
                      return Text(
                        '${n['title']} · $when',
                        style: const TextStyle(fontSize: 13),
                      );
                    }),
                  ),
                ],
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
      ],
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
  });

  final List<_TrendPoint> points;
  final double? refLow;
  final double? refHigh;
  final List<RefBand>? bands;
  final int? selectedIndex;
  final ValueChanged<int> onSelectIndex;

  @override
  State<_InteractiveTrendChart> createState() => _InteractiveTrendChartState();
}

class _InteractiveTrendChartState extends State<_InteractiveTrendChart> {
  int? _hoverIndex;
  Offset? _hoverLocal;

  static const _pad = EdgeInsets.fromLTRB(16, 28, 16, 18);

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
              final i = _nearestAlways(d.localPosition, size);
              setState(() {
                _hoverIndex = i;
                _hoverLocal = d.localPosition;
              });
              widget.onSelectIndex(i);
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
    this.refLow,
    this.refHigh,
    this.bands,
    this.selectedIndex,
    this.hoverIndex,
  });

  final List<double> values;
  final List<String> labels;
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
        Rect.fromLTRB(0, 0, size.width, yFor(refHigh!)),
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

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BandTrendPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.labels != labels ||
        oldDelegate.refLow != refLow ||
        oldDelegate.refHigh != refHigh ||
        oldDelegate.bands != bands ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.hoverIndex != hoverIndex ||
        oldDelegate.padding != padding;
  }
}
