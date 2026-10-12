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
    final existing = await userDb.query(
      'habit_log',
      where: 'habit_id = ? AND logged_on = ? AND deleted = 0',
      whereArgs: [habitId, loggedOnYmd],
      limit: 1,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    late final int doneFlag;
    late final double? storeValue;
    if (kind == 'yes_no') {
      doneFlag = (done ?? false) ? 1 : 0;
      storeValue = doneFlag == 1 ? 1.0 : 0.0;
    } else {
      storeValue = value ?? 0;
      final goal = goalValue ?? 0;
      doneFlag = (goal > 0 && storeValue >= goal) ? 1 : 0;
    }
    final row = {
      'done': doneFlag,
      'value': storeValue,
      'logged_by_profile_id': loggedByProfileId ?? profileId,
      'updated_at': now,
      'hlc': '$now-0-local',
    };
    if (existing.isEmpty) {
      await userDb.insert('habit_log', {
        'id': uuid.v4(),
        'habit_id': habitId,
        'profile_id': profileId,
        'logged_on': loggedOnYmd,
        'note': null,
        'created_at': now,
        'deleted': 0,
        ...row,
      });
    } else {
      await userDb.update(
        'habit_log',
        row,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
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
    final rows = await userDb.query(
      'habit_log',
      where: 'profile_id = ? AND logged_on = ? AND done = 1 AND deleted = 0',
      whereArgs: [profileId, ymd],
    );
    return {for (final r in rows) r['habit_id']! as String};
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
    return {for (final r in rows) r['habit_id']! as String: r};
  }

  Future<Map<String, Set<String>>> habitDoneMapForRange(
    String profileId,
    String startYmd,
    String endYmd,
  ) async {
    final rows = await userDb.query(
      'habit_log',
      where:
          'profile_id = ? AND logged_on >= ? AND logged_on <= ? AND done = 1 AND deleted = 0',
      whereArgs: [profileId, startYmd, endYmd],
    );
    final out = <String, Set<String>>{};
    for (final r in rows) {
      final hid = r['habit_id']! as String;
      (out[hid] ??= {}).add(r['logged_on']! as String);
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
    final out = <String, Map<String, Map<String, Object?>>>{};
    for (final r in rows) {
      final hid = r['habit_id']! as String;
      final ymd = r['logged_on']! as String;
      (out[hid] ??= {})[ymd] = r;
    }
    return out;
  }

  Future<List<Map<String, Object?>>> listNotes(String profileId) async {
    final rows = await userDb.query(
      'note',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
    );
    rows.sort((a, b) {
      final ak = (a['when_kind'] as String?) ?? 'none';
      final bk = (b['when_kind'] as String?) ?? 'none';
      final aUndated = ak == 'none' ? 0 : 1;
      final bUndated = bk == 'none' ? 0 : 1;
      if (aUndated != bUndated) return aUndated.compareTo(bUndated);
      final as_ = (a['start_ymd'] as String?) ?? '';
      final bs_ = (b['start_ymd'] as String?) ?? '';
      if (as_ != bs_) return bs_.compareTo(as_);
      return ((b['updated_at'] as int?) ?? 0)
          .compareTo((a['updated_at'] as int?) ?? 0);
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

  Future<List<Map<String, Object?>>> notesForChartCode(
    String profileId,
    String parameterCode,
  ) async {
    final all = await listNotes(profileId);
    return [
      for (final n in all)
        if (_jsonList(n['chart_codes_json']).contains(parameterCode)) n,
    ];
  }

  Future<List<Map<String, Object?>>> habitsForChartCode(
    String profileId,
    String parameterCode,
  ) async {
    final habits = await listHabits(profileId);
    return [
      for (final h in habits)
        if (_jsonList(h['chart_codes_json']).contains(parameterCode)) h,
    ];
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

List<String> habitChartCodes(Map<String, Object?> h) =>
    _jsonList(h['chart_codes_json']);

List<String> noteChartCodes(Map<String, Object?> n) =>
    _jsonList(n['chart_codes_json']);

List<String> noteTags(Map<String, Object?> n) => _jsonList(n['tags_json']);

String habitDayState({
  required String kind,
  required double? goalValue,
  Map<String, Object?>? log,
}) {
  if (log == null) return 'none';
  final done = (log['done'] as int? ?? 0) == 1;
  if (done) return 'done';
  if (kind == 'yes_no') return 'none';
  final v = (log['value'] as num?)?.toDouble() ?? 0;
  if (v > 0) return 'partial';
  return 'none';
}

bool habitScheduledOn(String daysMask, DateTime day) {
  final m = daysMask.padRight(7, '1').substring(0, 7);
  final idx = (day.weekday - 1).clamp(0, 6);
  return m[idx] == '1';
}

const habitTemplates = <Map<String, String>>[
  {'key': 'walk', 'title': 'Walk', 'kind': 'duration', 'goal': '30', 'unit': 'min'},
  {'key': 'water', 'title': 'Drink water', 'kind': 'count', 'goal': '8', 'unit': 'glasses'},
  {'key': 'stretch', 'title': 'Stretch', 'kind': 'yes_no', 'goal': '', 'unit': ''},
  {'key': 'sleep_early', 'title': 'Sleep by 10:30', 'kind': 'yes_no', 'goal': '', 'unit': ''},
  {'key': 'meditate', 'title': 'Meditate', 'kind': 'duration', 'goal': '10', 'unit': 'min'},
];
