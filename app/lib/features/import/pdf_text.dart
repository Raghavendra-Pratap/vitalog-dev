import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ocr_normalize.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../theme/tokens.dart';

enum PdfExtractStatus {
  ok,
  needsPassword,
  wrongPassword,
  failed,
  empty,
}

class PdfExtractResult {
  const PdfExtractResult({
    required this.status,
    this.text,
  });

  final PdfExtractStatus status;
  final String? text;
}

/// Best-effort PDF text for import (Android + desktop).
/// Prefer Syncfusion (password-aware, cross-platform); then OS `pdftotext`; then scrape.
/// Password is used only for this read — never stored.
///
/// Pass [bytes] when available (macOS sandbox: file_picker `withData` / copied temp).
Future<PdfExtractResult> extractPdfText(
  String? path, {
  Uint8List? bytes,
  String? password,
}) async {
  final data = await _resolveBytes(path: path, bytes: bytes);
  if (data == null || data.isEmpty) {
    debugPrint('pdf_text: no readable bytes (path=$path)');
    return const PdfExtractResult(status: PdfExtractStatus.failed);
  }

  final encrypted = _bytesLookEncrypted(data);

  // 1) Syncfusion — works on Android / iOS / desktop with user password.
  final sync = _extractWithSyncfusionBytes(data, password: password);
  if (sync.status == PdfExtractStatus.ok) return sync;
  // Ask for password before other fallbacks — Syncfusion already knows it's locked.
  if (sync.status == PdfExtractStatus.needsPassword ||
      sync.status == PdfExtractStatus.wrongPassword) {
    return sync;
  }

  // 2) Desktop Poppler when available (may be blocked by App Sandbox).
  String? workPath = path;
  if (workPath == null || !await File(workPath).exists()) {
    workPath = await _writeTempPdf(data);
  }
  if (workPath != null) {
    final pdftotext = await _which('pdftotext');
    if (pdftotext != null) {
      final args = <String>['-layout', '-enc', 'UTF-8'];
      if (password != null && password.isNotEmpty) {
        args.addAll(['-upw', password]);
      }
      args.addAll([workPath, '-']);
      try {
        final out = await Process.run(pdftotext, args);
        final text = (out.stdout as String?)?.trim() ?? '';
        final err = (out.stderr as String?) ?? '';

        if (out.exitCode == 0 && text.isNotEmpty) {
          return PdfExtractResult(status: PdfExtractStatus.ok, text: normalizeOcrLabText(text));
        }

        final authFail = _looksLikeAuthFailure(err) ||
            (encrypted && text.isEmpty && out.exitCode != 0);
        if (authFail) {
          return PdfExtractResult(
            status: password == null || password.isEmpty
                ? PdfExtractStatus.needsPassword
                : PdfExtractStatus.wrongPassword,
          );
        }
      } catch (e) {
        debugPrint('pdf_text: pdftotext failed: $e');
      }
    }
  }

  if (sync.status == PdfExtractStatus.needsPassword ||
      sync.status == PdfExtractStatus.wrongPassword) {
    return sync;
  }

  if (encrypted) {
    return PdfExtractResult(
      status: password == null || password.isEmpty
          ? PdfExtractStatus.needsPassword
          : PdfExtractStatus.wrongPassword,
    );
  }

  // 3) Naive scrape for simple unlocked PDFs.
  final scraped = _scrapePdfStreams(data);
  if (scraped != null && scraped.trim().isNotEmpty) {
    return PdfExtractResult(status: PdfExtractStatus.ok, text: normalizeOcrLabText(scraped.trim()));
  }

  if (sync.status == PdfExtractStatus.empty ||
      sync.status == PdfExtractStatus.failed) {
    return sync.status == PdfExtractStatus.failed
        ? sync
        : const PdfExtractResult(status: PdfExtractStatus.empty);
  }

  return const PdfExtractResult(status: PdfExtractStatus.empty);
}

