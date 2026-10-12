import 'package:flutter/material.dart';
import '../../widgets/month_year_date_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../desktop.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import 'lab_report_date.dart';
import '../../widgets/report_title.dart';
import '../../widgets/ref_range_fields.dart';
import '../../data/ref_range_suggestions.dart';
import 'ocr_layout.dart';
import 'ocr_normalize.dart';
import 'pdf_text.dart';

/// PDF / paste review: preview extract, confirm catalogue matches, save panel.
class ReportReviewScreen extends StatefulWidget {
  const ReportReviewScreen({
    super.key,
    required this.store,
    required this.onSaved,
    this.initialText,
    this.initialTitle,
  });

  final LocalStore store;
  final VoidCallback onSaved;
  final String? initialText;
  final String? initialTitle;

  @override
  State<ReportReviewScreen> createState() => _ReportReviewScreenState();
}

class _EditableMatch {
  _EditableMatch(
    ParsedLabLine line, {
    List<RefRangeSuggestion>? suggestions,
    List<RefBandSetSuggestion>? bandSetSuggestions,
  })  : pageIndex = line.pageIndex,
        parameterCode = line.parameterCode,
        parameterName = line.parameterName,
        value = TextEditingController(text: line.valueReported),
        unit = TextEditingController(text: line.unitReported),
        sourceLine = line.sourceLine,
        included = true,
        refs = RefRangeEditState(
          low: TextEditingController(
            text: line.refLow == null ? '' : formatRefNum(line.refLow!),
          ),
          high: TextEditingController(
            text: line.refHigh == null ? '' : formatRefNum(line.refHigh!),
          ),
          initialBands: line.refBands,
          rangeSuggestions: suggestions ?? const [],
          bandSetSuggestions: bandSetSuggestions ?? const [],
          preferStages:
              line.refBands != null && line.refBands!.length >= 2,
        ) {
    // ADR-006: slip range / OCR bands win — history only fills empties.
    if (!refs.stages) {
      autofillRefsFromHistory(
        low: refs.low,
        high: refs.high,
        suggestions: refs.rangeSuggestions,
      );
      if (refsAndBandsEmpty(
        lowText: refs.low.text,
        highText: refs.high.text,
        bands: refs.parsedBands,
      )) {
        autofillBandsFromHistory(state: refs);
      }
    }
  }

  final int pageIndex;
  final String parameterCode;
  final String parameterName;
  final TextEditingController value;
  final TextEditingController unit;
  final RefRangeEditState refs;
  final String? sourceLine;
  bool included;

  void dispose() {
    value.dispose();
    unit.dispose();
    refs.dispose();
  }
}

class _ReportReviewScreenState extends State<ReportReviewScreen> {
  final _title = TextEditingController();
  List<_EditableMatch> _rows = [];
  int? _pageFilter; // null = all pages
  var _busy = false;
  String? _note;
  String _rawPreview = '';
  var _showFullExtract = true;
  DateTime? _collectedAt;
  String? _collectedSource;
  String? _sourcePdfPath;
  List<int>? _sourcePdfBytes;
  String? _sourcePdfName;

