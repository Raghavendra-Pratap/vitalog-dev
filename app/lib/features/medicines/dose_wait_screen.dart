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
  bool _running = false;
  late final ValueNotifier<String> _readout;
  late final FixedExtentScrollController _hoursCtrl;
  late final FixedExtentScrollController _minutesCtrl;
  late final FixedExtentScrollController _secondsCtrl;

  @override
  void initState() {
    super.initState();
    final wait = DoseWaitController.instance;
    _running = wait.countdownRunning;
    _readout = ValueNotifier(
      _running
          ? DoseWaitController.formatDuration(
              wait.countdownRemaining ?? Duration.zero)
          : _fmtHms(_hours, _minutes, _seconds),
    );
    _hoursCtrl = FixedExtentScrollController(initialItem: _hours);
    _minutesCtrl = FixedExtentScrollController(initialItem: _minutes);
    _secondsCtrl = FixedExtentScrollController(initialItem: _seconds);
    DoseWaitController.instance.addListener(_tick);
  }

  @override
  void dispose() {
    DoseWaitController.instance.removeListener(_tick);
    _readout.dispose();
    _hoursCtrl.dispose();
    _minutesCtrl.dispose();
    _secondsCtrl.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final wait = DoseWaitController.instance;
    final running = wait.countdownRunning;
    if (running) {
      _readout.value = DoseWaitController.formatDuration(
        wait.countdownRemaining ?? Duration.zero,
      );
    }
    if (running != _running) {
      _running = running;
      setState(() {});
    }
  }

  void _paintDuration() {
    if (_running) return;
    _readout.value = _fmtHms(_hours, _minutes, _seconds);
  }

  void _applyPreset(int minutes) {
    _hours = 0;
    _minutes = minutes;
    _seconds = 0;
    _paintDuration();
    _hoursCtrl.jumpToItem(0);
    _minutesCtrl.jumpToItem(minutes);
    _secondsCtrl.jumpToItem(0);
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
    final running = wait.countdownRunning;

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
        ValueListenableBuilder<String>(
          valueListenable: _readout,
          builder: (context, time, _) => Text(
            time,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
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
                child: _scrollWheel(
                  label: 'Hours',
                  max: 23,
                  controller: _hoursCtrl,
                  onChanged: (v) {
                    _hours = v;
                    _paintDuration();
                  },
                ),
              ),
              Expanded(
                child: _scrollWheel(
                  label: 'Minutes',
                  max: 59,
                  controller: _minutesCtrl,
                  onChanged: (v) {
                    _minutes = v;
                    _paintDuration();
                  },
                ),
              ),
              Expanded(
                child: _scrollWheel(
                  label: 'Seconds',
                  max: 59,
                  controller: _secondsCtrl,
                  onChanged: (v) {
                    _seconds = v;
                    _paintDuration();
                  },
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
                  onPressed: () => _applyPreset(m),
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
              onPressed: () => DoseWaitController.instance.stopCountdown(),
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

  Widget _scrollWheel({
    required String label,
    required int max,
    required FixedExtentScrollController controller,
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
        SizedBox(
          height: 120,
          child: ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: 36,
            diameterRatio: 1.35,
            perspective: 0.003,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: max + 1,
              builder: (context, index) {
                return Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: BodylineColors.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                );
              },
            ),
          ),
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
  late bool _running;
  late int _laps;
  late final ValueNotifier<String> _readout;

  @override
  void initState() {
    super.initState();
    final wait = DoseWaitController.instance;
    _running = wait.stopwatchRunning;
    _laps = wait.stopwatchLaps.length;
    final elapsed = wait.stopwatchElapsed;
    _readout = ValueNotifier(
      elapsed != null
          ? DoseWaitController.formatStopwatch(elapsed)
          : '00:00.00',
    );
    DoseWaitController.instance.addListener(_tick);
  }

  @override
  void dispose() {
    DoseWaitController.instance.removeListener(_tick);
    _readout.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final wait = DoseWaitController.instance;
    final running = wait.stopwatchRunning;
    final laps = wait.stopwatchLaps.length;
    final elapsed = wait.stopwatchElapsed;
    _readout.value = elapsed != null
        ? DoseWaitController.formatStopwatch(elapsed)
        : '00:00.00';
    if (running != _running || laps != _laps) {
      _running = running;
      _laps = laps;
      setState(() {});
    }
  }

  Future<void> _start() async {
    await DoseWaitController.instance.startStopwatch();
  }

  @override
  Widget build(BuildContext context) {
    final wait = DoseWaitController.instance;
    final running = wait.stopwatchRunning;
    final hasLaps = wait.stopwatchLaps.isNotEmpty;

    final readout = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<String>(
          valueListenable: _readout,
          builder: (context, time, _) => Text(
            time,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          running ? 'Running' : (hasLaps ? 'Stopped' : 'Ready'),
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
            onPressed: () => DoseWaitController.instance.stopStopwatch(),
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
              itemCount: wait.stopwatchLaps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final lap = wait.stopwatchLaps[i];
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
