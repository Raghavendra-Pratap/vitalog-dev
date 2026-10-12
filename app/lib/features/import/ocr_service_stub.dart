import 'package:image_picker/image_picker.dart';

import 'ocr_exception.dart';

class OcrService {
  OcrService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  bool get isSupported => false;

  bool get supportsCamera => false;

  Future<XFile?> pickImage({required ImageSource source}) =>
      _picker.pickImage(source: source, imageQuality: 92);

  Future<String?> recognizeFile(String path) async =>
      throw const OcrException(OcrFailKind.unsupported);

  Future<String?> recognizeXFile(XFile file) async =>
      throw const OcrException(OcrFailKind.unsupported);
}
