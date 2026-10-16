import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'dose_wait_controller.dart';

/// Compact running timer/stopwatch control for shell headers.
/// Tap opens the clock shown here. When both run, the swap control
/// switches which one the header shows.
class DoseWaitHeaderChip extends StatefulWidget {
  const DoseWaitHeaderChip({
    super.key,
    required this.onOpen,
    this.safeTop = false,
  });

  final VoidCallback onOpen;

  /// When true, applies top safe-area padding only while the chip is visible.
  final bool safeTop;

  @override
  State<DoseWaitHeaderChip> createState() => _DoseWaitHeaderChipState();
}

class _DoseWaitHeaderChipState extends State<DoseWaitHeaderChip> {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: DoseWaitController.instance,
        builder: (context, _) => _buildChip(context),
      ),
    );
  }

  Widget _buildChip(BuildContext context) {
    final wait = DoseWaitController.instance;
    if (!wait.anyRunning) return const SizedBox.shrink();

    final isTimer = wait.headerMode == DoseWaitMode.countdown;
    final time = isTimer
        ? DoseWaitController.formatDuration(
            wait.countdownRemaining ?? Duration.zero)
        : DoseWaitController.formatStopwatch(
            wait.stopwatchElapsed ?? Duration.zero);
    final label = isTimer ? 'Timer' : 'Stopwatch';
    final other = isTimer ? 'Show stopwatch' : 'Show timer';

    final chip = Material(
      color: BodylineColors.selectedWash,
      borderRadius: BorderRadius.circular(999),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: widget.onOpen,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 8, wait.bothRunning ? 4 : 12, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isTimer ? Icons.hourglass_bottom : Icons.timer_outlined,
                    size: 16,
                    color: BodylineColors.teal,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: BodylineColors.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (wait.bothRunning)
            Tooltip(
              message: other,
              child: InkWell(
                onTap: wait.showOtherClock,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
                  child: Icon(
                    Icons.swap_horiz,
                    size: 18,
                    color: BodylineColors.teal,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (!widget.safeTop) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: chip,
      );
    }

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: chip,
        ),
      ),
    );
  }
}
