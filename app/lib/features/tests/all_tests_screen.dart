import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../theme/tokens.dart';
import '../../widgets/month_year_date_picker.dart';
import 'tests_screen.dart';

const _kMaxSeries = 6;

const _kPalette = <Color>[
  Color(0xFF0D7377), // teal
  Color(0xFFC45C26), // orange
  Color(0xFF2F5D8C), // blue
  Color(0xFF6B4E9B), // purple
  Color(0xFF2E7D4F), // green
  Color(0xFFB33A3A), // red
];

/// Multi-parameter overlay chart for the current profile.
/// Each series is scaled to its own min–max so different units can share one plot.
class AllTestsScreen extends StatefulWidget {
  const AllTestsScreen({
    super.key,
    required this.store,
    required this.onChanged,
    this.desktop = false,
  });

  final LocalStore store;
  final VoidCallback onChanged;
  final bool desktop;

  @override
  State<AllTestsScreen> createState() => _AllTestsScreenState();
}

class _AllTestsScreenState extends State<AllTestsScreen> {
  var _flaggedOnly = false;
  String _nameFilter = '';
  DateTime? _from;
  DateTime? _to;
  final Set<String> _selected = {};
  var _didInitSelection = false;

  List<_SeriesMeta> _available() {
    final pid = widget.store.activeProfileId;
    if (pid == null) return const [];
    final byCode = <String, _SeriesMeta>{};
    for (final o in widget.store.observations) {
      if (o.profileId != pid || o.deleted) continue;
      if (_from != null && o.observedAt.isBefore(_from!)) continue;
      if (_to != null &&
          o.observedAt.isAfter(_to!.add(const Duration(days: 1)))) {
        continue;
      }
      if (o.valueNum == null) continue;
      final m = byCode.putIfAbsent(
        o.parameterCode,
        () => _SeriesMeta(
          code: o.parameterCode,
          name: o.parameterName,
          unit: o.unitReported,
        ),
      );
      m.points.add(_Pt(o.observedAt, o.valueNum!, o.valueReported));
      if (o.flag != null && o.flag != ObservationFlag.normal) {
        m.hasFlag = true;
      }
      if (o.observedAt.isAfter(m.latestAt)) m.latestAt = o.observedAt;
    }
    var list = byCode.values.toList();
    for (final m in list) {
      m.points.sort((a, b) => a.at.compareTo(b.at));
    }
    if (_flaggedOnly) {
      list = [for (final m in list) if (m.hasFlag) m];
    }
    final q = _nameFilter.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = [
        for (final m in list)
          if (m.name.toLowerCase().contains(q) ||
              m.code.toLowerCase().contains(q))
            m,
      ];
    }
    list.sort((a, b) => b.latestAt.compareTo(a.latestAt));
    return list;
  }

  void _syncSelection(List<_SeriesMeta> available) {
    final codes = {for (final m in available) m.code};
    final next = Set<String>.from(_selected.where(codes.contains));
    if (!_didInitSelection && available.isNotEmpty) {
      _didInitSelection = true;
      final flagged = [for (final m in available) if (m.hasFlag) m.code];
      final pool = flagged.isNotEmpty
          ? flagged
          : [for (final m in available) m.code];
      next
        ..clear()
        ..addAll(pool.take(_kMaxSeries));
    }
    if (next.length != _selected.length || !next.containsAll(_selected)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selected
            ..clear()
            ..addAll(next);
        });
      });
    }
  }

  void _toggle(String code) {
    setState(() {
      if (_selected.contains(code)) {
        _selected.remove(code);
      } else if (_selected.length >= _kMaxSeries) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chart shows up to $_kMaxSeries tests at once'),
          ),
        );
      } else {
        _selected.add(code);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final available = _available();
    _syncSelection(available);
    final plotted = [
      for (final m in available)
        if (_selected.contains(m.code)) m,
    ];
    // Stable color by selection order among available order
    final colorOf = <String, Color>{};
    var ci = 0;
    for (final m in plotted) {
      colorOf[m.code] = _kPalette[ci % _kPalette.length];
      ci++;
    }
    final fmt = DateFormat.yMMMd();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            'Overlay up to $_kMaxSeries tests. Each line is scaled to that test’s own range so units can differ — we do not diagnose.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: BodylineColors.inkSubtle,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Flagged only'),
                selected: _flaggedOnly,
                onSelected: (v) => setState(() => _flaggedOnly = v),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Find test',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _nameFilter = v),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final d = await pickBodylineDate(
                    context,
                    initialDate: _from ??
                        DateTime.now().subtract(const Duration(days: 365)),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    helpText: 'From date',
                  );
                  if (d != null) setState(() => _from = d);
                },
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(_from == null ? 'From' : fmt.format(_from!)),
              ),
              TextButton.icon(
                onPressed: () async {
                  final d = await pickBodylineDate(
                    context,
                    initialDate: _to ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    helpText: 'To date',
                  );
                  if (d != null) setState(() => _to = d);
                },
                icon: const Icon(Icons.event, size: 18),
                label: Text(_to == null ? 'To' : fmt.format(_to!)),
              ),
              if (_from != null || _to != null)
                TextButton(
                  onPressed: () => setState(() {
                    _from = null;
                    _to = null;
                  }),
                  child: const Text('Clear dates'),
                ),
            ],
          ),
        ),
        if (available.isEmpty)
          const Expanded(
            child: Center(child: Text('No test values yet for this profile.')),
          )
        else ...[
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final m in available)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: _selected.contains(m.code),
                      avatar: _selected.contains(m.code)
                          ? CircleAvatar(
                              backgroundColor: colorOf[m.code] ??
                                  BodylineColors.teal,
                              radius: 6,
                            )
                          : null,
                      label: Text(
                        m.name,
                        style: TextStyle(
                          fontWeight: _selected.contains(m.code)
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      onSelected: (_) => _toggle(m.code),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: plotted.isEmpty
                  ? const Center(
                      child: Text('Select one or more tests to plot.'),
                    )
                  : _MultiTrendChart(
                      series: plotted,
                      colors: colorOf,
                      onOpen: (code, name) async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TestsScreen(
                              store: widget.store,
                              onChanged: widget.onChanged,
                              desktop: widget.desktop,
                              initialParameterCode: code,
                            ),
                          ),
                        );
                        widget.onChanged();
                      },
                    ),
            ),
          ),
          // Legend + open
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final m in plotted)
                  InkWell(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TestsScreen(
                            store: widget.store,
                            onChanged: widget.onChanged,
                            desktop: widget.desktop,
                            initialParameterCode: m.code,
                          ),
                        ),
                      );
                      widget.onChanged();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: colorOf[m.code],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${m.name} · ${m.points.last.reported}${m.unit.isEmpty ? '' : ' ${m.unit}'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.open_in_new,
                            size: 12,
                            color: BodylineColors.inkSubtle,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SeriesMeta {
  _SeriesMeta({
    required this.code,
    required this.name,
    required this.unit,
  });
  final String code;
  final String name;
  final String unit;
  final List<_Pt> points = [];
  bool hasFlag = false;
  DateTime latestAt = DateTime.fromMillisecondsSinceEpoch(0);
}

class _Pt {
  _Pt(this.at, this.value, this.reported);
  final DateTime at;
  final double value;
  final String reported;
}

class _MultiTrendChart extends StatefulWidget {
  const _MultiTrendChart({
    required this.series,
    required this.colors,
    required this.onOpen,
  });

  final List<_SeriesMeta> series;
  final Map<String, Color> colors;
  final void Function(String code, String name) onOpen;

  @override
  State<_MultiTrendChart> createState() => _MultiTrendChartState();
}

class _MultiTrendChartState extends State<_MultiTrendChart> {
  Offset? _hover;
  DateTime? _hoverTime;

  static const _pad = EdgeInsets.fromLTRB(48, 24, 16, 36);

  DateTime? get _minT {
    DateTime? t;
    for (final s in widget.series) {
      for (final p in s.points) {
        if (t == null || p.at.isBefore(t)) t = p.at;
      }
    }
    return t;
  }

  DateTime? get _maxT {
    DateTime? t;
    for (final s in widget.series) {
      for (final p in s.points) {
        if (t == null || p.at.isAfter(t)) t = p.at;
      }
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final minT = _minT;
    final maxT = _maxT;
    if (minT == null || maxT == null) {
      return const Center(child: Text('Not enough points to chart.'));
    }
    final dateFmt = DateFormat('d MMM yyyy');
    final tipLines = <String>[];
    if (_hoverTime != null) {
      tipLines.add(dateFmt.format(_hoverTime!));
      for (final s in widget.series) {
        final nearest = _nearestAt(s, _hoverTime!);
        if (nearest == null) continue;
        tipLines.add(
          '${s.name}: ${nearest.reported}${s.unit.isEmpty ? '' : ' ${s.unit}'}',
        );
      }
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: BodylineChartColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        border: Border.all(color: BodylineChartColors.border),
        boxShadow: BodylineChartColors.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return MouseRegion(
            onHover: (e) {
              final t = _timeAt(e.localPosition, size, minT, maxT);
              setState(() {
                _hover = e.localPosition;
                _hoverTime = t;
              });
            },
            onExit: (_) => setState(() {
              _hover = null;
              _hoverTime = null;
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                final t = _timeAt(d.localPosition, size, minT, maxT);
                setState(() {
                  _hover = d.localPosition;
                  _hoverTime = t;
                });
              },
              onPanUpdate: (d) {
                final t = _timeAt(d.localPosition, size, minT, maxT);
                setState(() {
                  _hover = d.localPosition;
                  _hoverTime = t;
                });
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _MultiSeriesPainter(
                        series: widget.series,
                        colors: widget.colors,
                        minT: minT,
                        maxT: maxT,
                        padding: _pad,
                        hoverTime: _hoverTime,
                      ),
                    ),
                  ),
                  if (_hover != null && tipLines.isNotEmpty)
                    Positioned(
                      left: (_hover!.dx + 12).clamp(8.0, size.width - 200),
                      top: (_hover!.dy - 8).clamp(8.0, size.height - 120),
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
                                height: 1.3,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0; i < tipLines.length; i++)
                                    Text(
                                      tipLines[i],
                                      style: TextStyle(
                                        fontWeight: i == 0
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
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
      ),
    );
  }

  DateTime _timeAt(Offset local, Size size, DateTime minT, DateTime maxT) {
    final chart = _pad.deflateSize(size);
    final x = (local.dx - _pad.left).clamp(0.0, chart.width);
    final spanMs = math.max(1, maxT.difference(minT).inMilliseconds);
    final t = minT.add(
      Duration(milliseconds: ((x / chart.width) * spanMs).round()),
    );
    return t;
  }

  _Pt? _nearestAt(_SeriesMeta s, DateTime t) {
    if (s.points.isEmpty) return null;
    var best = s.points.first;
    var bestD = (best.at.difference(t)).abs();
    for (final p in s.points.skip(1)) {
      final d = (p.at.difference(t)).abs();
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }
}

class _MultiSeriesPainter extends CustomPainter {
  _MultiSeriesPainter({
    required this.series,
    required this.colors,
    required this.minT,
    required this.maxT,
    required this.padding,
    this.hoverTime,
  });

  final List<_SeriesMeta> series;
  final Map<String, Color> colors;
  final DateTime minT;
  final DateTime maxT;
  final EdgeInsets padding;
  final DateTime? hoverTime;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = padding.deflateSize(size);
    final spanMs = math.max(1, maxT.difference(minT).inMilliseconds).toDouble();

    double xFor(DateTime t) {
      final f = t.difference(minT).inMilliseconds / spanMs;
      return padding.left + chart.width * f.clamp(0.0, 1.0);
    }

    // Grid
    final grid = Paint()
      ..color = BodylineChartColors.divider
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = padding.top + chart.height * (i / 4);
      canvas.drawLine(
        Offset(padding.left, y),
        Offset(padding.left + chart.width, y),
        grid,
      );
    }

    // Axis labels (relative)
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    void label(String s, Offset o, {TextAlign align = TextAlign.left}) {
      tp.text = TextSpan(
        text: s,
        style: TextStyle(fontSize: 10, color: BodylineChartColors.inkSubtle),
      );
      tp.layout();
      var dx = o.dx;
      if (align == TextAlign.right) dx -= tp.width;
      if (align == TextAlign.center) dx -= tp.width / 2;
      tp.paint(canvas, Offset(dx, o.dy));
    }

    label('High', Offset(padding.left - 6, padding.top - 2), align: TextAlign.right);
    label(
      'Low',
      Offset(padding.left - 6, padding.top + chart.height - 10),
      align: TextAlign.right,
    );

    final dateFmt = DateFormat('MMM yy');
    label(
      dateFmt.format(minT),
      Offset(padding.left, padding.top + chart.height + 8),
    );
    label(
      dateFmt.format(maxT),
      Offset(padding.left + chart.width, padding.top + chart.height + 8),
      align: TextAlign.right,
    );

    for (final s in series) {
      if (s.points.isEmpty) continue;
      final color = colors[s.code] ?? BodylineChartColors.teal;
      final vals = [for (final p in s.points) p.value];
      var minV = vals.reduce(math.min);
      var maxV = vals.reduce(math.max);
      if ((maxV - minV).abs() < 1e-9) {
        minV -= 1;
        maxV += 1;
      }
      final spanV = maxV - minV;

      double yFor(double v) {
        final n = (v - minV) / spanV;
        return padding.top + chart.height - n * chart.height;
      }

      final path = Path();
      for (var i = 0; i < s.points.length; i++) {
        final p = s.points[i];
        final o = Offset(xFor(p.at), yFor(p.value));
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      for (final p in s.points) {
        final o = Offset(xFor(p.at), yFor(p.value));
        canvas.drawCircle(o, 3.2, Paint()..color = color);
        canvas.drawCircle(o, 1.6, Paint()..color = BodylineChartColors.surface);
      }
    }

    if (hoverTime != null) {
      final x = xFor(hoverTime!);
      canvas.drawLine(
        Offset(x, padding.top),
        Offset(x, padding.top + chart.height),
        Paint()
          ..color = BodylineChartColors.ink.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MultiSeriesPainter old) =>
      old.series != series ||
      old.hoverTime != hoverTime ||
      old.minT != minT ||
      old.maxT != maxT;
}