PdfExtractResult _extractWithSyncfusionBytes(
  Uint8List bytes, {
  String? password,
}) {
  try {
    PdfDocument document;
    try {
      document = PdfDocument(
        inputBytes: bytes,
        password: password ?? '',
      );
    } catch (e) {
      debugPrint('pdf_text: Syncfusion open failed: $e');
      if (_looksLikePasswordError(e) || _bytesLookEncrypted(bytes)) {
        return PdfExtractResult(
          status: password == null || password.isEmpty
              ? PdfExtractStatus.needsPassword
              : PdfExtractStatus.wrongPassword,
        );
      }
      return const PdfExtractResult(status: PdfExtractStatus.failed);
    }

    try {
      final extractor = PdfTextExtractor(document);
      final pageCount = document.pages.count;
      final buf = StringBuffer();
      for (var i = 0; i < pageCount; i++) {
        // Prefer layout-aware extract (Agilus-style positioned tables),
        // then word-bounded text lines sorted by reading order.
        final layout = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
          layoutText: true,
        );
        final lines = extractor.extractTextLines(
          startPageIndex: i,
          endPageIndex: i,
        );
        final fromLines = _textFromPdfLines(lines);
        final pageText = _pickBetterPdfPageText(layout, fromLines);
        if (pageText.trim().isEmpty) continue;
        if (buf.isNotEmpty) buf.writeln();
        buf.writeln('--- page ${i + 1} of $pageCount ---');
        buf.writeln(pageText.trim());
      }
      final text = buf.toString().trim();
      debugPrint(
        'pdf_text: Syncfusion pages=$pageCount chars=${text.length}',
      );
      try {
        File('/tmp/vitalog_last_extract.txt').writeAsStringSync(text);
      } catch (_) {}
      if (text.isEmpty) {
        return const PdfExtractResult(status: PdfExtractStatus.empty);
      }
      return PdfExtractResult(
        status: PdfExtractStatus.ok,
        text: normalizeOcrLabText(text),
      );
    } finally {
      document.dispose();
    }
  } catch (e) {
    debugPrint('pdf_text: Syncfusion extract failed: $e');
    return const PdfExtractResult(status: PdfExtractStatus.failed);
  }
}

/// Pick → unlock if needed → return text (or null if cancelled / failed).
Future<String?> extractPdfTextInteractive(
  BuildContext context, {
  String? path,
  Uint8List? bytes,
}) async {
  var result = await extractPdfText(path, bytes: bytes);
  if (result.status == PdfExtractStatus.ok) return result.text;

  if (result.status == PdfExtractStatus.needsPassword ||
      result.status == PdfExtractStatus.wrongPassword) {
    while (true) {
      if (!context.mounted) return null;
      final password = await _askPdfPassword(
        context,
        wrong: result.status == PdfExtractStatus.wrongPassword,
      );
      if (password == null) return null;
      result = await extractPdfText(path, bytes: bytes, password: password);
      if (result.status == PdfExtractStatus.ok) return result.text;
      if (result.status != PdfExtractStatus.wrongPassword &&
          result.status != PdfExtractStatus.needsPassword) {
        break;
      }
    }
  }

  return null;
}

Future<bool> pdfLooksEncrypted(String? path, {Uint8List? bytes}) async {
  final data = await _resolveBytes(path: path, bytes: bytes);
  if (data == null) return false;
  return _bytesLookEncrypted(data);
}

bool _bytesLookEncrypted(Uint8List bytes) {
  try {
    // Encryption dict can sit past the first pages on large lab PDFs — scan all.
    final raw = latin1.decode(bytes, allowInvalid: true);
    return raw.contains('/Encrypt');
  } catch (_) {
    return false;
  }
}

bool _looksLikePasswordError(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('password') ||
      s.contains('encrypted') ||
      s.contains('cannot open an encrypted');
}

Future<Uint8List?> _resolveBytes({
  String? path,
  Uint8List? bytes,
}) async {
  if (bytes != null && bytes.isNotEmpty) return bytes;
  if (path == null || path.isEmpty) return null;
  try {
    return await File(path).readAsBytes();
  } catch (e) {
    debugPrint('pdf_text: File.readAsBytes failed for $path: $e');
    return null;
  }
}

