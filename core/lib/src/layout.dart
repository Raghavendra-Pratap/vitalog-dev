import 'word_box.dart';

/// One cell within a layout row (gap-split words joined).
class LayoutCell {
  const LayoutCell({
    required this.boxes,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final List<WordBox> boxes;
  final double x;
  final double y;
  final double w;
  final double h;

  String get text => boxes.map((b) => b.text).join(' ').trim();

  double get midX => x + w / 2;
}

/// Horizontally clustered words that share a vertical band.
class LayoutRow {
  const LayoutRow({
    required this.cells,
    required this.y,
    required this.h,
    required this.page,
  });

  final List<LayoutCell> cells;
  final double y;
  final double h;
  final int page;

  String get text => cells.map((c) => c.text).where((t) => t.isNotEmpty).join(' ').trim();

  double get midY => y + h / 2;
}

class LayoutRebuildOptions {
  const LayoutRebuildOptions({
    this.rowTol = 0.6,
    this.gapTol = 2.0,
    this.absoluteRowTolPt,
    this.absoluteGapTolPt,
  });

  /// Relative: |centre diff| ≤ rowTol × min(rowH, wordH). OCR default 0.6.
  final double rowTol;

  /// Relative: gap > gapTol × rowH starts a new cell. OCR default 2.0.
  final double gapTol;

  /// When set (text-layer), use absolute pt tolerance instead of relative rowTol.
  final double? absoluteRowTolPt;

  /// When set (text-layer), use absolute pt gap instead of relative gapTol.
  final double? absoluteGapTolPt;

  static LayoutRebuildOptions forSource(WordBoxSource source) {
    if (source == WordBoxSource.textLayer) {
      return const LayoutRebuildOptions(
        absoluteRowTolPt: 3,
        absoluteGapTolPt: 12,
      );
    }
    return const LayoutRebuildOptions();
  }
}

/// Rebuild table-like rows/cells from positioned [WordBox]es (spec §5.1–§5.2).
List<LayoutRow> rebuildLayout(
  List<WordBox> boxes, {
  LayoutRebuildOptions? options,
}) {
  final cleaned = [
    for (final b in boxes)
      if (b.text.trim().isNotEmpty)
        WordBox(
          text: b.text.trim(),
          x: b.x,
          y: b.y,
          w: b.w < 1 ? 1 : b.w,
          h: b.h < 1 ? 1 : b.h,
          conf: b.conf,
          page: b.page,
          source: b.source,
          font: b.font,
        ),
  ];
  if (cleaned.isEmpty) return const [];

  final byPage = <int, List<WordBox>>{};
  for (final b in cleaned) {
    byPage.putIfAbsent(b.page, () => []).add(b);
  }
  final pages = byPage.keys.toList()..sort();
  final out = <LayoutRow>[];
  for (final page in pages) {
    final opts = options ??
        LayoutRebuildOptions.forSource(
          byPage[page]!.every((b) => b.source == WordBoxSource.textLayer)
              ? WordBoxSource.textLayer
              : WordBoxSource.ocr,
        );
    out.addAll(_rebuildPage(byPage[page]!, page, opts));
  }
  return out;
}

List<LayoutRow> _rebuildPage(
  List<WordBox> boxes,
  int page,
  LayoutRebuildOptions opts,
) {
  final items = [...boxes]..sort((a, b) {
      final dy = a.midY - b.midY;
      if (dy.abs() > 0.5) return dy < 0 ? -1 : 1;
      return a.x.compareTo(b.x);
    });

  final rowBoxes = <List<WordBox>>[];
  final rowMids = <double>[];
  final rowHs = <double>[];

  for (final box in items) {
    var joined = false;
    for (var i = 0; i < rowBoxes.length; i++) {
      final rowH = rowHs[i];
      final thresh = opts.absoluteRowTolPt ??
          (opts.rowTol * (rowH < box.height ? rowH : box.height));
      if ((box.midY - rowMids[i]).abs() <= thresh) {
        rowBoxes[i].add(box);
        final n = rowBoxes[i].length;
        rowMids[i] = ((rowMids[i] * (n - 1)) + box.midY) / n;
        final maxH = rowBoxes[i].fold<double>(0, (s, b) => b.height > s ? b.height : s);
        rowHs[i] = maxH;
        joined = true;
        break;
      }
    }
    if (!joined) {
      rowBoxes.add([box]);
      rowMids.add(box.midY);
      rowHs.add(box.height);
    }
  }

  // Stable top→bottom order by midY
  final order = List<int>.generate(rowBoxes.length, (i) => i)
    ..sort((a, b) => rowMids[a].compareTo(rowMids[b]));

  final rows = <LayoutRow>[];
  for (final i in order) {
    final members = rowBoxes[i]..sort((a, b) => a.x.compareTo(b.x));
    final rowH = rowHs[i];
    final cells = _splitCells(members, rowH, opts);
    final top = members.fold<double>(members.first.y, (s, b) => b.y < s ? b.y : s);
    rows.add(LayoutRow(cells: cells, y: top, h: rowH, page: page));
  }

  return _mergeMultiline(rows);
}

List<LayoutCell> _splitCells(
  List<WordBox> members,
  double rowH,
  LayoutRebuildOptions opts,
) {
  if (members.isEmpty) return const [];
  final gapLimit = opts.absoluteGapTolPt ?? (opts.gapTol * rowH);
  final groups = <List<WordBox>>[
    [members.first],
  ];
  for (var i = 1; i < members.length; i++) {
    final prev = members[i - 1];
    final cur = members[i];
    final gap = cur.x - prev.right;
    if (gap > gapLimit) {
      groups.add([cur]);
    } else {
      groups.last.add(cur);
    }
  }
  return [
    for (final g in groups)
      LayoutCell(
        boxes: g,
        x: g.first.x,
        y: g.fold<double>(g.first.y, (s, b) => b.y < s ? b.y : s),
        w: g.last.right - g.first.x,
        h: g.fold<double>(0, (s, b) => b.height > s ? b.height : s),
      ),
  ];
}

/// Spec §5.4: name-only row + following value-only row → merge.
List<LayoutRow> _mergeMultiline(List<LayoutRow> rows) {
  if (rows.length < 2) return rows;
  final out = <LayoutRow>[];
  var i = 0;
  while (i < rows.length) {
    final cur = rows[i];
    if (i + 1 < rows.length) {
      final next = rows[i + 1];
      final samePage = cur.page == next.page;
      final close = (next.y - (cur.y + cur.h)).abs() <= 1.2 * cur.h ||
          (next.midY - cur.midY).abs() <= 1.2 * cur.h;
      if (samePage && close && _looksNameOnly(cur) && _looksValueOnly(next)) {
        out.add(
          LayoutRow(
            cells: [...cur.cells, ...next.cells],
            y: cur.y,
            h: (next.y + next.h) - cur.y,
            page: cur.page,
          ),
        );
        i += 2;
        continue;
      }
    }
    out.add(cur);
    i++;
  }
  return out;
}

bool _looksNameOnly(LayoutRow row) {
  final t = row.text;
  if (t.isEmpty) return false;
  if (RegExp(r'\d').hasMatch(t) &&
      RegExp(r'\b\d{1,4}(?:\.\d+)?\b').hasMatch(t) &&
      !RegExp(r'[A-Za-z]{3,}').hasMatch(t)) {
    return false;
  }
  // Mostly letters / analyte name; no standalone result number as only cell.
  if (row.cells.length == 1 && !RegExp(r'^\d').hasMatch(row.cells.first.text)) {
    return true;
  }
  return row.cells.every((c) => !RegExp(r'^\d{1,4}(?:\.\d+)?$').hasMatch(c.text.trim()));
}

bool _looksValueOnly(LayoutRow row) {
  final t = row.text.trim();
  if (t.isEmpty) return false;
  // Starts with a number or comparator, or unit-heavy without long name.
  if (RegExp(r'^[<>]?\s*\d').hasMatch(t)) return true;
  if (row.cells.isNotEmpty &&
      RegExp(r'^\d{1,4}(?:\.\d+)?').hasMatch(row.cells.first.text.trim())) {
    return true;
  }
  return false;
}

/// Flatten layout rows to newline-separated text for legacy text parsers.
String layoutRowsToText(List<LayoutRow> rows) {
  return rows.map((r) => r.text).where((t) => t.isNotEmpty).join('\n');
}
