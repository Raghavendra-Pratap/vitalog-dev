/// Typed OCR failures so UI can show decode vs process vs unsupported.
enum OcrFailKind {
  /// Empty or unreadable picker bytes.
  empty,
  /// Could not decode pixels (often HEIC / exotic formats).
  decode,
  /// ML Kit / platform OCR threw while processing a valid image.
  process,
  /// This OS cannot OCR yet (honest stub).
  unsupported,
}

class OcrException implements Exception {
  const OcrException(this.kind, {this.detail, this.cause});

  final OcrFailKind kind;
  final String? detail;
  final Object? cause;

  String get userMessage {
    switch (kind) {
      case OcrFailKind.empty:
      case OcrFailKind.decode:
        return "Couldn't decode this format — try JPG/PNG or paste text.";
      case OcrFailKind.process:
        return 'Could not read that image. Paste the text instead.';
      case OcrFailKind.unsupported:
        return detail ??
            'Image OCR is not available on this device. Paste the report text instead.';
    }
  }

  @override
  String toString() =>
      'OcrException($kind${detail != null ? ', $detail' : ''})';
}
