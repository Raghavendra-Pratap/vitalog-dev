import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'ocr_exception.dart';
import 'ocr_layout.dart';
import 'ocr_normalize.dart';

/// On-device OCR via Google ML Kit (Android / iOS).
///
/// Pipeline: XFile bytes → decode (package:image, then Flutter codec) →
/// bake EXIF → cap long edge → JPEG temp → [InputImage.fromFilePath],
/// with raw-bytes fallback if the file path still fails.
class OcrService {
  OcrService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  static const int _maxLongEdge = 2000;
  static const int _jpegQuality = 85;
  /// Second pass when first OCR has analyte names but no result numbers.
  static const int _hiResLongEdge = 3200;
  static const int _hiResJpegQuality = 95;

  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// Camera capture is mobile-only.
  bool get supportsCamera => Platform.isAndroid || Platform.isIOS;

  Future<XFile?> pickImage({required ImageSource source}) =>
      _picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 2400,
        requestFullMetadata: false,
      );

  /// Prefer [recognizeXFile] — picker paths are not always ML Kit-readable.
  Future<String?> recognizeFile(String path) =>
      recognizeXFile(XFile(path));

  Future<String?> recognizeXFile(XFile file) async {
    if (!isSupported) {
      throw const OcrException(OcrFailKind.unsupported);
    }

    File? tmp;
    File? tmpHi;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final prepared = await _prepareJpeg(file);
      tmp = prepared.file;

      var text = await _recognizePrepared(recognizer, prepared);
      if (text == null || text.trim().isEmpty) return null;

      // Multi-pass: names-without-values or footer-only → higher-res JPEG
      // (do not invent numbers).
      final normalized = normalizeOcrLabText(text);
      final weak = ocrLooksLikeLabelsWithoutValues(normalized) ||
          ocrLooksLikeFooterWithoutResults(normalized);
      if (weak) {
        debugPrint(
          'ocr: weak extract (labels-only or footer) — retry hi-res',
        );
        try {
          final hi = await _prepareJpeg(
            file,
            maxLongEdge: _hiResLongEdge,
            jpegQuality: _hiResJpegQuality,
          );
          tmpHi = hi.file;
          final text2 = await _recognizePrepared(recognizer, hi);
          if (text2 != null && text2.trim().isNotEmpty) {
            final n2 = normalizeOcrLabText(text2);
            final stillWeak = ocrLooksLikeLabelsWithoutValues(n2) ||
                ocrLooksLikeFooterWithoutResults(n2);
            if (!stillWeak ||
                ocrLabValueSignal(n2) > ocrLabValueSignal(normalized)) {
              return n2;
            }
          }
        } catch (e, st) {
          debugPrint('ocr: hi-res retry failed ${e.runtimeType}: $e');
          debugPrint('ocr: stack $st');
        }
      }
      return normalized;
    } on OcrException {
      rethrow;
    } catch (e, st) {
      debugPrint('ocr: recognizeXFile ${e.runtimeType}: $e');
      debugPrint('ocr: stack $st');
      throw OcrException(OcrFailKind.process, detail: e.toString(), cause: e);
    } finally {
      await recognizer.close();
      for (final f in [tmp, tmpHi]) {
        if (f != null) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }
  }

  Future<String?> _recognizePrepared(
    TextRecognizer recognizer,
    _PreparedImage prepared,
  ) async {
    try {
      return await _runRecognizer(
        recognizer,
        InputImage.fromFilePath(prepared.file.path),
      );
    } catch (e, st) {
      debugPrint(
        'ocr: fromFilePath failed ${e.runtimeType}: $e',
      );
      debugPrint('ocr: stack $st');
      try {
        final input = _inputFromRaw(prepared);
        return await _runRecognizer(recognizer, input);
      } catch (e2, st2) {
        debugPrint(
          'ocr: fromBytes failed ${e2.runtimeType}: $e2',
        );
        debugPrint('ocr: stack $st2');
        throw OcrException(
          OcrFailKind.process,
          detail: e2.toString(),
          cause: e2,
        );
      }
    }
  }

  Future<String?> _runRecognizer(
    TextRecognizer recognizer,
    InputImage input,
  ) async {
    final result = await recognizer.processImage(input);
    // Prefer element-level boxes so name + value columns stitch like Vision.
    final boxes = <OcrBox>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        if (line.elements.isNotEmpty) {
          for (final el in line.elements) {
            final t = el.text.trim();
            if (t.isEmpty) continue;
            final r = el.boundingBox;
            boxes.add(
              OcrBox(
                text: t,
                left: r.left,
                top: r.top,
                right: r.right,
                bottom: r.bottom,
              ),
            );
          }
        } else {
          final t = line.text.trim();
          if (t.isEmpty) continue;
          final r = line.boundingBox;
          boxes.add(
            OcrBox(
              text: t,
              left: r.left,
              top: r.top,
              right: r.right,
              bottom: r.bottom,
            ),
          );
        }
      }
    }
    String raw;
    if (boxes.isNotEmpty) {
      raw = layoutOcrByGeometry(boxes);
    } else {
      raw = result.text.trim();
    }
    return raw.isEmpty ? null : raw;
  }

  Future<_PreparedImage> _prepareJpeg(
    XFile file, {
    int? maxLongEdge,
    int? jpegQuality,
  }) async {
    late final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      debugPrint('ocr: readAsBytes ${e.runtimeType}: $e');
      throw OcrException(OcrFailKind.empty, detail: e.toString(), cause: e);
    }
    if (bytes.isEmpty) {
      debugPrint('ocr: empty image bytes');
      throw const OcrException(OcrFailKind.empty, detail: 'empty bytes');
    }

    final edge = maxLongEdge ?? _maxLongEdge;
    final quality = jpegQuality ?? _jpegQuality;

    final decoded = await _decodePixels(bytes, hintName: file.name);
    var image = img.bakeOrientation(decoded);
    image = _capLongEdge(image, edge);

    final jpeg = Uint8List.fromList(
      img.encodeJpg(image, quality: quality),
    );
    final dir = await getTemporaryDirectory();
    final name = 'ocr_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final tmp = File('${dir.path}/$name');
    await tmp.writeAsBytes(jpeg, flush: true);
    debugPrint(
      'ocr: prepared jpeg ${image.width}x${image.height} '
      'bytes=${jpeg.length}',
    );
    return _PreparedImage(file: tmp, image: image, jpegBytes: jpeg);
  }

  /// package:image first; Flutter platform codec second (HEIC on capable OS).
  Future<img.Image> _decodePixels(
    Uint8List bytes, {
    required String hintName,
  }) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) return decoded;
    } catch (e) {
      debugPrint('ocr: package:image decode ${e.runtimeType}: $e');
    }

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;
      final w = uiImage.width;
      final h = uiImage.height;
      final bd = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      uiImage.dispose();
      if (bd == null) {
        throw const OcrException(OcrFailKind.decode, detail: 'no rgba');
      }
      return img.Image.fromBytes(
        width: w,
        height: h,
        bytes: bd.buffer,
        bytesOffset: bd.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
    } catch (e) {
      if (e is OcrException) rethrow;
      debugPrint('ocr: flutter codec ${e.runtimeType}: $e');
      final lower = hintName.toLowerCase();
      final heic = lower.endsWith('.heic') ||
          lower.endsWith('.heif') ||
          _looksLikeHeic(bytes);
      throw OcrException(
        OcrFailKind.decode,
        detail: heic ? 'heic/heif' : e.toString(),
        cause: e,
      );
    }
  }

  bool _looksLikeHeic(Uint8List bytes) {
    if (bytes.length < 12) return false;
    // ftyp....heic / heif / mif1
    final box = String.fromCharCodes(bytes.sublist(4, 8));
    if (box != 'ftyp') return false;
    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    return brand.contains('hei') ||
        brand.contains('mif1') ||
        brand.contains('msf1');
  }

  img.Image _capLongEdge(img.Image image, int maxEdge) {
    final long = image.width > image.height ? image.width : image.height;
    if (long <= maxEdge) return image;
    final scale = maxEdge / long;
    final w = (image.width * scale).round().clamp(1, maxEdge);
    final h = (image.height * scale).round().clamp(1, maxEdge);
    return img.copyResize(
      image,
      width: w,
      height: h,
      interpolation: img.Interpolation.linear,
    );
  }

  InputImage _inputFromRaw(_PreparedImage prepared) {
    final image = prepared.image;
    if (Platform.isAndroid) {
      final nv21 = _rgbaToNv21(image);
      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: ui.Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }
    // iOS: BGRA8888
    final bgra = _toBgra(image);
    return InputImage.fromBytes(
      bytes: bgra,
      metadata: InputImageMetadata(
        size: ui.Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.bgra8888,
        bytesPerRow: image.width * 4,
      ),
    );
  }

  Uint8List _toBgra(img.Image image) {
    final out = Uint8List(image.width * image.height * 4);
    var i = 0;
    for (final p in image) {
      out[i++] = p.b.toInt();
      out[i++] = p.g.toInt();
      out[i++] = p.r.toInt();
      out[i++] = p.a.toInt();
    }
    return out;
  }

  /// RGB → NV21 (Y plane + interleaved VU).
  Uint8List _rgbaToNv21(img.Image image) {
    final w = image.width;
    final h = image.height;
    final ySize = w * h;
    final out = Uint8List(ySize + ySize ~/ 2);
    var yi = 0;
    var uvi = ySize;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final Y = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
        out[yi++] = Y.clamp(0, 255);
        if (y % 2 == 0 && x % 2 == 0) {
          final V = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
          final U = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
          out[uvi++] = V.clamp(0, 255);
          if (uvi < out.length) out[uvi++] = U.clamp(0, 255);
        }
      }
    }
    return out;
  }
}

class _PreparedImage {
  _PreparedImage({
    required this.file,
    required this.image,
    required this.jpegBytes,
  });

  final File file;
  final img.Image image;
  final Uint8List jpegBytes;
}
