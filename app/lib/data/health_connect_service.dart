import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_store.dart';
import 'models.dart';

/// Opt-in bridge to Google Health Connect (Android) / Apple HealthKit (iOS).
///
/// Scope (ADR-011 / 011a): weight, glucose, BP, steps, sleep duration —
/// read + manual edit + optional write. Sleep stages out of scope.
/// Data never leaves the device except into the OS health store the user chose.
class HealthConnectService {
  HealthConnectService();

  static const _prefEnabled = 'hc_enabled';
  static const _prefWrite = 'hc_write_enabled';
  static const _prefLastSync = 'hc_last_sync_ms';

  final Health _health = Health();
  bool _configured = false;

  static const types = <HealthDataType>[
    HealthDataType.WEIGHT,
    HealthDataType.BLOOD_GLUCOSE,
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    HealthDataType.STEPS,
    HealthDataType.SLEEP_ASLEEP,
  ];

  static const permissions = <HealthDataAccess>[
    HealthDataAccess.READ_WRITE,
    HealthDataAccess.READ_WRITE,
    HealthDataAccess.READ_WRITE,
    HealthDataAccess.READ_WRITE,
    HealthDataAccess.READ_WRITE,
    HealthDataAccess.READ_WRITE,
  ];

  bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  String get platformLabel {
    if (!isSupported) return 'Not available on this device';
    if (Platform.isAndroid) return 'Health Connect';
    if (Platform.isIOS) return 'Apple Health';
    return 'Health store';
  }

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? false;
  }

  Future<bool> isWriteEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefWrite) ?? false;
  }

  Future<DateTime?> lastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_prefLastSync);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, v);
  }

  Future<void> setWriteEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefWrite, v);
  }

  Future<void> _touchLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefLastSync, DateTime.now().millisecondsSinceEpoch);
  }

  /// Availability for UI: unsupported | missing | ready.
  Future<HealthBridgeStatus> status() async {
    if (!isSupported) return HealthBridgeStatus.unsupported;
    await _ensureConfigured();
    if (Platform.isAndroid) {
      final available = await _health.isHealthConnectAvailable();
      if (!available) return HealthBridgeStatus.missingApp;
    }
    final enabled = await isEnabled();
    if (!enabled) return HealthBridgeStatus.ready;
    final granted = await _health.hasPermissions(types, permissions: permissions);
    if (granted == true) return HealthBridgeStatus.connected;
    return HealthBridgeStatus.needsAuth;
  }

  Future<void> openInstallPage() async {
    if (!Platform.isAndroid) return;
    await _ensureConfigured();
    await _health.installHealthConnect();
  }

  /// Request OS permissions and mark bridge enabled.
  Future<bool> connect() async {
    if (!isSupported) return false;
    await _ensureConfigured();
    if (Platform.isAndroid) {
      final available = await _health.isHealthConnectAvailable();
      if (!available) {
        throw StateError(
          'Install Health Connect from Play Store, then try again.',
        );
      }
    }
    final ok = await _health.requestAuthorization(
      types,
      permissions: permissions,
    );
    if (!ok) {
      throw StateError(
        'Permission was not granted. You can change this in system settings.',
      );
    }
    if (Platform.isAndroid) {
      try {
        await _health.requestHealthDataHistoryAuthorization();
      } catch (_) {
        // Optional; 30-day default still works.
      }
    }
    await _setEnabled(true);
    await setWriteEnabled(true);
    return true;
  }

  Future<void> disconnect() async {
    await _setEnabled(false);
    await setWriteEnabled(false);
  }

  /// Pull recent vitals into [store] for [profileId]. Returns counts.
  Future<HealthImportResult> importRecent({
    required LocalStore store,
    required String profileId,
    Duration lookback = const Duration(days: 90),
  }) async {
    if (!isSupported) {
      throw StateError('Health sync is only on Android and iPhone.');
    }
    if (!await isEnabled()) {
      throw StateError('Connect $platformLabel first.');
    }
    await _ensureConfigured();

    final end = DateTime.now();
    final start = end.subtract(lookback);
    final points = await _health.getHealthDataFromTypes(
      types: types,
      startTime: start,
      endTime: end,
    );

    var weight = 0;
    var glucose = 0;
    var bp = 0;
    var steps = 0;
    var sleep = 0;
    var skipped = 0;

    // Group BP systolic/diastolic by minute bucket so one report can hold both.
    final bpBuckets = <int, _BpPair>{};
    // Aggregate steps / sleep-asleep minutes by calendar day.
    final stepByDay = <String, _DayAgg>{};
    final sleepByDay = <String, _DayAgg>{};

    for (final p in points) {
      final numVal = _numeric(p);
      if (numVal == null) {
        skipped++;
        continue;
      }
      final observed = p.dateFrom;
      final ext = 'hc:${p.uuid}';

      switch (p.type) {
        case HealthDataType.WEIGHT:
          final kg = _toKg(numVal, p.unit);
          final r = await store.addManualPanel(
            profileId: profileId,
            title: 'Health · Weight',
            collectedAt: observed,
            source: _reportSource(),
            values: [
              ManualObservationInput(
                parameterCode: 'weight',
                parameterName: 'Weight',
                valueReported: _fmt(kg),
                unitReported: 'kg',
                externalId: ext,
                source: _obsSource(),
              ),
            ],
          );
          if (r != null) {
            weight++;
          } else {
            skipped++;
          }
          break;
        case HealthDataType.BLOOD_GLUCOSE:
          final mgdl = _toMgDl(numVal, p.unit);
          final r = await store.addManualPanel(
            profileId: profileId,
            title: 'Health · Glucose',
            collectedAt: observed,
            source: _reportSource(),
            values: [
              ManualObservationInput(
                parameterCode: 'glu_cap',
                parameterName: 'Glucose, capillary (glucometer)',
                valueReported: _fmt(mgdl),
                unitReported: 'mg/dL',
                externalId: ext,
                source: _obsSource(),
              ),
            ],
          );
          if (r != null) {
            glucose++;
          } else {
            skipped++;
          }
          break;
        case HealthDataType.BLOOD_PRESSURE_SYSTOLIC:
        case HealthDataType.BLOOD_PRESSURE_DIASTOLIC:
          final bucket =
              observed.millisecondsSinceEpoch ~/ 60000; // per minute
          final pair = bpBuckets.putIfAbsent(bucket, () => _BpPair(observed));
          if (p.type == HealthDataType.BLOOD_PRESSURE_SYSTOLIC) {
            pair.sys = numVal.round();
            pair.sysExt = ext;
          } else {
            pair.dia = numVal.round();
            pair.diaExt = ext;
          }
          break;
        case HealthDataType.STEPS:
          final day = _dayKey(observed);
          final agg = stepByDay.putIfAbsent(
            day,
            () => _DayAgg(observed, ext),
          );
          agg.value += numVal;
          if (observed.isAfter(agg.at)) {
            agg.at = observed;
            agg.ext = ext;
          }
          break;
        case HealthDataType.SLEEP_ASLEEP:
          // Prefer sample span; fall back to numeric minutes.
          final spanMin = p.dateTo.difference(p.dateFrom).inMinutes;
          final mins = spanMin > 0 ? spanMin.toDouble() : numVal;
          if (mins <= 0) {
            skipped++;
            break;
          }
          final day = _dayKey(observed);
          final agg = sleepByDay.putIfAbsent(
            day,
            () => _DayAgg(observed, ext),
          );
          agg.value += mins;
          if (observed.isAfter(agg.at)) {
            agg.at = observed;
            agg.ext = ext;
          }
          break;
        default:
          skipped++;
      }
    }

    for (final pair in bpBuckets.values) {
      if (pair.sys == null && pair.dia == null) continue;
      final values = <ManualObservationInput>[];
      if (pair.sys != null) {
        values.add(
          ManualObservationInput(
            parameterCode: 'bp_sys',
            parameterName: 'Blood pressure, systolic',
            valueReported: '${pair.sys}',
            unitReported: 'mmHg',
            externalId: pair.sysExt,
            source: _obsSource(),
          ),
        );
      }
      if (pair.dia != null) {
        values.add(
          ManualObservationInput(
            parameterCode: 'bp_dia',
            parameterName: 'Blood pressure, diastolic',
            valueReported: '${pair.dia}',
            unitReported: 'mmHg',
            externalId: pair.diaExt,
            source: _obsSource(),
          ),
        );
      }
      final r = await store.addManualPanel(
        profileId: profileId,
        title: 'Health · Blood pressure',
        collectedAt: pair.at,
        source: _reportSource(),
        values: values,
      );
      if (r != null) {
        bp++;
      } else {
        skipped++;
      }
    }

    for (final e in stepByDay.entries) {
      final agg = e.value;
      final total = agg.value.round();
      if (total <= 0) continue;
      final r = await store.addManualPanel(
        profileId: profileId,
        title: 'Health · Steps',
        collectedAt: agg.at,
        source: _reportSource(),
        values: [
          ManualObservationInput(
            parameterCode: 'steps',
            parameterName: 'Steps',
            valueReported: '$total',
            unitReported: 'steps',
            externalId: 'hc:steps:${e.key}',
            source: _obsSource(),
          ),
        ],
      );
      if (r != null) {
        steps++;
      } else {
        skipped++;
      }
    }

    for (final e in sleepByDay.entries) {
      final agg = e.value;
      if (agg.value <= 0) continue;
      final hours = agg.value / 60.0;
      final r = await store.addManualPanel(
        profileId: profileId,
        title: 'Health · Sleep',
        collectedAt: agg.at,
        source: _reportSource(),
        values: [
          ManualObservationInput(
            parameterCode: 'sleep_hrs',
            parameterName: 'Sleep duration',
            valueReported: _fmt(hours),
            unitReported: 'h',
            externalId: 'hc:sleep:${e.key}',
            source: _obsSource(),
          ),
        ],
      );
      if (r != null) {
        sleep++;
      } else {
        skipped++;
      }
    }

    await _touchLastSync();
    return HealthImportResult(
      weight: weight,
      glucose: glucose,
      bloodPressure: bp,
      steps: steps,
      sleep: sleep,
      skipped: skipped,
    );
  }

  String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Push a single Vitalog reading to the OS health store (if write enabled).
  Future<bool> writeReading({
    required String parameterCode,
    required double value,
    required String unit,
    required DateTime at,
  }) async {
    if (!isSupported) return false;
    if (!await isEnabled() || !await isWriteEnabled()) return false;
    await _ensureConfigured();

    final code = parameterCode.toLowerCase();
    try {
      if (code == 'weight') {
        final kg = unit.toLowerCase().contains('lb') ? value * 0.45359237 : value;
        return await _health.writeHealthData(
          value: kg,
          type: HealthDataType.WEIGHT,
          startTime: at,
          endTime: at,
          recordingMethod: RecordingMethod.manual,
        );
      }
      if (code == 'glu_cap' || code == 'glu_r' || code == 'glu_f' || code == 'glu_pp') {
        final mgdl = unit.toLowerCase().contains('mmol')
            ? value * 18.0182
            : value;
        return await _health.writeHealthData(
          value: mgdl,
          unit: HealthDataUnit.MILLIGRAM_PER_DECILITER,
          type: HealthDataType.BLOOD_GLUCOSE,
          startTime: at,
          endTime: at,
          recordingMethod: RecordingMethod.manual,
        );
      }
      if (code == 'steps') {
        return await _health.writeHealthData(
          value: value,
          type: HealthDataType.STEPS,
          startTime: at,
          endTime: at,
          recordingMethod: RecordingMethod.manual,
        );
      }
      if (code == 'sleep_hrs') {
        final mins = (value * 60).round();
        if (mins <= 0) return false;
        final end = at;
        final start = end.subtract(Duration(minutes: mins));
        return await _health.writeHealthData(
          value: mins.toDouble(),
          type: HealthDataType.SLEEP_ASLEEP,
          startTime: start,
          endTime: end,
          recordingMethod: RecordingMethod.manual,
        );
      }
      // BP write needs both sides — callers should use [writeBloodPressure].
      return false;
    } catch (e, st) {
      debugPrint('HealthConnectService.writeReading: $e\n$st');
      return false;
    }
  }

  Future<bool> writeBloodPressure({
    required int systolic,
    required int diastolic,
    required DateTime at,
  }) async {
    if (!isSupported) return false;
    if (!await isEnabled() || !await isWriteEnabled()) return false;
    await _ensureConfigured();
    try {
      return await _health.writeBloodPressure(
        systolic: systolic,
        diastolic: diastolic,
        startTime: at,
        endTime: at,
        recordingMethod: RecordingMethod.manual,
      );
    } catch (e, st) {
      debugPrint('HealthConnectService.writeBloodPressure: $e\n$st');
      return false;
    }
  }

  String _reportSource() =>
      Platform.isIOS ? 'healthkit' : 'health_connect';

  String _obsSource() => _reportSource();

  static double? _numeric(HealthDataPoint p) {
    final v = p.value;
    if (v is NumericHealthValue) return v.numericValue.toDouble();
    return null;
  }

  static double _toKg(double value, HealthDataUnit unit) {
    if (unit == HealthDataUnit.POUND) return value * 0.45359237;
    return value; // KILOGRAM default
  }

  static double _toMgDl(double value, HealthDataUnit unit) {
    final name = unit.name.toUpperCase();
    if (name.contains('MILLIMOLE')) {
      return value * 18.0182;
    }
    return value;
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return '${v.round()}';
    return v.toStringAsFixed(1);
  }
}

