import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.flag, this.compact = true});

  final ObservationFlag flag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    switch (flag) {
      case ObservationFlag.normal:
        bg = BodylineColors.tealTint;
        fg = BodylineColors.tealDark;
      case ObservationFlag.high:
      case ObservationFlag.criticalHigh:
      case ObservationFlag.abnormal:
        bg = BodylineColors.orangeTint;
        fg = BodylineColors.orangeText;
      case ObservationFlag.low:
      case ObservationFlag.criticalLow:
        bg = BodylineColors.blueTint;
        fg = BodylineColors.blueText;
    }
    final label = compact
        ? switch (flag) {
            ObservationFlag.normal => 'In range',
            ObservationFlag.high || ObservationFlag.criticalHigh => 'High',
            ObservationFlag.low || ObservationFlag.criticalLow => 'Low',
            ObservationFlag.abnormal => 'Out',
          }
        : flagLabel(flag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(BodylineRadii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
      ),
    );
  }
}