  @override
  void initState() {
    super.initState();
    _title.text = widget.initialTitle ?? 'Imported report';
    if (widget.initialText != null && widget.initialText!.trim().isNotEmpty) {
      _rawPreview = widget.initialText!;
      _applyDatesFromText(widget.initialText!);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _parse(widget.initialText!));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  List<_EditableMatch> get _visibleRows {
    if (_pageFilter == null) return _rows;
    return [for (final r in _rows) if (r.pageIndex == _pageFilter) r];
  }

  int get _includedCount =>
      _rows.where((r) => r.included && r.value.text.trim().isNotEmpty).length;

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final path = file.path;
    final bytes = file.bytes;
    if ((path == null || path.isEmpty) && (bytes == null || bytes.isEmpty)) {
      if (!mounted) return;
      setState(() {
        _note =
            'Could not open that file. Try again, or paste the report text.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _note = 'Reading PDF text…';
    });
    try {
      final text = await extractPdfTextInteractive(
        context,
        path: path,
        bytes: bytes,
      );
      if (!mounted) return;
      if (text == null || text.trim().isEmpty) {
        final encrypted = await pdfLooksEncrypted(path, bytes: bytes);
        setState(() {
          _busy = false;
          _note = encrypted
              ? 'Could not unlock that PDF. Check the password, or paste values / attach the file on Records.'
              : 'No selectable text in that PDF (often a scan). Paste values, use Android camera OCR, or attach the PDF on Records after saving.';
        });
        return;
      }
      if (_title.text == 'Imported report') {
        _title.text = displayReportTitle(
          file.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
        );
      }
      _sourcePdfPath = path;
      _sourcePdfBytes = bytes;
      _sourcePdfName = file.name;
      _rawPreview = text;
      setState(() {
        _busy = false;
        _note = 'PDF text extracted on-device. Review matches before saving.';
      });
      await _parse(text);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _note = 'PDF read failed.';
      });
    }
  }

  Future<void> _parse(String text) async {
    setState(() => _busy = true);
    final rows = await widget.store.parseLabText(normalizeOcrLabText(text), bandsSource: text);
    if (!mounted) return;
    for (final r in _rows) {
      r.dispose();
    }
    setState(() {
      _rawPreview = text;
      final pid = widget.store.activeProfileId;
      _rows = [
        for (final r in rows)
          _EditableMatch(
            r,
            suggestions: pid == null
                ? const []
                : widget.store.refRangeSuggestions(pid, r.parameterCode),
            bandSetSuggestions: pid == null
                ? const []
                : widget.store.refBandSetSuggestions(pid, r.parameterCode),
          ),
      ];
      _pageFilter = null;
      _busy = false;
      _showFullExtract = true;
      _applyDatesFromText(text);
      final pages = _pageCountFromPreview();
      final dateBit = _collectedAt == null
          ? ''
          : ' · check date ${_fmtDate(_collectedAt!)}'
              '${_collectedSource == null ? '' : ' (${_collectedSource!})'}';
      if (rows.isEmpty) {
        if (ocrLooksLikeFooterWithoutResults(text)) {
          _note =
              'Looks like a report footer (address / page number), not the results table — reframe the photo or import the PDF.';
        } else if (ocrLooksLikeLabelsWithoutValues(text)) {
          _note =
              "Couldn't find numbers next to test names — try a flatter photo or PDF.";
        } else {
          _note =
              'No known tests matched across $pages page(s). Try All pages view, or enter a panel manually.';
        }
      } else {
        final byPage = <int, int>{};
        for (final r in rows) {
          byPage[r.pageIndex] = (byPage[r.pageIndex] ?? 0) + 1;
        }
        final spread = byPage.entries
            .map((e) => 'p${e.key}:${e.value}')
            .join(' · ');
        _note =
            '$pages page(s) · ${rows.length} matches ($spread)$dateBit. Edit values per page, then save all.';
      }
    });
  }

  Future<void> _save() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;
    // First included wins when the same parameter appears on multiple pages.
    final seen = <String>{};
    final values = <ManualObservationInput>[];
    for (final p in _rows) {
      if (!p.included) continue;
      final v = p.value.text.trim();
      if (v.isEmpty) continue;
      if (!seen.add(p.parameterCode)) continue;
      values.add(
        ManualObservationInput(
          parameterCode: p.parameterCode,
          parameterName: p.parameterName,
          valueReported: v,
          unitReported: p.unit.text.trim(),
          refLow: p.refs.snapshot().low,
          refHigh: p.refs.snapshot().high,
          refBands: p.refs.snapshot().bands,
        ),
      );
    }
    if (values.isEmpty) return;
    final report = await widget.store.addManualPanel(
      profileId: pid,
      title: _title.text.trim().isEmpty ? 'Imported report' : _title.text.trim(),
      collectedAt: _collectedAt ?? DateTime.now(),
      values: values,
      source: 'import',
    );
    if (report == null) return;
    // Keep the imported PDF as the encrypted original on this report.
    try {
      final name = _sourcePdfName ?? 'lab-report.pdf';
      if (_sourcePdfPath != null && _sourcePdfPath!.isNotEmpty) {
        await widget.store.addAttachment(
          ownerType: 'report',
          ownerId: report.id,
          filePath: _sourcePdfPath!,
          mime: 'application/pdf',
          fileName: name,
        );
      } else if (_sourcePdfBytes != null && _sourcePdfBytes!.isNotEmpty) {
        await widget.store.addAttachmentBytes(
          ownerType: 'report',
          ownerId: report.id,
          bytes: _sourcePdfBytes!,
          mime: 'application/pdf',
          fileName: name,
        );
      }
    } catch (_) {
      // Values already saved; original can be attached later from Records.
    }
    if (!mounted) return;
    widget.onSaved();
    Navigator.of(context).pop();
  }

  ProfileRecord? get _profile {
    final id = widget.store.activeProfileId;
    for (final p in widget.store.profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _applyDatesFromText(String text) {
    final dates = parseLabReportDates(text);
    _collectedAt = dates.collectedAt ?? dates.reportedAt;
    _collectedSource = dates.sourceLabel;
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  Future<void> _pickCollectedDate() async {
    final now = DateTime.now();
    final initial = _collectedAt ?? now;
    final picked = await pickBodylineDate(
      context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(now.year - 30),
      lastDate: now.add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _collectedAt = DateTime(picked.year, picked.month, picked.day);
      _collectedSource = 'Set manually';
    });
  }

  int _pageCountFromPreview() {
    final matches =
        RegExp(r'^--- page (\d+)', multiLine: true).allMatches(_rawPreview);
    if (matches.isEmpty) return _rawPreview.trim().isEmpty ? 0 : 1;
    var max = 0;
    for (final m in matches) {
      final n = int.tryParse(m.group(1) ?? '') ?? 0;
      if (n > max) max = n;
    }
    return max;
  }

  String _extractFooterLabel() {
    if (_rawPreview.isEmpty && _rows.isEmpty) {
      return 'Paste or PDF text preview';
    }
    final pages = _pageCountFromPreview();
    final pageBit =
        pages <= 1 ? '1 page extracted' : '$pages pages extracted';
    if (_rows.isEmpty) return pageBit;
    if (_showFullExtract) {
      return '$pageBit · full text · ${_rows.length} catalogue matches';
    }
    return '$pageBit · ${_rows.length} matched — open All pages to scroll the full report';
  }

  Widget _collectedDateField() {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Check / collection date',
        helperText: _collectedAt == null
            ? 'Not found in PDF — using today unless you set one'
            : (_collectedSource == null
                ? 'From report text'
                : 'From report: ${_collectedSource!}'),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _collectedAt == null ? 'Tap to set' : _fmtDate(_collectedAt!),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          TextButton(
            onPressed: _pickCollectedDate,
            child: Text(_collectedAt == null ? 'Set' : 'Change'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = useWideShell(context);
    final profile = _profile;

    return Scaffold(
      backgroundColor: BodylineColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              wide ? DesktopLayout.mainPaddingH : 20,
              wide ? DesktopLayout.mainPaddingV : 12,
              wide ? DesktopLayout.mainPaddingH : 20,
              8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Review report',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        [
                          if (_title.text.trim().isNotEmpty) _title.text.trim(),
                          if (profile != null) 'for ${profile.name}',
                          if (_rows.isNotEmpty)
                            '$_includedCount of ${_rows.length} to save',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (_note != null)
                        Text(
                          _note!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _includedCount == 0 || _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: BodylineColors.ink,
                    foregroundColor: BodylineColors.onInk,
                  ),
                  child: Text(
                    _includedCount == 0
                        ? 'Save values'
                        : 'Save all ($_includedCount)',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                wide ? DesktopLayout.mainPaddingH : 16,
                0,
                wide ? DesktopLayout.mainPaddingH : 16,
                wide ? DesktopLayout.mainPaddingV : 16,
              ),
              child: wide ? _wideBody() : _narrowBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wideBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 520,
          child: _reportPagePane(),
        ),
        const SizedBox(width: DesktopLayout.mainGap),
        Expanded(child: _matchedPane()),
      ],
    );
  }

  Widget _narrowBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 24),
      children: [
        _pickActions(),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Report title'),
        ),
        const SizedBox(height: 10),
        _collectedDateField(),
        const SizedBox(height: 12),
        SizedBox(height: 280, child: _reportPagePane()),
        const SizedBox(height: 16),
        SizedBox(height: 360, child: _matchedPane()),
      ],
    );
  }

  Widget _pickActions() {
    return Wrap(
      spacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _pickPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Choose PDF'),
        ),
      ],
    );
  }

  Widget _buildPreviewBody() {
    if (_rows.isEmpty || _showFullExtract) {
      final lines = _rawPreview.isEmpty
          ? const <String>['No extract yet.']
          : _rawPreview.split(RegExp(r'\r?\n'));
      return ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final line = lines[i];
          final isPage = line.startsWith('--- page ');
          return Text(
            line.isEmpty ? ' ' : line,
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 11,
              fontWeight: isPage ? FontWeight.w700 : FontWeight.w400,
              color: isPage ? BodylineColors.teal : BodylineColors.inkMuted,
              height: 1.35,
            ),
          );
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      itemCount: _rows.length,
      itemBuilder: (context, i) {
        final r = _rows[i];
        final snap = r.refs.snapshot();
        final lo = snap.low;
        final hi = snap.high;
        final bandN = snap.bands?.length ?? 0;
        final range = bandN >= 2
            ? '$bandN stages'
            : ((lo != null || hi != null)
                ? '${lo ?? '—'}–${hi ?? '—'}'
                : '—');
        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: r.included ? BodylineColors.surface : BodylineColors.chip,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: BodylineColors.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  'p${r.pageIndex}',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: BodylineColors.teal,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  r.sourceLine ?? r.parameterName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 12,
                    color: BodylineColors.ink,
                  ),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  r.value.text,
                  style: const TextStyle(fontFamily: 'Georgia', fontSize: 12),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  r.unit.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Georgia', fontSize: 12),
                ),
              ),
              SizedBox(
                width: 84,
                child: Text(
                  range,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Georgia', fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _reportPagePane() {
    return Container(
      decoration: BoxDecoration(
        color: BodylineColors.chip,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (_rawPreview.isEmpty && _rows.isEmpty) ...[
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Add a lab PDF to review extracted values\nagainst the original page.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: BodylineColors.inkMuted),
                    ),
                    const SizedBox(height: 16),
                    _pickActions(),
                  ],
                ),
              ),
            ),
          ] else ...[
            Align(alignment: Alignment.centerLeft, child: _pickActions()),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: 440,
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                decoration: BoxDecoration(
                  color: BodylineColors.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _title.text.trim().isEmpty
                          ? 'LAB REPORT'
                          : _title.text.trim().toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: BodylineColors.ink,
                      ),
                    ),
                    Text(
                      [
                        if (_profile != null) 'Patient: ${_profile!.name}',
                        'Extracted on this device',
                        if (_collectedAt != null)
                          'Check ${_fmtDate(_collectedAt!)}',
                      ].join(' · '),
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 12,
                        color: BodylineColors.inkMuted,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: BodylineColors.divider),
                    ),
                    const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Test',
                            style: TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            'Result',
                            style: TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            'Unit',
                            style: TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: Text(
                            'Ref. range',
                            style: TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (_rawPreview.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ChoiceChip(
                              label: Text(
                                _rows.isEmpty
                                    ? 'Matched'
                                    : 'Matched (${_rows.length})',
                              ),
                              selected: !_showFullExtract,
                              onSelected: (v) {
                                if (v) {
                                  setState(() => _showFullExtract = false);
                                }
                              },
                            ),
                            ChoiceChip(
                              label: Text(
                                'All pages (${_pageCountFromPreview()})',
                              ),
                              selected: _showFullExtract,
                              onSelected: (v) {
                                if (v) {
                                  setState(() => _showFullExtract = true);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ColoredBox(
                        color: BodylineColors.surface,
                        child: _buildPreviewBody(),
                      ),
                    ),
                    Divider(color: BodylineColors.divider),
                    Text(
                      _extractFooterLabel(),
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 11,
                        color: BodylineColors.inkSubtle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _matchedPane() {
    final pages = {
      for (final r in _rows) r.pageIndex,
    }.toList()
      ..sort();
    final visible = _visibleRows;
    final included = _includedCount;
    final skipped = _rows.length - included;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        border: Border.all(color: BodylineColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (useWideShell(context)) ...[
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Report title',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            _collectedDateField(),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Text(
                '$included to save',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: BodylineColors.tealDark,
                    ),
              ),
              const SizedBox(width: 16),
              Text(
                skipped == 0 ? '${_rows.length} matched' : '$skipped excluded',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: BodylineColors.inkSubtle,
                    ),
              ),
            ],
          ),
          if (pages.length > 1) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('All pages (${_rows.length})'),
                      selected: _pageFilter == null,
                      onSelected: (_) => setState(() => _pageFilter = null),
                    ),
                  ),
                  for (final p in pages)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          'Page $p (${_rows.where((r) => r.pageIndex == p).length})',
                        ),
                        selected: _pageFilter == p,
                        onSelected: (_) => setState(() => _pageFilter = p),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(width: 40),
              Expanded(
                flex: 3,
                child: Text(
                  'Parameter',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: BodylineColors.inkSubtle,
                  ),
                ),
              ),
              SizedBox(
                width: 88,
                child: Text(
                  'Value',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: BodylineColors.inkSubtle,
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  'Unit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: BodylineColors.inkSubtle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _busy
                ? const Center(child: Text('Matching…'))
                : visible.isEmpty
                    ? Center(
                        child: Text(
                          _rows.isEmpty
                              ? 'Matched values appear here.'
                              : 'No matches on this page.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final r = visible[i];
                          final showPageHeader = i == 0 ||
                              visible[i - 1].pageIndex != r.pageIndex;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showPageHeader && _pageFilter == null)
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: i == 0 ? 0 : 12,
                                    bottom: 6,
                                  ),
                                  child: Text(
                                    'Page ${r.pageIndex}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: BodylineColors.tealDark,
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Opacity(
                                  opacity: r.included ? 1 : 0.45,
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(minHeight: 56),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: BodylineColors.tealTint,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: BodylineColors.divider,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Checkbox(
                                              value: r.included,
                                              onChanged: (v) => setState(
                                                () => r.included = v ?? true,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 3,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    r.parameterName,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  Text(
                                                    [
                                                      'Page ${r.pageIndex}',
                                                      if (r.sourceLine != null)
                                                        '“${r.sourceLine!}”',
                                                    ].join(' · '),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            SizedBox(
                                              width: 88,
                                              child: TextField(
                                                controller: r.value,
                                                enabled: r.included,
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                  decimal: true,
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                  isDense: true,
                                                  border: OutlineInputBorder(),
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 8,
                                                  ),
                                                ),
                                                onChanged: (_) =>
                                                    setState(() {}),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            SizedBox(
                                              width: 72,
                                              child: TextField(
                                                controller: r.unit,
                                                enabled: r.included,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                  isDense: true,
                                                  border: OutlineInputBorder(),
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 8,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        RefRangeEditor(state: r.refs,
                                          enabled: r.included,
                                          dense: true,
                                          onChanged: () => setState(() {}),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

}
