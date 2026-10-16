import 'dart:io';

import 'package:image_picker/image_picker.dart';

import 'ocr_layout.dart';
import 'ocr_service_desktop.dart' as desktop;
import 'ocr_service_mobile.dart' as mobile;

/// ML Kit on Android/iOS; Vision on macOS; honest stub OCR on Windows/Linux.
class OcrService {
  OcrService({ImagePicker? picker})
      : _impl = (Platform.isAndroid || Platform.isIOS)
            ? mobile.OcrService(picker: picker)
            : desktop.OcrService(picker: picker);

  final dynamic _impl;

  bool get isSupported => _impl.isSupported as bool;

  bool get supportsCamera => _impl.supportsCamera as bool;

  Future<XFile?> pickImage({required ImageSource source}) =>
      _impl.pickImage(source: source) as Future<XFile?>;

  Future<String?> recognizeFile(String path) =>
      _impl.recognizeFile(path) as Future<String?>;

  Future<String?> recognizeXFile(XFile file) =>
      _impl.recognizeXFile(file) as Future<String?>;

  Future<OcrExtractResult?> recognizeXFileDetailed(XFile file) async {
    try {
      return await _impl.recognizeXFileDetailed(file) as OcrExtractResult?;
    } catch (_) {
      final text = await recognizeXFile(file);
      if (text == null || text.trim().isEmpty) return null;
      return OcrExtractResult(text: text);
    }
  }
}