enum HealthBridgeStatus {
  unsupported,
  missingApp,
  ready,
  needsAuth,
  connected,
}

class HealthImportResult {
  const HealthImportResult({
    required this.weight,
    required this.glucose,
    required this.bloodPressure,
    required this.steps,
    required this.sleep,
    required this.skipped,
  });

  final int weight;
  final int glucose;
  final int bloodPressure;
  final int steps;
  final int sleep;
  final int skipped;

  int get imported => weight + glucose + bloodPressure + steps + sleep;

  String get summary {
    if (imported == 0) {
      return skipped > 0
          ? 'No new readings (skipped $skipped).'
          : 'No readings in that period.';
    }
    final parts = <String>[];
    if (weight > 0) parts.add('$weight weight');
    if (glucose > 0) parts.add('$glucose glucose');
    if (bloodPressure > 0) parts.add('$bloodPressure blood pressure');
    if (steps > 0) parts.add('$steps steps days');
    if (sleep > 0) parts.add('$sleep sleep nights');
    return 'Imported ${parts.join(', ')}.';
  }
}

class _BpPair {
  _BpPair(this.at);
  final DateTime at;
  int? sys;
  int? dia;
  String? sysExt;
  String? diaExt;
}

class _DayAgg {
  _DayAgg(this.at, this.ext);
  DateTime at;
  String? ext;
  double value = 0;
}
