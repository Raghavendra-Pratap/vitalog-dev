import 'dart:async';

import 'package:flutter/foundation.dart';
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


/// Thin post-dose wait timer — local countdown / stopwatch, no drug DB.
class DoseWaitController extends ChangeNotifier {
  DoseWaitController._();
  static final DoseWaitController instance = DoseWaitController._();

  static const _prefsEndsAt = 'dose_wait_ends_at_ms';
  static const _prefsMode = 'dose_wait_mode';
  static const _prefsLabel = 'dose_wait_label';
  static const _prefsStartedAt = 'dose_wait_started_at_ms';
  static const _prefsRunning = 'dose_wait_running';

  DoseWaitMode _mode = DoseWaitMode.countdown;
  DateTime? _endsAt;
  DateTime? _startedAt;
  String? _label;
  bool _running = false;
  Timer? _tick;
  final List<DoseWaitLap> _laps = [];
  Duration _lastLapOverall = Duration.zero;
  Duration? _frozenElapsed;

  DoseWaitMode get mode => _mode;
  DateTime? get endsAt => _endsAt;
  DateTime? get startedAt => _startedAt;
  String? get label => _label;
  bool get isRunning => _running;
  List<DoseWaitLap> get laps => List.unmodifiable(_laps);

  Duration? get remaining {
    if (!_running || _mode != DoseWaitMode.countdown || _endsAt == null) {
      return null;
    }
    final left = _endsAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Duration? get elapsed {
    if (_frozenElapsed != null) return _frozenElapsed;
    if (!_running || _startedAt == null) return null;
    return DateTime.now().difference(_startedAt!);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final running = prefs.getBool(_prefsRunning) ?? false;
    if (!running) {
      _running = false;
      notifyListeners();
      return;
    }
    final modeName = prefs.getString(_prefsMode) ?? 'countdown';
    _mode = modeName == 'stopwatch' ? DoseWaitMode.stopwatch : DoseWaitMode.countdown;
    _label = prefs.getString(_prefsLabel);
    final startedMs = prefs.getInt(_prefsStartedAt);
    _startedAt =
        startedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(startedMs);
    final endsMs = prefs.getInt(_prefsEndsAt);
    _endsAt = endsMs == null ? null : DateTime.fromMillisecondsSinceEpoch(endsMs);

    if (_mode == DoseWaitMode.countdown) {
      if (_endsAt == null || !_endsAt!.isAfter(DateTime.now())) {
        await clear(notifyOs: false);
        return;
      }
    }
    _running = true;
    _startTick();
    notifyListeners();
  }

  Future<void> startCountdown({
    required Duration duration,
    String? label,
  }) async {
    final now = DateTime.now();
    _mode = DoseWaitMode.countdown;
    _startedAt = now;
    _endsAt = now.add(duration);
    _label = label;
    _running = true;
    await _persist();
    await ReminderNotifications.instance.ensurePermission();
    await ReminderNotifications.instance.scheduleDoseWait(endsAt: _endsAt!);
    _startTick();
    notifyListeners();
  }

  Future<void> startStopwatch({String? label}) async {
    final now = DateTime.now();
    _mode = DoseWaitMode.stopwatch;
    _startedAt = now;
    _endsAt = null;
    _label = label;
    _running = true;
    _laps.clear();
    _lastLapOverall = Duration.zero;
    _frozenElapsed = null;
    await ReminderNotifications.instance.cancelDoseWait();
    await _persist();
    _startTick();
    notifyListeners();
  }

  void lap() {
    if (!_running || _mode != DoseWaitMode.stopwatch || _startedAt == null) {
      return;
    }
    final overall = DateTime.now().difference(_startedAt!);
    final lapDur = overall - _lastLapOverall;
    _lastLapOverall = overall;
    _laps.insert(
      0,
      DoseWaitLap(
        index: _laps.length + 1,
        lap: lapDur,
        overall: overall,
      ),
    );
    notifyListeners();
  }

  Future<void> stop() async {
    if (_mode == DoseWaitMode.stopwatch && _running && _startedAt != null) {
      _frozenElapsed = DateTime.now().difference(_startedAt!);
      _running = false;
      _tick?.cancel();
      _tick = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsRunning, false);
      notifyListeners();
      return;
    }
    await clear(notifyOs: true);
  }

  Future<void> resetStopwatch() async {
    await clear(notifyOs: false);
  }

  Future<void> clear({required bool notifyOs}) async {
    _tick?.cancel();
    _tick = null;
    _running = false;
    _endsAt = null;
    _startedAt = null;
    _label = null;
    _laps.clear();
    _lastLapOverall = Duration.zero;
    _frozenElapsed = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsEndsAt);
    await prefs.remove(_prefsMode);
    await prefs.remove(_prefsLabel);
    await prefs.remove(_prefsStartedAt);
    await prefs.setBool(_prefsRunning, false);
    if (notifyOs) {
      await ReminderNotifications.instance.cancelDoseWait();
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsRunning, _running);
    await prefs.setString(
      _prefsMode,
      _mode == DoseWaitMode.stopwatch ? 'stopwatch' : 'countdown',
    );
    if (_label != null) {
      await prefs.setString(_prefsLabel, _label!);
    } else {
      await prefs.remove(_prefsLabel);
    }
    if (_startedAt != null) {
      await prefs.setInt(_prefsStartedAt, _startedAt!.millisecondsSinceEpoch);
    }
    if (_endsAt != null) {
      await prefs.setInt(_prefsEndsAt, _endsAt!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_prefsEndsAt);
    }
  }

  void _startTick() {
    _tick?.cancel();
    final period = _mode == DoseWaitMode.stopwatch
        ? const Duration(milliseconds: 50)
        : const Duration(seconds: 1);
    _tick = Timer.periodic(period, (_) async {
      if (_mode == DoseWaitMode.countdown &&
          _endsAt != null &&
          !DateTime.now().isBefore(_endsAt!)) {
        await clear(notifyOs: false);
        return;
      }
      notifyListeners();
    });
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

  /// Stopwatch display with centiseconds: MM:SS.cc
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
