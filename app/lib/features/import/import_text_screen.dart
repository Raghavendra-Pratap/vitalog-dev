import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../data/ref_range_suggestions.dart';
import '../../theme/tokens.dart';
import '../../widgets/ref_range_fields.dart';
import 'package:file_picker/file_picker.dart';
import 'ocr_exception.dart';
import 'ocr_layout.dart';
import 'ocr_normalize.dart';
import 'ocr_service.dart';
import 'lab_report_date.dart';
import 'package:bodyline_core/bodyline_core.dart';
import 'pdf_text.dart';

class _ImportMatch {
  _ImportMatch(
    ParsedLabLine line, {
    List<RefRangeSuggestion>? suggestions,
    List<RefBandSetSuggestion>? bandSetSuggestions,
  })  : parameterCode = line.parameterCode,
        parameterName = line.parameterName,
        valueReported = line.valueReported,
        unitReported = line.unitReported,
        sourceLine = line.sourceLine,
        kept = true,
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
    // ADR-006: slip / OCR bands + range win — history only when empty.
    if (refs.stages) {
      // OCR already opened Stages.
    } else {
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

  final String parameterCode;
  final String parameterName;
  final String valueReported;
  final String unitReported;
  final String? sourceLine;
  final RefRangeEditState refs;
  bool kept;

  void dispose() {
    refs.dispose();
  }
}

/// M2: paste or on-device OCR (Android/iOS) → match aliases → confirm save.
class ImportTextScreen extends StatefulWidget {
  const ImportTextScreen({
    super.key,
    required this.store,
    required this.onSaved,
    this.autoOpenImage = false,
  });

  final LocalStore store;
  final VoidCallback onSaved;

  /// When true, opens the image picker once after first frame (desktop Add report).
  final bool autoOpenImage;

  @override
  State<ImportTextScreen> createState() => _ImportTextScreenState();
}

class _ImportTextScreenState extends State<ImportTextScreen> {
  final _text = TextEditingController();
  List<WordBox>? _lastBoxes;
  final _title = TextEditingController(text: 'Imported report');
  final _ocr = OcrService();
  List<_ImportMatch> _rows = [];
  var _busy = false;
  String? _ocrNote;
  var _didAutoOpenImage = false;

  int get _includedCount => _rows.where((r) => r.kept).length;

  @override
  void initState() {
    super.initState();
    if (widget.autoOpenImage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didAutoOpenImage) return;
        _didAutoOpenImage = true;
        _fromGallery();
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _title.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _fromPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      // macOS sandbox: load bytes while the open panel grants access.
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final path = file.path;
    final bytes = file.bytes;
    if ((path == null || path.isEmpty) && (bytes == null || bytes.isEmpty)) {
      if (!mounted) return;
      setState(() {
        _ocrNote =
            'Could not open that file. Try again, or paste the report text.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _ocrNote = 'Reading PDF text…';
    });
    try {
      final extracted = await extractPdfResultInteractive(
        context,
        path: path,
        bytes: bytes,
      );
      final text = extracted?.text;
      _lastBoxes = extracted?.boxes;
      if (!mounted) return;
      if (text == null || text.trim().isEmpty) {
        final encrypted = await pdfLooksEncrypted(path, bytes: bytes);
        setState(() {
          _busy = false;
          _ocrNote = encrypted
              ? 'Could not unlock that PDF. Check the password, or paste values / attach the file on Records.'
              : 'No selectable text in that PDF (often a scan). Paste values, use Android camera OCR, or attach the PDF on Records after saving.';
        });
        return;
      }
      _text.text = text;
      if (_title.text.trim().isEmpty || _title.text == 'Imported report') {
        _title.text =
            file.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      }
      setState(() {
        _busy = false;
        _ocrNote = 'PDF text extracted on-device. Review matches before saving.';
      });
      await _parse();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ocrNote = 'PDF read failed. Paste the text instead.';
      });
    }
  }

  bool get _showCamera => _ocr.supportsCamera;

  String get _photoLabel {
    if (Platform.isAndroid || Platform.isIOS) return 'Photo';
    return 'Open image';
  }

  Future<void> _fromCamera() async {
    if (!_ocr.supportsCamera) {
      setState(() {
        _ocrNote =
            'Camera is only on Android and iOS. Use Open image, PDF, or paste text.';
      });
      return;
    }
    final file = await _ocr.pickImage(source: ImageSource.camera);
    if (file == null) return;
    await _runOcr(file);
  }

  Future<void> _fromGallery() async {
    final file = await _ocr.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    await _runOcr(file);
  }

