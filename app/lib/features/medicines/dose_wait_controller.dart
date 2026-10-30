import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../notifications/reminder_notifications.dart';

enum DoseWaitMode { countdown, stopwatch }

class DoseWaitLap {
  DoseWaitLap({
    required this.index,
    required this.lap,
    required this.overall,
  });
  final int index;
  final Duration lap;
  final Duration overall;
}

class _Clock {
  bool running = false;
  DateTime? startedAt;
  DateTime? endsAt;
  String? label;
  Duration? frozenElapsed;
  final List<DoseWaitLap> laps = [];
  Duration lastLapOverall = Duration.zero;

  void reset() {
    running = false;
    startedAt = null;
    endsAt = null;
    label = null;
    frozenElapsed = null;
    laps.clear();
    lastLapOverall = Duration.zero;
  }
}

/// Local countdown and stopwatch. Both can run at once.
class DoseWaitController extends ChangeNotifier {
  DoseWaitController._();
  static final DoseWaitController instance = DoseWaitController._();

  static const _dualFlag = 'dose_wait_dual_v1';
  static const _headerKey = 'dose_wait_header_mode';

  static const _cdRunning = 'dose_wait_cd_running';
  static const _cdStarted = 'dose_wait_cd_started_at_ms';
  static const _cdEnds = 'dose_wait_cd_ends_at_ms';
  static const _cdLabel = 'dose_wait_cd_label';

  static const _swRunning = 'dose_wait_sw_running';
  static const _swStarted = 'dose_wait_sw_started_at_ms';
  static const _swFrozen = 'dose_wait_sw_frozen_ms';
  static const _swLabel = 'dose_wait_sw_label';

  // Legacy single-clock keys (migrated once).
  static const _legacyEndsAt = 'dose_wait_ends_at_ms';
  static const _legacyMode = 'dose_wait_mode';
  static const _legacyLabel = 'dose_wait_label';
  static const _legacyStartedAt = 'dose_wait_started_at_ms';
  static const _legacyRunning = 'dose_wait_running';

  final _Clock _cd = _Clock();
  final _Clock _sw = _Clock();
  DoseWaitMode _header = DoseWaitMode.countdown;
  Ticker? _uiTicker;
  DateTime? _lastPaint;

  /// Clock shown in the shell header.
  DoseWaitMode get mode => _header;
  DoseWaitMode get headerMode => _header;

  bool get countdownRunning => _cd.running;
  bool get stopwatchRunning => _sw.running;
  bool get anyRunning => _cd.running || _sw.running;
  bool get bothRunning => _cd.running && _sw.running;

  /// True when the header clock is running.
  bool get isRunning =>
      _header == DoseWaitMode.countdown ? _cd.running : _sw.running;

  DateTime? get endsAt => _cd.endsAt;
  DateTime? get startedAt =>
      _header == DoseWaitMode.stopwatch ? _sw.startedAt : _cd.startedAt;
  String? get label =>
      _header == DoseWaitMode.stopwatch ? _sw.label : _cd.label;

