/// Positioned word from PDF text layer or OCR (spec §4.3).
class WordBox {
  const WordBox({
    required this.text,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.conf = 100,
    this.page = 1,
    this.source = WordBoxSource.ocr,
    this.font,
  });

  final String text;
  /// Page coordinates, origin top-left.
  final double x;
  final double y;
  final double w;
  final double h;
  final int conf;
  final int page;
  final WordBoxSource source;
  final String? font;

  double get midX => x + w / 2;
  double get midY => y + h / 2;
  double get right => x + w;
  double get bottom => y + h;
  double get height => h < 1 ? 1 : h;

  factory WordBox.fromJson(Map<String, dynamic> json) {
    final src = json['source']?.toString();
    return WordBox(
      text: (json['text'] ?? '').toString(),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      w: (json['w'] as num).toDouble(),
      h: (json['h'] as num).toDouble(),
      conf: (json['conf'] as num?)?.toInt() ?? 100,
      page: (json['page'] as num?)?.toInt() ?? 1,
      source: src == 'textLayer' || src == 'text_layer'
          ? WordBoxSource.textLayer
          : WordBoxSource.ocr,
      font: json['font']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'conf': conf,
        'page': page,
        'source': source == WordBoxSource.textLayer ? 'textLayer' : 'ocr',
        if (font != null) 'font': font,
      };
}

enum WordBoxSource { textLayer, ocr }
