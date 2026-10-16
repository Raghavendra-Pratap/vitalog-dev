import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'ocr_exception.dart';
import 'ocr_layout.dart';
import 'ocr_normalize.dart';

/// Desktop image pick + OCR.
///
/// - **macOS:** Apple Vision via `app.vitalog/vision_ocr` MethodChannel.
/// - **Windows / Linux:** file pick works; OCR returns [OcrFailKind.unsupported]
///   (no silent fake success). Tesseract-in-app is not wired yet.
class OcrService {
  OcrService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  // ignore: unused_field — kept for API parity with mobile ctor
  final ImagePicker _picker;

  static const _visionChannel = MethodChannel('app.vitalog/vision_ocr');

  bool get isSupported => Platform.isMacOS;

  bool get supportsCamera => false;

  /// Gallery / “Open image” — prefers [FilePicker] with bytes for sandbox.
  Future<XFile?> pickImage({required ImageSource source}) async {
    if (source == ImageSource.camera) {
      return null;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'png',
        'jpg',
        'jpeg',
        'webp',
        'heic',
        'heif',
      ],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    if (f.bytes != null && f.bytes!.isNotEmpty) {
      return XFile.fromData(
        f.bytes!,
        name: f.name,
        mimeType: _mimeForName(f.name),
      );
    }
    final path = f.path;
    if (path == null || path.isEmpty) return null;
    return XFile(path, name: f.name);
  }

  Future<String?> recognizeFile(String path) =>
      recognizeXFile(XFile(path));

  Future<OcrExtractResult?> recognizeXFileDetailed(XFile file) async {
    final text = await recognizeXFile(file);
    if (text == null || text.trim().isEmpty) return null;
    return OcrExtractResult(text: text);
  }


  Future<String?> recognizeXFile(XFile file) async {
    if (!Platform.isMacOS) {
      throw const OcrException(
        OcrFailKind.unsupported,
        detail:
            'Image selected. On-device OCR for Windows/Linux is not available yet — paste the report text, or use Android/iOS / macOS.',
      );
    }

    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw const OcrException(OcrFailKind.empty, detail: 'empty bytes');
      }
      final raw = await _visionChannel.invokeMethod<String>(
        'recognizeImage',
        <String, dynamic>{
          'bytes': bytes,
          'name': file.name,
        },
      );
      if (raw == null || raw.trim().isEmpty) return null;
      return normalizeOcrLabText(raw);
    } on OcrException {
      rethrow;
    } on PlatformException catch (e) {
      debugPrint('ocr: vision PlatformException ${e.code}: ${e.message}');
      if (e.code == 'decode') {
        throw OcrException(OcrFailKind.decode, detail: e.message, cause: e);
      }
      throw OcrException(OcrFailKind.process, detail: e.message, cause: e);
    } catch (e, st) {
      debugPrint('ocr: desktop ${e.runtimeType}: $e');
      debugPrint('ocr: stack $st');
      throw OcrException(OcrFailKind.process, detail: e.toString(), cause: e);
    }
  }

  String? _mimeForName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.heic') || n.endsWith('.heif')) return 'image/heic';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    return null;
  }
}
