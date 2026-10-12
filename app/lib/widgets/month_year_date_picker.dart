import 'package:flutter/material.dart';

/// Shared date picker that opens on **year** so month/year are one tap away
/// (then day). Use everywhere instead of bare [showDatePicker].
Future<DateTime?> pickBodylineDate(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String? helpText,
  bool startAtYear = true,
}) {
  final first = firstDate ?? DateTime(1900);
  final last = lastDate ?? DateTime.now().add(const Duration(days: 365 * 5));
  var initial = initialDate;
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
    helpText: helpText,
    initialDatePickerMode:
        startAtYear ? DatePickerMode.year : DatePickerMode.day,
  );
}