  Duration? get countdownRemaining {
    if (!_cd.running || _cd.endsAt == null) return null;
    final left = _cd.endsAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Duration? get stopwatchElapsed {
    if (_sw.frozenElapsed != null && !_sw.running) return _sw.frozenElapsed;
    if (!_sw.running || _sw.startedAt == null) return _sw.frozenElapsed;
    return DateTime.now().difference(_sw.startedAt!);
  }

  List<DoseWaitLap> get stopwatchLaps => List.unmodifiable(_sw.laps);

  Duration? get remaining =>
      _header == DoseWaitMode.countdown ? countdownRemaining : null;

  Duration? get elapsed =>
      _header == DoseWaitMode.stopwatch ? stopwatchElapsed : null;

  List<DoseWaitLap> get laps =>
      _header == DoseWaitMode.stopwatch ? stopwatchLaps : const [];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_dualFlag) == true) {
      _loadDual(prefs);
    } else {
      _migrateLegacy(prefs);
      await prefs.setBool(_dualFlag, true);
      await _persist();
    }
    _ensureHeader();
    if (_cd.running &&
        (_cd.endsAt == null || !_cd.endsAt!.isAfter(DateTime.now()))) {
      await _clearCountdown(notifyOs: false, persist: true);
    }
    _syncTick();
    notifyListeners();
  }

  void _loadDual(SharedPreferences prefs) {
    final headerName = prefs.getString(_headerKey) ?? 'countdown';
    _header = headerName == 'stopwatch'
        ? DoseWaitMode.stopwatch
        : DoseWaitMode.countdown;

    _cd.running = prefs.getBool(_cdRunning) ?? false;
    _cd.label = prefs.getString(_cdLabel);
    final cdStarted = prefs.getInt(_cdStarted);
    _cd.startedAt = cdStarted == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(cdStarted);
    final cdEnds = prefs.getInt(_cdEnds);
    _cd.endsAt =
        cdEnds == null ? null : DateTime.fromMillisecondsSinceEpoch(cdEnds);

    _sw.running = prefs.getBool(_swRunning) ?? false;
    _sw.label = prefs.getString(_swLabel);
    final swStarted = prefs.getInt(_swStarted);
    _sw.startedAt = swStarted == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(swStarted);
    final frozen = prefs.getInt(_swFrozen);
    _sw.frozenElapsed = frozen == null ? null : Duration(milliseconds: frozen);
  }

  void _migrateLegacy(SharedPreferences prefs) {
    final running = prefs.getBool(_legacyRunning) ?? false;
    final modeName = prefs.getString(_legacyMode) ?? 'countdown';
    final label = prefs.getString(_legacyLabel);
    final startedMs = prefs.getInt(_legacyStartedAt);
    final endsMs = prefs.getInt(_legacyEndsAt);
    final started = startedMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(startedMs);
    final ends =
        endsMs == null ? null : DateTime.fromMillisecondsSinceEpoch(endsMs);
    if (!running) return;
    if (modeName == 'stopwatch') {
      _sw.running = true;
      _sw.startedAt = started;
      _sw.label = label;
      _header = DoseWaitMode.stopwatch;
    } else if (ends != null && ends.isAfter(DateTime.now())) {
      _cd.running = true;
      _cd.startedAt = started;
      _cd.endsAt = ends;
      _cd.label = label;
      _header = DoseWaitMode.countdown;
    }
  }

  Future<void> startCountdown({
    required Duration duration,
    String? label,
  }) async {
    final now = DateTime.now();
    _cd.startedAt = now;
    _cd.endsAt = now.add(duration);
    _cd.label = label;
    _cd.running = true;
    _header = DoseWaitMode.countdown;
    _syncTick();
    notifyListeners();
    unawaited(_armCountdownAlert());
  }

  Future<void> _armCountdownAlert() async {
    await _persist();
    if (!_cd.running || _cd.endsAt == null) return;
    await ReminderNotifications.instance.ensurePermission();
    if (!_cd.running || _cd.endsAt == null) return;
    await ReminderNotifications.instance.scheduleDoseWait(endsAt: _cd.endsAt!);
  }

  Future<void> startStopwatch({String? label}) async {
    final now = DateTime.now();
    _sw.startedAt = now;
    _sw.endsAt = null;
    _sw.label = label;
    _sw.running = true;
    _sw.laps.clear();
    _sw.lastLapOverall = Duration.zero;
    _sw.frozenElapsed = null;
    _header = DoseWaitMode.stopwatch;
    _syncTick();
    notifyListeners();
    unawaited(_persist());
  }

  void showHeader(DoseWaitMode mode) {
    if (mode == DoseWaitMode.countdown && !_cd.running) return;
    if (mode == DoseWaitMode.stopwatch && !_sw.running) return;
    if (_header == mode) return;
    _header = mode;
    unawaited(_persistHeader());
    notifyListeners();
  }

  void showOtherClock() {
    if (!bothRunning) return;
    showHeader(
      _header == DoseWaitMode.countdown
          ? DoseWaitMode.stopwatch
          : DoseWaitMode.countdown,
    );
  }

  void lap() {
    if (!_sw.running || _sw.startedAt == null) return;
    final overall = DateTime.now().difference(_sw.startedAt!);
    final lapDur = overall - _sw.lastLapOverall;
    _sw.lastLapOverall = overall;
    _sw.laps.insert(
      0,
      DoseWaitLap(
        index: _sw.laps.length + 1,
        lap: lapDur,
        overall: overall,
      ),
    );
    notifyListeners();
  }

  Future<void> stopCountdown() =>
      _clearCountdown(notifyOs: true, persist: true);

  Future<void> stopStopwatch() async {
    if (!_sw.running || _sw.startedAt == null) return;
    _sw.frozenElapsed = DateTime.now().difference(_sw.startedAt!);
    _sw.running = false;
    _ensureHeader();
    _syncTick();
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> resetStopwatch() async {
    _sw.reset();
    _ensureHeader();
    _syncTick();
    notifyListeners();
    unawaited(_persist());
  }

  /// Stops the header clock. Prefer [stopCountdown] / [stopStopwatch].
  Future<void> stop() async {
    if (_header == DoseWaitMode.stopwatch) {
      await stopStopwatch();
    } else {
      await stopCountdown();
    }
  }

  Future<void> clear({required bool notifyOs}) async {
    await _clearCountdown(notifyOs: notifyOs, persist: false);
    _sw.reset();
    _header = DoseWaitMode.countdown;
    _syncTick();
    await _persist();
    notifyListeners();
  }

  Future<void> _clearCountdown({
    required bool notifyOs,
    required bool persist,
  }) async {
    _cd.reset();
    _ensureHeader();
    _syncTick();
    if (persist) notifyListeners();
    if (persist) unawaited(_persist());
    if (notifyOs) {
      unawaited(ReminderNotifications.instance.cancelDoseWait());
    }
  }

  void _ensureHeader() {
    if (_header == DoseWaitMode.countdown && !_cd.running && _sw.running) {
      _header = DoseWaitMode.stopwatch;
    } else if (_header == DoseWaitMode.stopwatch &&
        !_sw.running &&
        _cd.running) {
      _header = DoseWaitMode.countdown;
    }
  }

  Future<void> _persistHeader() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _headerKey,
      _header == DoseWaitMode.stopwatch ? 'stopwatch' : 'countdown',
    );
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dualFlag, true);
    await prefs.setString(
      _headerKey,
      _header == DoseWaitMode.stopwatch ? 'stopwatch' : 'countdown',
    );

    await prefs.setBool(_cdRunning, _cd.running);
    if (_cd.label != null) {
      await prefs.setString(_cdLabel, _cd.label!);
    } else {
      await prefs.remove(_cdLabel);
    }
    if (_cd.startedAt != null) {
      await prefs.setInt(_cdStarted, _cd.startedAt!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_cdStarted);
    }
    if (_cd.endsAt != null) {
      await prefs.setInt(_cdEnds, _cd.endsAt!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_cdEnds);
    }

    await prefs.setBool(_swRunning, _sw.running);
    if (_sw.label != null) {
      await prefs.setString(_swLabel, _sw.label!);
    } else {
      await prefs.remove(_swLabel);
    }
    if (_sw.startedAt != null) {
      await prefs.setInt(_swStarted, _sw.startedAt!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_swStarted);
    }
    if (_sw.frozenElapsed != null) {
      await prefs.setInt(_swFrozen, _sw.frozenElapsed!.inMilliseconds);
    } else {
      await prefs.remove(_swFrozen);
    }

    await prefs.setBool(_legacyRunning, false);
  }

  void _syncTick() {
    final active = _cd.running || _sw.running;
    if (!active) {
      _uiTicker?.stop();
      _lastPaint = null;
      return;
    }
    _uiTicker ??= Ticker(_onUiTick);
    if (!_uiTicker!.isActive) _uiTicker!.start();
  }

  void _safeNotify() {
    if (!hasListeners) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    // Avoid notifying while the tree is locking/unlocking inherited widgets
    // (can trip InheritedElement '_dependents.isEmpty' during route changes).
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) notifyListeners();
    });
  }

  void _onUiTick(Duration _) {
    final now = DateTime.now();
    if (_cd.running && _cd.endsAt != null && !now.isBefore(_cd.endsAt!)) {
      unawaited(_clearCountdown(notifyOs: false, persist: true));
      return;
    }
    // A plain Timer does not paint while this screen is idle. The ticker
    // asks for frames; the gap keeps the readout cheap.
    final gap = _sw.running ? 80 : 200;
    if (_lastPaint != null &&
        now.difference(_lastPaint!).inMilliseconds < gap) {
      return;
    }
    _lastPaint = now;
    _safeNotify();
  }

  static String formatDuration(Duration d) {
    final total = d.inSeconds.clamp(0, 99 * 3600);
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  static String formatStopwatch(Duration d) {
    final totalMs = d.inMilliseconds.clamp(0, 99 * 3600 * 1000);
    final m = totalMs ~/ 60000;
    final s = (totalMs % 60000) ~/ 1000;
    final c = (totalMs % 1000) ~/ 10;
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}.'
        '${c.toString().padLeft(2, '0')}';
  }
}