  Future<void> _runOcr(XFile file) async {
    setState(() {
      _busy = true;
      _ocrNote = 'Reading text on this device…';
    });
    try {
      final detailed = await _ocr.recognizeXFileDetailed(file);
      final text = detailed?.text;
      _lastBoxes = detailed?.boxes;
      if (!mounted) return;
      if (text == null || text.trim().isEmpty) {
        setState(() {
          _busy = false;
          _ocrNote = 'No text found. Try a clearer photo or paste the values.';
        });
        return;
      }
      _text.text = text;
      setState(() {
        _busy = false;
        _ocrNote = 'Text extracted on-device. Review matches before saving.';
      });
    } on OcrException catch (e) {
      debugPrint('ocr: ${e.kind} ${e.detail ?? ''}');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ocrNote = e.userMessage;
      });
      return;
    } catch (e) {
      debugPrint('ocr: recognize failed ${e.runtimeType}: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ocrNote = 'Could not read that image. Paste the text instead.';
      });
      return;
    }
    // Parse errors must not be mislabeled as image-read failures.
    await _parse();
  }

  Future<void> _parse() async {
    setState(() => _busy = true);
    final rows =
        (_lastBoxes != null && _lastBoxes!.length >= 4)
            ? await widget.store.parseLabFromBoxes(
                _lastBoxes!,
                bandsSource: _text.text,
                textFallback: _text.text,
              )
            : await widget.store.parseLabText(
                normalizeOcrLabText(_text.text),
                bandsSource: _text.text,
              );
    if (!mounted) return;
    final footerOnly =
        rows.isEmpty && ocrLooksLikeFooterWithoutResults(_text.text);
    final noValues =
        rows.isEmpty && !footerOnly && ocrLooksLikeLabelsWithoutValues(_text.text);
    final emptyMsg = footerOnly
        ? 'Looks like a report footer (address / page number), not the results table — reframe the photo or import the PDF.'
        : noValues
            ? "Couldn't find numbers next to test names — try a flatter photo or PDF."
            : 'No known tests matched. Check spelling or enter the panel manually.';
    for (final r in _rows) {
      r.dispose();
    }
    final pid = widget.store.activeProfileId;
    setState(() {
      _rows = [
        for (final r in rows)
          _ImportMatch(
            r,
            suggestions: pid == null
                ? const []
                : widget.store.refRangeSuggestions(pid, r.parameterCode),
            bandSetSuggestions: pid == null
                ? const []
                : widget.store.refBandSetSuggestions(pid, r.parameterCode),
          ),
      ];
      _busy = false;
      if (footerOnly || noValues) {
        _ocrNote = emptyMsg;
      }
    });
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(emptyMsg),
        ),
      );
    }
  }

  Future<void> _save() async {
    final pid = widget.store.activeProfileId;
    if (pid == null || _includedCount == 0) return;
    final dates = parseLabReportDates(_text.text);
    final custom = _title.text.trim();
    final useCustom =
        custom.isNotEmpty && custom.toLowerCase() != 'imported report';
    final kept = [for (final r in _rows) if (r.kept) r];
    final groups = await widget.store.groupParameterCodesByPanel(
      kept.map((r) => r.parameterCode),
    );
    final byCode = <String, List<_ImportMatch>>{};
    for (final r in kept) {
      (byCode[r.parameterCode] ??= []).add(r);
    }
    final seen = <String>{};
    var saved = 0;
    for (final g in groups) {
      final values = <ManualObservationInput>[];
      for (final code in g.parameterCodes) {
        if (!seen.add(code)) continue;
        final matches = byCode[code];
        if (matches == null || matches.isEmpty) continue;
        final r = matches.first;
        values.add(
          ManualObservationInput(
            parameterCode: r.parameterCode,
            parameterName: r.parameterName,
            valueReported: r.valueReported,
            unitReported: r.unitReported,
            refLow: r.refs.snapshot().low,
            refHigh: r.refs.snapshot().high,
            refBands: r.refs.snapshot().bands,
          ),
        );
      }
      if (values.isEmpty) continue;
      final title = useCustom ? '$custom · ${g.panelName}' : g.panelName;
      final report = await widget.store.addManualPanel(
        profileId: pid,
        title: title,
        collectedAt: dates.effective,
        values: values,
        source: 'import',
      );
      if (report != null) saved++;
    }
    if (!mounted) return;
    if (saved > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saved == 1 ? 'Saved 1 panel' : 'Saved $saved panels'),
        ),
      );
    }
    widget.onSaved();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import report')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            'Scan or paste a lab report. Matching uses your on-device catalogue — review before save.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_showCamera)
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _fromCamera,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _fromGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(_photoLabel),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _fromPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
            ],
          ),
          if (_ocrNote != null) ...[
            const SizedBox(height: 8),
            Text(_ocrNote!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Report title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: 'Report text',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _parse,
            child: Text(_busy ? 'Working…' : 'Match tests'),
          ),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              '$_includedCount of ${_rows.length} kept',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Uncheck anything that looks wrong before saving.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final r in _rows)
              Opacity(
                opacity: r.kept ? 1 : 0.45,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: BodylineColors.surface,
                    borderRadius:
                        BorderRadius.circular(BodylineRadii.cardSmall),
                    border: Border.all(color: BodylineColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: r.kept,
                            onChanged: (v) =>
                                setState(() => r.kept = v ?? true),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.parameterName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${r.valueReported} ${r.unitReported}',
                                ),
                                if (r.sourceLine != null &&
                                    r.sourceLine!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'From: ${r.sourceLine}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                        child: RefRangeEditor(state: r.refs,
                          enabled: r.kept,
                          dense: true,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            FilledButton(
              onPressed: _includedCount == 0 ? null : _save,
              child: Text(
                _includedCount == 0
                    ? 'Nothing selected'
                    : 'Save $_includedCount value${_includedCount == 1 ? '' : 's'}',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