Future<String?> _writeTempPdf(Uint8List bytes) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/vitalog_import_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (e) {
    debugPrint('pdf_text: temp write failed: $e');
    return null;
  }
}

bool _looksLikeAuthFailure(String err) {
  final e = err.toLowerCase();
  return e.contains('incorrect password') ||
      e.contains('invalid password') ||
      e.contains('encrypted') ||
      e.contains('password required') ||
      e.contains('owner password') ||
      e.contains('user password') ||
      e.contains('authentication');
}

Future<String?> _askPdfPassword(
  BuildContext context, {
  required bool wrong,
}) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('PDF password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            wrong
                ? 'That password did not unlock the report. Try again.'
                : 'This report is password-protected. Enter the password from your lab portal or email — Vitalog does not keep it.',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Password',
            ),
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: BodylineColors.ink,
            foregroundColor: BodylineColors.onInk,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Unlock'),
        ),
      ],
    ),
  );
  final value = controller.text;
  controller.dispose();
  if (ok != true) return null;
  return value;
}

Future<String?> _which(String cmd) async {
  try {
    final r = await Process.run('which', [cmd]);
    if (r.exitCode == 0) {
      final p = (r.stdout as String).trim();
      if (p.isNotEmpty) return p;
    }
  } catch (_) {}
  // Homebrew common paths (sandbox may still block exec).
  for (final p in [
    '/opt/homebrew/bin/$cmd',
    '/usr/local/bin/$cmd',
  ]) {
    if (await File(p).exists()) return p;
  }
  return null;
}


String _textFromPdfLines(List<TextLine> lines) {
  if (lines.isEmpty) return '';
  final sorted = [...lines]..sort((a, b) {
      final page = a.pageIndex.compareTo(b.pageIndex);
      if (page != 0) return page;
      final dy = a.bounds.top.compareTo(b.bounds.top);
      if (dy != 0) return dy;
      return a.bounds.left.compareTo(b.bounds.left);
    });
  return sorted
      .map((l) => l.text.trim())
      .where((t) => t.isNotEmpty)
      .join('\n');
}

/// Prefer the extract that keeps analyte + value on fewer broken lines.
String _pickBetterPdfPageText(String layout, String fromLines) {
  final a = layout.trim();
  final b = fromLines.trim();
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  return _pdfExtractScore(a) >= _pdfExtractScore(b) ? a : b;
}

int _pdfExtractScore(String text) {
  final lines = [
    for (final l in text.split(RegExp(r'\r?\n')))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.isEmpty) return 0;
  var score = 0;
  var short = 0;
  for (final l in lines) {
    if (!l.contains(' ') && l.length <= 18) short++;
    if (RegExp(r'[A-Za-z]{3,}.*\d+(?:\.\d+)?').hasMatch(l) &&
        l.split(RegExp(r'\s+')).length >= 2) {
      score += 8;
    }
    if (RegExp(
      r'\b(mg/?dL|g/?dL|U/?L|mU/?L|uIU/?mL|µIU/?mL|ng/?mL)\b',
      caseSensitive: false,
    ).hasMatch(l)) {
      score += 3;
    }
  }
  final shortRatio = short / lines.length;
  if (shortRatio > 0.55) score -= 40;
  if (shortRatio < 0.25) score += 15;
  score += lines.where((l) => l.length > 24).length;
  return score;
}

String? _scrapePdfStreams(Uint8List bytes) {
  try {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final buf = StringBuffer();
    final tj = RegExp(r'\(([^\\()]*(?:\\.[^\\()]*)*)\)\s*Tj');
    for (final m in tj.allMatches(raw)) {
      var s = m.group(1)!;
      s = s
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\r', '')
          .replaceAll(r'\t', ' ')
          .replaceAll(r'\(', '(')
          .replaceAll(r'\)', ')')
          .replaceAll(r'\\', r'\');
      if (s.trim().isNotEmpty) buf.writeln(s);
    }
    final text = buf.toString().trim();
    return text.isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}
