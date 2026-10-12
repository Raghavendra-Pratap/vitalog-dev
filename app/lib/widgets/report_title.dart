import 'package:flutter/material.dart';

/// Soften PDF filenames (strip trailing UUID, tidy separators) for UI display.
String displayReportTitle(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return 'Untitled report';
  t = t.replaceFirst(
    RegExp(
      r'[-_\s]*[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\s*$',
    ),
    '',
  );
  t = t.replaceAll(RegExp(r'[_\s]+'), ' ').trim();
  return t.isEmpty ? raw.trim() : t;
}

/// Title that never blows out layout: capped lines + ellipsis.
class ReportTitleText extends StatelessWidget {
  const ReportTitleText(
    this.title, {
    super.key,
    this.style,
    this.maxLines = 2,
    this.textAlign,
  });

  final String title;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      displayReportTitle(title),
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      softWrap: true,
      textAlign: textAlign,
    );
  }
}
