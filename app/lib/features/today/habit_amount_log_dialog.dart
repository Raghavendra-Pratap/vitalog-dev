import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../../widgets/bodyline_dialog.dart';

/// Unit suffix for count/duration habits (e.g. " steps", " min").
String habitAmountUnitSuffix({
  required String kind,
  String? unitLabel,
}) {
  final u = unitLabel?.trim();
  if (u != null && u.isNotEmpty) return ' $u';
  if (kind == 'duration') return ' min';
  return '';
}

String _fmtAmount(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Confirm clearing today's habit log. Returns true only if the user confirms.
Future<bool> confirmClearHabitLog({
  required BuildContext context,
  required String habitTitle,
}) async {
  final ok = await showBodylineDialog<bool>(
    context: context,
    title: 'Clear today’s log?',
    subtitle: habitTitle,
    showLockup: false,
    maxWidth: 320,
    content: Text(
      'This removes what you logged for today. You can log again afterwards.',
      style: Theme.of(context).textTheme.bodyMedium,
    ),
    actionsBuilder: (ctx) => [
      TextButton(
        onPressed: () => Navigator.pop(ctx, false),
        style: TextButton.styleFrom(foregroundColor: BodylineColors.tealDark),
        child: const Text('Keep', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(ctx, true),
        style: FilledButton.styleFrom(
          backgroundColor: BodylineColors.danger,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),
        child: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    ],
  );
  return ok == true;
}

/// Ask for today's amount. When [currentValue] is set, offers **Add** (sum) and
/// **Set total** so a second walk can be logged without wiping the first.
Future<double?> showHabitAmountLogDialog({
  required BuildContext context,
  required String habitTitle,
  required String kind,
  String? unitLabel,
  double? goalValue,
  double? currentValue,
}) {
  final unit = habitAmountUnitSuffix(kind: kind, unitLabel: unitLabel).trim();
  final hasCurrent = currentValue != null && currentValue > 0;
  final ctrl = TextEditingController();

  String? subtitle;
  final parts = <String>[];
  if (goalValue != null && goalValue > 0) {
    final g = _fmtAmount(goalValue);
    parts.add(unit.isEmpty ? 'Goal: $g' : 'Goal: $g $unit');
  }
  if (hasCurrent) {
    final c = _fmtAmount(currentValue!);
    parts.add(unit.isEmpty ? 'Logged so far: $c' : 'Logged so far: $c $unit');
  }
  if (parts.isNotEmpty) subtitle = parts.join(' · ');

  final fieldLabel = hasCurrent
      ? (unit.isEmpty ? 'Amount' : 'Amount ($unit)')
      : (unit.isEmpty ? "Today's total" : "Today's total ($unit)");

  return showBodylineDialog<double>(
    context: context,
    title: habitTitle,
    subtitle: subtitle,
    showLockup: false,
    maxWidth: 320,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            labelText: fieldLabel,
            hintText: hasCurrent
                ? (kind == 'duration' ? 'e.g. 20 more' : 'e.g. 3000 more')
                : (kind == 'duration' ? 'e.g. 45' : 'e.g. 8000'),
            helperText: hasCurrent
                ? 'Add to today’s total, or set a new total.'
                : null,
          ),
        ),
      ],
    ),
    actionsBuilder: (ctx) {
      double? parsed() {
        final v = double.tryParse(ctrl.text.trim());
        if (v == null || v < 0) return null;
        return v;
      }

      return [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          style: TextButton.styleFrom(foregroundColor: BodylineColors.tealDark),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (hasCurrent)
          TextButton(
            onPressed: () {
              final v = parsed();
              if (v == null) return;
              Navigator.pop(ctx, currentValue! + v);
            },
            style: TextButton.styleFrom(foregroundColor: BodylineColors.tealDark),
            child: const Text(
              'Add',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        FilledButton(
          onPressed: () {
            final v = parsed();
            if (v == null) return;
            Navigator.pop(ctx, v);
          },
          style: FilledButton.styleFrom(
            backgroundColor: BodylineColors.ink,
            foregroundColor: BodylineColors.onInk,
            shape: const StadiumBorder(),
          ),
          child: Text(
            hasCurrent ? 'Set total' : 'Save',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ];
    },
  ).whenComplete(ctrl.dispose);
}
