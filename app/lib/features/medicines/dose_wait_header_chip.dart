import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'dose_wait_controller.dart';
import 'dose_wait_screen.dart';

Widget _maybeTooltip({
  required BuildContext context,
  required String message,
  required Widget child,
}) {
  if (Overlay.maybeOf(context) == null) {
    return Semantics(label: message, button: true, child: child);
  }
  return Tooltip(message: message, child: child);
}

/// Compact running timer/stopwatch control for headers.
/// Tap opens the clock. When both run, swap switches which one is shown.
class DoseWaitHeaderChip extends StatefulWidget {
  const DoseWaitHeaderChip({
    super.key,
    this.onOpen,
    this.safeTop = false,
    /// Icon + time only (no "Timer"/"Stopwatch" word) on phone headers.
    this.compact = true,
  });

  final VoidCallback? onOpen;
  final bool safeTop;
  final bool compact;

  static void openClock(BuildContext context) {
    final mode = DoseWaitController.instance.mode;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DoseWaitScreen(mode: mode),
      ),
    );
  }

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
    final onOpen = widget.onOpen ?? () => DoseWaitHeaderChip.openClock(context);
    final showLabel = !widget.compact;

    // DecoratedBox + GestureDetector: avoid Material/Theme inherited deps so
    // stopwatch ticks during route pops do not trip InheritedElement asserts.
    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: BodylineColors.selectedWash,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _maybeTooltip(
            context: context,
            message: label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: Padding(
                padding:
                    EdgeInsets.fromLTRB(10, 8, wait.bothRunning ? 4 : 10, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isTimer ? Icons.hourglass_bottom : Icons.timer_outlined,
                      size: 16,
                      color: BodylineColors.teal,
                    ),
                    if (showLabel) ...[
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: BodylineColors.inkSubtle,
                        ),
                      ),
                    ],
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
          ),
          if (wait.bothRunning)
            _maybeTooltip(
              context: context,
              message: other,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: wait.showOtherClock,
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

    if (!widget.safeTop) return chip;

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

/// [AppBar.actions]: page icons first, then the running clock (grouped on the right).
List<Widget> doseWaitActions([List<Widget> extra = const <Widget>[]]) => [
      ...extra,
      const DoseWaitHeaderChip(),
    ];

/// Tab-root title row — trailing actions sit immediately left of the clock.
class TabPageHeader extends StatelessWidget {
  const TabPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            ...trailing,
            const DoseWaitHeaderChip(),
          ],
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
