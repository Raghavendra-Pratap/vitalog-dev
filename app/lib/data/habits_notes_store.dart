import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Daily habits + freeform notes (Phase 2 / ADR-003: track, don't diagnose).
///
/// Habit kinds: `yes_no` | `count` | `duration` (minutes).
/// Partial day: count/duration with 0 < value < goal.
mixin HabitsNotesStoreMixin {
  Database get userDb;
  Uuid get uuid;

  Future<void> ensureHabitsNotesTables() async {
    final db = userDb;
    await db.execute('''
CREATE TABLE IF NOT EXISTS habit (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  title TEXT NOT NULL,
  cadence TEXT NOT NULL DEFAULT 'daily',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS habit_log (
  id TEXT PRIMARY KEY,
  habit_id TEXT NOT NULL,
  profile_id TEXT NOT NULL,
  logged_on TEXT NOT NULL,
  done INTEGER NOT NULL DEFAULT 1,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS note (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  include_in_doctor_summary INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');

    await _addCol(db, 'habit', 'kind', "TEXT NOT NULL DEFAULT 'yes_no'");
    await _addCol(db, 'habit', 'goal_value', 'REAL');
    await _addCol(db, 'habit', 'unit_label', 'TEXT');
    await _addCol(db, 'habit', 'days_mask', "TEXT NOT NULL DEFAULT '1111111'");
    await _addCol(db, 'habit', 'reminder_enabled', 'INTEGER NOT NULL DEFAULT 0');
    await _addCol(db, 'habit', 'reminder_hm', 'TEXT');
    await _addCol(db, 'habit', 'template_key', 'TEXT');
    await _addCol(db, 'habit', 'ended_on', 'TEXT');
    await _addCol(db, 'habit', 'chart_codes_json', "TEXT NOT NULL DEFAULT '[]'");

    await _addCol(db, 'habit_log', 'value', 'REAL');
    await _addCol(db, 'habit_log', 'logged_by_profile_id', 'TEXT');

    await _addCol(db, 'note', 'when_kind', "TEXT NOT NULL DEFAULT 'none'");
    await _addCol(db, 'note', 'start_ymd', 'TEXT');
    await _addCol(db, 'note', 'end_ymd', 'TEXT');
    await _addCol(db, 'note', 'tags_json', "TEXT NOT NULL DEFAULT '[]'");
    await _addCol(db, 'note', 'chart_codes_json', "TEXT NOT NULL DEFAULT '[]'");
    await _addCol(db, 'note', 'habit_id', 'TEXT');
  }

  Future<void> _addCol(
    Database db,
    String table,
    String col,
    String decl,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.any((c) => c['name'] == col)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $col $decl');
  }

  Future<List<Map<String, Object?>>> listHabits(String profileId) async {
    return userDb.query(
      'habit',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
  }

  Future<Map<String, Object?>?> getHabit(String id) async {
    final rows = await userDb.query(
      'habit',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<String> addHabit({
    required String profileId,
    required String title,
    String cadence = 'daily',
    String kind = 'yes_no',
    double? goalValue,
    String? unitLabel,
    String daysMask = '1111111',
    bool reminderEnabled = false,
    String? reminderHm,
    String? templateKey,
    List<String> chartCodes = const [],
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = uuid.v4();
    await userDb.insert('habit', {
      'id': id,
      'profile_id': profileId,
      'title': title.trim(),
      'cadence': cadence,
      'kind': kind,
      'goal_value': goalValue,
      'unit_label': unitLabel,
      'days_mask': daysMask,
      'reminder_enabled': reminderEnabled ? 1 : 0,
      'reminder_hm': reminderHm,
      'template_key': templateKey,
      'ended_on': null,
      'chart_codes_json': jsonEncode(chartCodes),
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
    return id;
  }

  Future<void> updateHabit({
    required String id,
    required String title,
    required String kind,
    double? goalValue,
    String? unitLabel,
    String daysMask = '1111111',
    bool reminderEnabled = false,
    String? reminderHm,
    List<String> chartCodes = const [],
    String? endedOn,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'habit',
      {
        'title': title.trim(),
        'kind': kind,
        'goal_value': goalValue,
        'unit_label': unitLabel,
        'days_mask': daysMask,
        'reminder_enabled': reminderEnabled ? 1 : 0,
        'reminder_hm': reminderHm,
        'chart_codes_json': jsonEncode(chartCodes),
        'ended_on': endedOn,
        'updated_at': now,
        'hlc': '$now-0-local',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDeleteHabit(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'habit',
      {'deleted': 1, 'updated_at': now, 'hlc': '$now-0-local'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Aggregate multiple day entries into one synthetic log row for charts/stats.
  Map<String, Object?> _aggregateHabitLogs(List<Map<String, Object?>> rows) {
    final first = rows.first;
    var sum = 0.0;
    var anyDone = false;
    for (final r in rows) {
      sum += (r['value'] as num?)?.toDouble() ?? 0;
      final d = r['done'];
      if (d == 1 || d == true || d == 1.0) anyDone = true;
    }
    return {
      ...first,
      'value': sum,
      'done': anyDone ? 1 : 0,
      'entry_count': rows.length,
    };
  }

  /// Replace-or-set day's total (one logical day). Soft-deletes prior entries,
  /// then inserts a single row — used by Today quick actions.
  Future<void> setHabitProgress({
    required String habitId,
    required String profileId,
    required String loggedOnYmd,
    required String kind,
    double? goalValue,
    bool? done,
    double? value,
    String? loggedByProfileId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    late final int doneFlag;
    late final double storeValue;
    if (kind == 'yes_no') {
      doneFlag = (done ?? false) ? 1 : 0;
      storeValue = doneFlag == 1 ? 1.0 : 0.0;
    } else {
      storeValue = value ?? 0;
      final goal = goalValue ?? 0;
      doneFlag = (goal > 0 && storeValue >= goal) ? 1 : 0;
    }

    final existing = await userDb.query(
      'habit_log',
      where: 'habit_id = ? AND logged_on = ? AND deleted = 0',
      whereArgs: [habitId, loggedOnYmd],
    );
    for (final r in existing) {
      await userDb.update(
        'habit_log',
        {'deleted': 1, 'updated_at': now, 'hlc': '$now-0-local'},
        where: 'id = ?',
        whereArgs: [r['id']],
      );
    }

    if (kind == 'yes_no' && doneFlag == 0 && storeValue <= 0) {
      return; // cleared
    }
    if (kind != 'yes_no' && storeValue <= 0) {
      return;
    }

    await userDb.insert('habit_log', {
      'id': uuid.v4(),
      'habit_id': habitId,
      'profile_id': profileId,
      'logged_on': loggedOnYmd,
      'note': null,
      'done': doneFlag,
      'value': storeValue,
      'logged_by_profile_id': loggedByProfileId ?? profileId,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
  }

  Future<List<Map<String, Object?>>> listHabitLogEntries({
    required String habitId,
    required String loggedOnYmd,
  }) async {
    return userDb.query(
      'habit_log',
      where: 'habit_id = ? AND logged_on = ? AND deleted = 0',
      whereArgs: [habitId, loggedOnYmd],
      orderBy: 'created_at ASC',
    );
  }

  Future<String> addHabitLogEntry({
    required String habitId,
    required String profileId,
    required String loggedOnYmd,
    required String kind,
    double? goalValue,
    double? value,
    bool? done,
    String? note,
    String? loggedByProfileId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    late final int doneFlag;
    late final double storeValue;
    if (kind == 'yes_no') {
      doneFlag = (done ?? true) ? 1 : 0;
      storeValue = doneFlag == 1 ? 1.0 : 0.0;
    } else {
      storeValue = value ?? 0;
      final goal = goalValue ?? 0;
      doneFlag = (goal > 0 && storeValue >= goal) ? 1 : 0;
    }
    final id = uuid.v4();
    await userDb.insert('habit_log', {
      'id': id,
      'habit_id': habitId,
      'profile_id': profileId,
      'logged_on': loggedOnYmd,
      'note': note,
      'done': doneFlag,
      'value': storeValue,
      'logged_by_profile_id': loggedByProfileId ?? profileId,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
    return id;
  }

  Future<void> updateHabitLogEntry({
    required String id,
    required String kind,
    double? goalValue,
    double? value,
    bool? done,
    String? note,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    late final int doneFlag;
    late final double storeValue;
    if (kind == 'yes_no') {
      doneFlag = (done ?? false) ? 1 : 0;
      storeValue = doneFlag == 1 ? 1.0 : 0.0;
    } else {
      storeValue = value ?? 0;
      final goal = goalValue ?? 0;
      doneFlag = (goal > 0 && storeValue >= goal) ? 1 : 0;
    }
    await userDb.update(
      'habit_log',
      {
        'done': doneFlag,
        'value': storeValue,
        if (note != null) 'note': note,
        'updated_at': now,
        'hlc': '$now-0-local',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDeleteHabitLogEntry(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'habit_log',
      {'deleted': 1, 'updated_at': now, 'hlc': '$now-0-local'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setHabitDone({
    required String habitId,
    required String profileId,
    required String loggedOnYmd,
    required bool done,
  }) =>
      setHabitProgress(
        habitId: habitId,
        profileId: profileId,
        loggedOnYmd: loggedOnYmd,
        kind: 'yes_no',
        done: done,
        loggedByProfileId: profileId,
      );

  Future<Set<String>> habitDoneIdsForDay(String profileId, String ymd) async {
    final byHabit = await habitLogsForDay(profileId, ymd);
    return {
      for (final e in byHabit.entries)
        if ((e.value['done'] as int? ?? 0) == 1 ||
            ((e.value['value'] as num?)?.toDouble() ?? 0) > 0)
          e.key,
    };
  }

  Future<Map<String, Map<String, Object?>>> habitLogsForDay(
    String profileId,
    String ymd,
  ) async {
    final rows = await userDb.query(
      'habit_log',
      where: 'profile_id = ? AND logged_on = ? AND deleted = 0',
      whereArgs: [profileId, ymd],
    );
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      (grouped[r['habit_id']! as String] ??= []).add(r);
    }
    return {
      for (final e in grouped.entries) e.key: _aggregateHabitLogs(e.value),
    };
  }

  Future<Map<String, Set<String>>> habitDoneMapForRange(
    String profileId,
    String startYmd,
    String endYmd,
  ) async {
    final range = await habitLogsForRange(profileId, startYmd, endYmd);
    final out = <String, Set<String>>{};
    for (final e in range.entries) {
      for (final day in e.value.entries) {
        final log = day.value;
        final done = (log['done'] as int? ?? 0) == 1;
        final v = (log['value'] as num?)?.toDouble() ?? 0;
        if (done || v > 0) {
          (out[e.key] ??= {}).add(day.key);
        }
      }
    }
    return out;
  }

  Future<Map<String, Map<String, Map<String, Object?>>>> habitLogsForRange(
    String profileId,
    String startYmd,
    String endYmd,
  ) async {
    final rows = await userDb.query(
      'habit_log',
      where:
          'profile_id = ? AND logged_on >= ? AND logged_on <= ? AND deleted = 0',
      whereArgs: [profileId, startYmd, endYmd],
    );
    final grouped = <String, Map<String, List<Map<String, Object?>>>>{};
    for (final r in rows) {
      final hid = r['habit_id']! as String;
      final ymd = r['logged_on']! as String;
      ((grouped[hid] ??= {})[ymd] ??= []).add(r);
    }
    final out = <String, Map<String, Map<String, Object?>>>{};
    for (final he in grouped.entries) {
      out[he.key] = {
        for (final de in he.value.entries)
          de.key: _aggregateHabitLogs(de.value),
      };
    }
    return out;
  }

  Future<List<Map<String, Object?>>> listNotes(String profileId) async {
    // Copy — sqflite_sqlcipher may return a fixed-length list; in-place sort throws.
    final rows = List<Map<String, Object?>>.from(
      await userDb.query(
        'note',
        where: 'profile_id = ? AND deleted = 0',
        whereArgs: [profileId],
      ),
    );
    int updatedMs(Map<String, Object?> r) {
      final v = r['updated_at'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }
    rows.sort((a, b) {
      final ak = '${a['when_kind'] ?? 'none'}';
      final bk = '${b['when_kind'] ?? 'none'}';
      final aUndated = ak == 'none' ? 0 : 1;
      final bUndated = bk == 'none' ? 0 : 1;
      if (aUndated != bUndated) return aUndated.compareTo(bUndated);
      final as_ = '${a['start_ymd'] ?? ''}';
      final bs_ = '${b['start_ymd'] ?? ''}';
      if (as_ != bs_) return bs_.compareTo(as_);
      return updatedMs(b).compareTo(updatedMs(a));
    });
    return rows;
  }

  Future<Map<String, Object?>?> getNote(String id) async {
    final rows = await userDb.query(
      'note',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<String> addNote({
    required String profileId,
    required String title,
    required String body,
    bool includeInDoctorSummary = false,
    String whenKind = 'none',
    String? startYmd,
    String? endYmd,
    List<String> tags = const [],
    List<String> chartCodes = const [],
    String? habitId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = uuid.v4();
    await userDb.insert('note', {
      'id': id,
      'profile_id': profileId,
      'title': title.trim(),
      'body': body.trim(),
      'include_in_doctor_summary': includeInDoctorSummary ? 1 : 0,
      'when_kind': whenKind,
      'start_ymd': startYmd,
      'end_ymd': endYmd,
      'tags_json': jsonEncode(tags),
      'chart_codes_json': jsonEncode(chartCodes),
      'habit_id': habitId,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
    return id;
  }

  Future<void> updateNote({
    required String id,
    required String title,
    required String body,
    required bool includeInDoctorSummary,
    required String whenKind,
    String? startYmd,
    String? endYmd,
    List<String> tags = const [],
    List<String> chartCodes = const [],
    String? habitId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'note',
      {
        'title': title.trim(),
        'body': body.trim(),
        'include_in_doctor_summary': includeInDoctorSummary ? 1 : 0,
        'when_kind': whenKind,
        'start_ymd': startYmd,
        'end_ymd': endYmd,
        'tags_json': jsonEncode(tags),
        'chart_codes_json': jsonEncode(chartCodes),
        if (habitId != null) 'habit_id': habitId,
        'updated_at': now,
        'hlc': '$now-0-local',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDeleteNote(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'note',
      {'deleted': 1, 'updated_at': now, 'hlc': '$now-0-local'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Note for one habit on one calendar day (at most one).
  Future<Map<String, Object?>?> habitDayNote({
    required String habitId,
    required String ymd,
  }) async {
    final rows = await userDb.query(
      'note',
      where:
          'habit_id = ? AND when_kind = ? AND start_ymd = ? AND deleted = 0',
      whereArgs: [habitId, 'day', ymd],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> listNotesForHabit(String habitId) async {
    final rows = List<Map<String, Object?>>.from(
      await userDb.query(
        'note',
        where: 'habit_id = ? AND deleted = 0',
        whereArgs: [habitId],
      ),
    );
    rows.sort((a, b) {
      final as_ = '${a['start_ymd'] ?? ''}';
      final bs_ = '${b['start_ymd'] ?? ''}';
      if (as_ != bs_) return bs_.compareTo(as_);
      final au = a['updated_at'];
      final bu = b['updated_at'];
      final ai = au is int ? au : (au is num ? au.toInt() : 0);
      final bi = bu is int ? bu : (bu is num ? bu.toInt() : 0);
      return bi.compareTo(ai);
    });
    return rows;
  }

  /// Create or update the day note for a habit. Empty [body] soft-deletes.
  Future<void> upsertHabitDayNote({
    required String profileId,
    required String habitId,
    required String habitTitle,
    required String ymd,
    required String body,
    List<String> chartCodes = const [],
  }) async {
    final trimmed = body.trim();
    final existing = await habitDayNote(habitId: habitId, ymd: ymd);
    if (trimmed.isEmpty) {
      if (existing != null) {
        await softDeleteNote(existing['id']! as String);
      }
      return;
    }
    final title = habitTitle.trim().isEmpty ? 'Habit' : habitTitle.trim();
    if (existing != null) {
      await updateNote(
        id: existing['id']! as String,
        title: title,
        body: trimmed,
        includeInDoctorSummary:
            (existing['include_in_doctor_summary'] as int? ?? 0) == 1,
        whenKind: 'day',
        startYmd: ymd,
        endYmd: ymd,
        tags: noteTags(existing),
        chartCodes: chartCodes.isEmpty
            ? noteChartCodes(existing)
            : chartCodes,
        habitId: habitId,
      );
      return;
    }
    await addNote(
      profileId: profileId,
      title: title,
      body: trimmed,
      whenKind: 'day',
      startYmd: ymd,
      endYmd: ymd,
      chartCodes: chartCodes,
      habitId: habitId,
    );
  }

  Future<List<Map<String, Object?>>> notesForChartCode(
    String profileId,
    String parameterCode,
  ) async {
    final all = await listNotes(profileId);
    return [
      for (final n in all)
        if (chartCodesMatch(_jsonList(n['chart_codes_json']), parameterCode)) n,
    ];
  }

  Future<List<Map<String, Object?>>> habitsForChartCode(
    String profileId,
    String parameterCode,
  ) async {
    final habits = await listHabits(profileId);
    return [
      for (final h in habits)
        if (chartCodesMatch(_jsonList(h['chart_codes_json']), parameterCode)) h,
    ];
  }

  /// Habits that have a reminder enabled (any profile) — for OS reschedule.
  Future<List<Map<String, Object?>>> listHabitsWithReminders() async {
    return userDb.query(
      'habit',
      where: 'deleted = 0 AND reminder_enabled = 1',
    );
  }

  Future<List<Map<String, Object?>>> listAllHabits() async {
    return userDb.query(
      'habit',
      where: 'deleted = 0',
    );
  }

}

List<String> _jsonList(Object? raw) {
  if (raw == null) return const [];
  try {
    final decoded = jsonDecode(raw as String);
    if (decoded is List) {
      return [for (final e in decoded) '$e'.trim()]
          .where((e) => e.isNotEmpty)
          .toList();
    }
  } catch (_) {}
  return const [];
}

/// Sentinel in [chart_codes_json] — show on every trend chart.
const String kChartCodeAll = '*';

bool chartCodesAreAll(List<String> codes) => codes.contains(kChartCodeAll);

bool chartCodesMatch(List<String> codes, String parameterCode) =>
    chartCodesAreAll(codes) || codes.contains(parameterCode);

List<String> habitChartCodes(Map<String, Object?> h) =>
    _jsonList(h['chart_codes_json']);

List<String> noteChartCodes(Map<String, Object?> n) =>
    _jsonList(n['chart_codes_json']);

/// Human summary for UI (“all charts” or joined codes).
String chartCodesLabel(List<String> codes) {
  if (codes.isEmpty) return '';
  if (chartCodesAreAll(codes)) return 'all charts';
  return codes.join(' · ');
}

List<String> noteTags(Map<String, Object?> n) => _jsonList(n['tags_json']);

String habitDayState({
  required String kind,
  required double? goalValue,
  Map<String, Object?>? log,
}) {
  if (log == null) return 'none';
  final doneRaw = log['done'];
  final done = doneRaw == true ||
      doneRaw == 1 ||
      doneRaw == 1.0 ||
      (doneRaw is num && doneRaw.toInt() == 1) ||
      doneRaw == '1';
  if (kind == 'yes_no') return done ? 'done' : 'none';
  // Prefer summed value vs goal so multi-entry days mark complete correctly.
  final v = (log['value'] as num?)?.toDouble() ?? 0;
  if (goalValue != null && goalValue > 0 && v >= goalValue) return 'done';
  if (done) return 'done';
  if (v > 0) return 'partial';
  return 'none';
}

bool habitScheduledOn(String daysMask, DateTime day) {
  final m = daysMask.padRight(7, '1').substring(0, 7);
  final idx = (day.weekday - 1).clamp(0, 6);
  return m[idx] == '1';
}


String habitScheduleLabel(String? daysMask) {
  final m = (daysMask ?? '1111111').padRight(7, '1').substring(0, 7);
  if (m == '1111111') return 'Every day';
  if (m == '1111100') return 'Weekdays';
  if (m == '0000011') return 'Weekends';
  final n = m.split('').where((c) => c == '1').length;
  return n == 1 ? '1 day / week' : '$n days / week';
}

String habitKindLabel(String? kind) {
  switch (kind) {
    case 'duration':
      return 'Duration';
    case 'count':
      return 'Count';
    default:
      return 'Yes / no';
  }
}

String habitGoalLabel(Map<String, Object?> h) {
  final kind = (h['kind'] as String?) ?? 'yes_no';
  final goal = (h['goal_value'] as num?)?.toDouble();
  if (kind == 'yes_no' || goal == null || goal <= 0) return '—';
  final unit = (h['unit_label'] as String?)?.trim();
  final g = goal == goal.roundToDouble()
      ? goal.toStringAsFixed(0)
      : goal.toString();
  if (unit != null && unit.isNotEmpty) return '$g $unit';
  if (kind == 'duration') return '$g min';
  return g;
}

String habitReminderLabel(Map<String, Object?> h) {
  final on = (h['reminder_enabled'] as int? ?? 0) == 1;
  if (!on) return 'Off';
  final hm = (h['reminder_hm'] as String?)?.trim();
  if (hm == null || hm.isEmpty) return 'On';
  final parts = hm.split(':');
  if (parts.length >= 2) {
    final hour = int.tryParse(parts[0]) ?? 0;
    final min = int.tryParse(parts[1]) ?? 0;
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final ampm = hour < 12 ? 'am' : 'pm';
    return '$h12:${min.toString().padLeft(2, '0')} $ampm';
  }
  return hm;
}

/// Done / scheduled / partial counts over scheduled days in [start]..[end] inclusive.
({int done, int scheduled, int partial, double sumValues, int valuedDays})
    habitWindowStats({
  required Map<String, Object?> habit,
  required Map<String, Map<String, Object?>> logs,
  required DateTime start,
  required DateTime end,
  DateTime? asOf,
}) {
  final kind = (habit['kind'] as String?) ?? 'yes_no';
  final goal = (habit['goal_value'] as num?)?.toDouble();
  final mask = (habit['days_mask'] as String?) ?? '1111111';
  final cap = asOf ?? DateTime.now();
  final today = DateTime(cap.year, cap.month, cap.day);
  var done = 0;
  var scheduled = 0;
  var partial = 0;
  var sum = 0.0;
  var valued = 0;
  for (var d = start;
      !d.isAfter(end);
      d = d.add(const Duration(days: 1))) {
    final day = DateTime(d.year, d.month, d.day);
    if (day.isAfter(today)) continue;
    if (!habitScheduledOn(mask, day)) continue;
    scheduled++;
    final ymd =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final log = logs[ymd];
    final st = habitDayState(kind: kind, goalValue: goal, log: log);
    if (st == 'done') done++;
    if (st == 'partial') partial++;
    final v = (log?['value'] as num?)?.toDouble();
    if (v != null && v > 0) {
      sum += v;
      valued++;
    }
  }
  return (
    done: done,
    scheduled: scheduled,
    partial: partial,
    sumValues: sum,
    valuedDays: valued,
  );
}

const habitTemplates = <Map<String, String>>[
  {'key': 'walk', 'title': 'Walk', 'kind': 'duration', 'goal': '30', 'unit': 'min', 'section': 'lifestyle'},
  {'key': 'water', 'title': 'Drink water', 'kind': 'count', 'goal': '8', 'unit': 'glasses', 'section': 'lifestyle'},
  {'key': 'stretch', 'title': 'Stretch', 'kind': 'yes_no', 'goal': '', 'unit': '', 'section': 'lifestyle'},
  {'key': 'sleep_early', 'title': 'Sleep by 10:30', 'kind': 'yes_no', 'goal': '', 'unit': '', 'section': 'lifestyle'},
  {'key': 'meditate', 'title': 'Meditate', 'kind': 'duration', 'goal': '10', 'unit': 'min', 'section': 'lifestyle'},
];

List<Map<String, String>> habitTemplatesFor(String section) => [
      for (final t in habitTemplates)
        if ((t['section'] ?? 'lifestyle') == section) t,
    ];
