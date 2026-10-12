import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'dose_wait_controller.dart';

/// Full-page timer or stopwatch (home / Reminders shortcuts).
class DoseWaitScreen extends StatelessWidget {
  const DoseWaitScreen({
    super.key,
    this.mode = DoseWaitMode.countdown,
  });

  final DoseWaitMode mode;

  @override
  Widget build(BuildContext context) {
    final isTimer = mode == DoseWaitMode.countdown;
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(title: Text(isTimer ? 'Timer' : 'Stopwatch')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: isTimer
            ? const DoseTimerView(showTitle: false)
            : const DoseStopwatchView(showTitle: false),
      ),
    );
  }
}

/// Countdown timer — same UI as Reminders desktop detail.
class DoseTimerView extends StatefulWidget {
  const DoseTimerView({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  State<DoseTimerView> createState() => _DoseTimerViewState();
}

class _DoseTimerViewState extends State<DoseTimerView> {
  int _hours = 0;
  int _minutes = 30;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    DoseWaitController.instance.addListener(_tick);
  }

  @override
  void dispose() {
    DoseWaitController.instance.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final d = Duration(hours: _hours, minutes: _minutes, seconds: _seconds);
    if (d.inSeconds <= 0) return;
    await DoseWaitController.instance.startCountdown(duration: d);
  }

  String _fmtHms(int h, int m, int s) =>
      '${h.toString().padLeft(2, '0')} : ${m.toString().padLeft(2, '0')} : ${s.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final wait = DoseWaitController.instance;
    final running =
        wait.isRunning && wait.mode == DoseWaitMode.countdown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle) ...[
          Text(
            'Timer',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Countdown after a dose. Alert stays on this device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],
        const Spacer(),
        Text(
          running
              ? DoseWaitController.formatDuration(
                  wait.remaining ?? Duration.zero)
              : _fmtHms(_hours, _minutes, _seconds),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          running ? 'Countdown running' : 'Set a duration, then Start',
          textAlign: TextAlign.center,
          style: TextStyle(color: BodylineColors.inkSubtle),
        ),
        const SizedBox(height: 24),
        if (!running) ...[
          Row(
            children: [
              Expanded(
                child: _stepper(
                  label: 'Hours',
                  value: _hours,
                  max: 23,
                  onChanged: (v) => setState(() => _hours = v),
                ),
              ),
              Expanded(
                child: _stepper(
                  label: 'Minutes',
                  value: _minutes,
                  max: 59,
                  onChanged: (v) => setState(() => _minutes = v),
                ),
              ),
              Expanded(
                child: _stepper(
                  label: 'Seconds',
                  value: _seconds,
                  max: 59,
                  onChanged: (v) => setState(() => _seconds = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final m in [10, 15, 30])
                OutlinedButton(
                  onPressed: () => setState(() {
                    _hours = 0;
                    _minutes = m;
                    _seconds = 0;
                  }),
                  child: Text('00:${m.toString().padLeft(2, '0')}:00'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: FilledButton(
              onPressed: _start,
              style: FilledButton.styleFrom(
                backgroundColor: BodylineColors.teal,
                foregroundColor: BodylineColors.isDark
                    ? const Color(0xFF04201C)
                    : Colors.white,
                minimumSize: const Size(140, 48),
                shape: const StadiumBorder(),
              ),
              child: const Text('Start'),
            ),
          ),
        ] else
          Center(
            child: FilledButton(
              onPressed: () => DoseWaitController.instance.stop(),
              style: FilledButton.styleFrom(
                backgroundColor: BodylineColors.ink,
                foregroundColor: BodylineColors.onInk,
                minimumSize: const Size(140, 48),
                shape: const StadiumBorder(),
              ),
              child: const Text('Stop'),
            ),
          ),
        const Spacer(),
      ],
    );
  }

  Widget _stepper({
    required String label,
    required int value,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: BodylineColors.inkSubtle,
          ),
        ),
        const SizedBox(height: 6),
        IconButton(
          onPressed: () => onChanged(value >= max ? 0 : value + 1),
          icon: const Icon(Icons.keyboard_arrow_up),
        ),
        Text(
          value.toString().padLeft(2, '0'),
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        IconButton(
          onPressed: () => onChanged(value <= 0 ? max : value - 1),
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
      ],
    );
  }
}

/// Stopwatch — same controls as Reminders; compact full-page layout.
class DoseStopwatchView extends StatefulWidget {
  const DoseStopwatchView({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  State<DoseStopwatchView> createState() => _DoseStopwatchViewState();
}

class _DoseStopwatchViewState extends State<DoseStopwatchView> {
  @override
  void initState() {
    super.initState();
    DoseWaitController.instance.addListener(_tick);
  }

  @override
  void dispose() {
    DoseWaitController.instance.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    await DoseWaitController.instance.startStopwatch();
  }

  @override
  Widget build(BuildContext context) {
    final wait = DoseWaitController.instance;
    final running =
        wait.isRunning && wait.mode == DoseWaitMode.stopwatch;
    final hasLaps = wait.laps.isNotEmpty;

    final readout = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          wait.elapsed != null
              ? DoseWaitController.formatStopwatch(wait.elapsed!)
              : '00:00.00',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          running
              ? 'Running'
              : (hasLaps ? 'Stopped' : 'Ready'),
          textAlign: TextAlign.center,
          style: TextStyle(color: BodylineColors.inkSubtle),
        ),
      ],
    );

    final controls = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (running) ...[
          OutlinedButton(
            onPressed: () => DoseWaitController.instance.lap(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(100, 48),
              shape: const CircleBorder(),
              fixedSize: const Size(88, 88),
            ),
            child: const Text('Lap'),
          ),
          const SizedBox(width: 16),
          FilledButton(
            onPressed: () => DoseWaitController.instance.stop(),
            style: FilledButton.styleFrom(
              backgroundColor: BodylineColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(100, 48),
              shape: const CircleBorder(),
              fixedSize: const Size(88, 88),
            ),
            child: const Text('Stop'),
          ),
        ] else ...[
          if (hasLaps) ...[
            OutlinedButton(
              onPressed: () => DoseWaitController.instance.resetStopwatch(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(100, 48),
              ),
              child: const Text('Reset'),
            ),
            const SizedBox(width: 12),
          ],
          FilledButton(
            onPressed: _start,
            style: FilledButton.styleFrom(
              backgroundColor: BodylineColors.teal,
              foregroundColor: BodylineColors.isDark
                  ? const Color(0xFF04201C)
                  : Colors.white,
              minimumSize: const Size(140, 48),
              shape: const StadiumBorder(),
            ),
            child: Text(hasLaps ? 'Start again' : 'Start'),
          ),
        ],
      ],
    );

    final lapsHeader = Row(
      children: [
        Expanded(
          child: Text(
            'Lap',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: BodylineColors.inkSubtle,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            'Lap time',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: BodylineColors.inkSubtle,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            'Overall',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: BodylineColors.inkSubtle,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle) ...[
          Text(
            'Stopwatch',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Track elapsed time on this device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (hasLaps) ...[
          const SizedBox(height: 20),
          readout,
          const SizedBox(height: 20),
          lapsHeader,
          const Divider(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: wait.laps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final lap = wait.laps[i];
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        lap.index.toString().padLeft(2, '0'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        DoseWaitController.formatStopwatch(lap.lap),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        DoseWaitController.formatStopwatch(lap.overall),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          controls,
        ] else
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  readout,
                  const SizedBox(height: 28),
                  controls,
                ],
              ),
            ),
          ),
      ],
    );
  }
}
