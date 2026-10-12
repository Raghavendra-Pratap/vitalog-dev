import 'dart:convert';
import 'reminder_rrule.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

/// Visits + reminders (M3) on user.db.
mixin CareStoreMixin {
  Database get userDb;
  Uuid get uuid;

  Future<void> ensureCareTables() async {
    await userDb.execute('''
CREATE TABLE IF NOT EXISTS provider (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  name TEXT NOT NULL,
  specialty TEXT,
  clinic TEXT,
  phone TEXT,
  notes TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await userDb.execute('''
CREATE TABLE IF NOT EXISTS visit (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  provider_id TEXT,
  visited_at INTEGER NOT NULL,
  reason TEXT,
  diagnosis TEXT,
  notes TEXT,
  follow_up_date TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await userDb.execute('''
CREATE TABLE IF NOT EXISTS reminder (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  target_code TEXT,
  provider_id TEXT,
  rrule TEXT,
  notes TEXT,
  due_at INTEGER NOT NULL,
  lead_minutes INTEGER NOT NULL DEFAULT 1440,
  active INTEGER NOT NULL DEFAULT 1,
  last_done_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');

    final provCols = await userDb.rawQuery('PRAGMA table_info(provider)');
    if (!provCols.any((col) => col['name'] == 'clinic')) {
      await userDb.execute('ALTER TABLE provider ADD COLUMN clinic TEXT');
    }
    final remCols = await userDb.rawQuery('PRAGMA table_info(reminder)');
    if (!remCols.any((col) => col['name'] == 'notes')) {
      await userDb.execute('ALTER TABLE reminder ADD COLUMN notes TEXT');
    }
    final hasAssignee = remCols.any((c) => c['name'] == 'assignee_profile_id');
    if (!hasAssignee) {
      await userDb.execute(
        'ALTER TABLE reminder ADD COLUMN assignee_profile_id TEXT',
      );
    }
    final hasObservers = remCols.any((c) => c['name'] == 'observer_ids_json');
    if (!hasObservers) {
      await userDb.execute(
        'ALTER TABLE reminder ADD COLUMN observer_ids_json TEXT',
      );
    }
  }

  /// Household-shared: reuse a doctor with the same name on any profile.
  Future<String?> _ensureProvider({
    required String profileId,
    required String? name,
  }) async {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final existing = await userDb.query(
      'provider',
      where: 'deleted = 0 AND lower(name) = lower(?)',
      whereArgs: [trimmed],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id']! as String;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = uuid.v4();
    await userDb.insert('provider', {
      'id': id,
      'profile_id': profileId,
      'name': trimmed,
      'specialty': null,
      'clinic': null,
      'phone': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
    return id;
  }

  Future<List<VisitRecord>> listVisits(String profileId) async {
    final rows = await userDb.rawQuery('''
SELECT v.*, p.name AS provider_name, p.clinic AS provider_clinic
FROM visit v
LEFT JOIN provider p ON p.id = v.provider_id AND p.deleted = 0
WHERE v.profile_id = ? AND v.deleted = 0
ORDER BY v.visited_at DESC
''', [profileId]);
    return [
      for (final r in rows)
        VisitRecord(
          id: r['id']! as String,
          profileId: r['profile_id']! as String,
          visitedAt:
              DateTime.fromMillisecondsSinceEpoch(r['visited_at']! as int),
          reason: r['reason'] as String?,
          diagnosis: r['diagnosis'] as String?,
          notes: r['notes'] as String?,
          followUpDate: r['follow_up_date'] as String?,
          providerId: r['provider_id'] as String?,
          providerName: r['provider_name'] as String?,
          providerClinic: r['provider_clinic'] as String?,
        ),
    ];
  }

  Future<String?> clinicForDoctorName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    final rows = await userDb.query(
      'provider',
      columns: ['clinic'],
      where: "deleted = 0 AND lower(name) = lower(?) AND clinic IS NOT NULL AND trim(clinic) != ''",
      whereArgs: [n],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['clinic'] as String?;
  }

  /// Doctor names shared across the family vault (deduped).
  Future<List<String>> listDoctorNames(String profileId) async {
    final rows = await userDb.query(
      'provider',
      columns: ['name'],
      where: 'deleted = 0',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    final seen = <String>{};
    final out = <String>[];
    for (final r in rows) {
      final n = r['name']! as String;
      final key = n.toLowerCase();
      if (seen.add(key)) out.add(n);
    }
    return out;
  }

  /// Providers shared across the family vault — one card per name.
  Future<List<ProviderRecord>> listProviders(String profileId) async {
    final rows = await userDb.query(
      'provider',
      where: 'deleted = 0',
      orderBy: 'updated_at DESC',
    );
    final byName = <String, ProviderRecord>{};
    for (final r in rows) {
      final name = r['name']! as String;
      final key = name.toLowerCase();
      if (byName.containsKey(key)) {
        // Prefer the richer / newer row; fill empty fields from older duplicates.
        final cur = byName[key]!;
        byName[key] = ProviderRecord(
          id: cur.id,
          profileId: cur.profileId,
          name: cur.name,
          specialty: _nonEmpty(cur.specialty) ?? r['specialty'] as String?,
          clinic: _nonEmpty(cur.clinic) ?? r['clinic'] as String?,
          phone: _nonEmpty(cur.phone) ?? r['phone'] as String?,
          notes: _nonEmpty(cur.notes) ?? r['notes'] as String?,
        );
        continue;
      }
      byName[key] = ProviderRecord(
        id: r['id']! as String,
        profileId: r['profile_id']! as String,
        name: name,
        specialty: r['specialty'] as String?,
        clinic: r['clinic'] as String?,
        phone: r['phone'] as String?,
        notes: r['notes'] as String?,
      );
    }
    final list = byName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  String? _nonEmpty(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  /// Insert or update a provider by id or unique name across the family vault.
  Future<String> upsertProvider({
    required String profileId,
    required String name,
    String? specialty,
    String? clinic,
    String? phone,
    String? notes,
    String? existingId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Doctor name required');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    String? id = existingId;
    if (id == null) {
      final existing = await userDb.query(
        'provider',
        where: 'deleted = 0 AND lower(name) = lower(?)',
        whereArgs: [trimmed],
        orderBy: 'updated_at DESC',
        limit: 1,
      );
      if (existing.isNotEmpty) id = existing.first['id']! as String;
    }
    if (id != null) {
      await userDb.update(
        'provider',
        {
          'name': trimmed,
          'specialty': specialty,
          'clinic': clinic,
          'phone': phone,
          'notes': notes,
          'updated_at': now,
          'hlc': '$now-0-local',
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    id = uuid.v4();
    await userDb.insert('provider', {
      'id': id,
      'profile_id': profileId,
      'name': trimmed,
      'specialty': specialty,
      'clinic': clinic,
      'phone': phone,
      'notes': notes,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
    return id;
  }

  Future<VisitRecord> addVisit({
    required String profileId,
    required DateTime visitedAt,
    String? reason,
    String? diagnosis,
    String? notes,
    String? followUpDate,
    String? providerName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = uuid.v4();
    final providerId = await _ensureProvider(
      profileId: profileId,
      name: providerName,
    );
    final cleanedProvider = providerName?.trim();
    await userDb.insert('visit', {
      'id': id,
      'profile_id': profileId,
      'provider_id': providerId,
      'visited_at': visitedAt.millisecondsSinceEpoch,
      'reason': reason,
      'diagnosis': diagnosis,
      'notes': notes,
      'follow_up_date': followUpDate,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
    return VisitRecord(
      id: id,
      profileId: profileId,
      visitedAt: visitedAt,
      reason: reason,
      diagnosis: diagnosis,
      notes: notes,
      followUpDate: followUpDate,
      providerId: providerId,
      providerName:
          (cleanedProvider == null || cleanedProvider.isEmpty)
              ? null
              : cleanedProvider,
    );
  }


  Future<void> softDeleteProvider(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'provider',
      {'deleted': 1, 'updated_at': now, 'hlc': '$now-0-local'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<VisitRecord?> getVisit(String visitId) async {
    final rows = await userDb.query(
      'visit',
      where: 'id = ? AND deleted = 0',
      whereArgs: [visitId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    String? providerName;
    final provId = r['provider_id'] as String?;
    String? providerClinic;
    if (provId != null) {
      final p = await userDb.query(
        'provider',
        columns: ['name', 'clinic'],
        where: 'id = ?',
        whereArgs: [provId],
        limit: 1,
      );
      if (p.isNotEmpty) {
        providerName = p.first['name'] as String?;
        providerClinic = p.first['clinic'] as String?;
      }
    }
    return VisitRecord(
      id: r['id']! as String,
      profileId: r['profile_id']! as String,
      visitedAt: DateTime.fromMillisecondsSinceEpoch(r['visited_at']! as int),
      reason: r['reason'] as String?,
      diagnosis: r['diagnosis'] as String?,
      notes: r['notes'] as String?,
      followUpDate: r['follow_up_date'] as String?,
      providerId: provId,
      providerName: providerName,
      providerClinic: providerClinic,
    );
  }

  Future<VisitRecord> updateVisit({
    required String visitId,
    required String profileId,
    required DateTime visitedAt,
    String? reason,
    String? diagnosis,
    String? notes,
    String? followUpDate,
    String? providerName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final providerId = await _ensureProvider(
      profileId: profileId,
      name: providerName,
    );
    final cleanedProvider = providerName?.trim();
    await userDb.update(
      'visit',
      {
        'provider_id': providerId,
        'visited_at': visitedAt.millisecondsSinceEpoch,
        'reason': reason,
        'diagnosis': diagnosis,
        'notes': notes,
        'follow_up_date': followUpDate,
        'updated_at': now,
        'hlc': '$now-0-local',
      },
      where: 'id = ? AND profile_id = ? AND deleted = 0',
      whereArgs: [visitId, profileId],
    );
    final clinic = (cleanedProvider == null || cleanedProvider.isEmpty)
        ? null
        : await clinicForDoctorName(cleanedProvider);
    return VisitRecord(
      id: visitId,
      profileId: profileId,
      visitedAt: visitedAt,
      reason: reason,
      diagnosis: diagnosis,
      notes: notes,
      followUpDate: followUpDate,
      providerId: providerId,
      providerName:
          (cleanedProvider == null || cleanedProvider.isEmpty)
              ? null
              : cleanedProvider,
      providerClinic: clinic,
    );
  }

  Future<List<ReminderRecord>> listReminders(String profileId) async {
    final rows = await userDb.query(
      'reminder',
      where: 'profile_id = ? AND deleted = 0 AND active = 1',
      whereArgs: [profileId],
      orderBy: 'due_at ASC',
    );
    return [
      for (final r in rows)
        ReminderRecord(
          id: r['id']! as String,
          profileId: r['profile_id']! as String,
          kind: r['kind']! as String,
          title: r['title']! as String,
          targetCode: r['target_code'] as String?,
          dueAt: DateTime.fromMillisecondsSinceEpoch(r['due_at']! as int),
          rrule: r['rrule'] as String?,
          notes: r['notes'] as String?,
        ),
    ];
  }

  Future<List<ReminderRecord>> dueReminders(String profileId) async {
    final all = await listReminders(profileId);
    final now = DateTime.now();
    return all.where((r) => !r.dueAt.isAfter(now)).toList();
  }

  Future<ReminderRecord> addReminder({
    required String profileId,
    required String title,
    required DateTime dueAt,
    String kind = 'custom',
    String? targetCode,
    String? rrule,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = uuid.v4();
    final rule = (rrule == null || rrule.trim().isEmpty) ? null : rrule.trim();
    final note = (notes == null || notes.trim().isEmpty) ? null : notes.trim();
    await userDb.insert('reminder', {
      'id': id,
      'profile_id': profileId,
      'kind': kind,
      'title': title,
      'target_code': targetCode,
      'provider_id': null,
      'rrule': rule,
      'notes': note,
      'due_at': dueAt.millisecondsSinceEpoch,
      'lead_minutes': 1440,
      'active': 1,
      'last_done_at': null,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
    return ReminderRecord(
      id: id,
      profileId: profileId,
      kind: kind,
      title: title,
      targetCode: targetCode,
      dueAt: dueAt,
      rrule: rule,
      notes: note,
    );
  }

  Future<ReminderRecord?> findVisitFollowUpReminder(
    String profileId,
    String visitId,
  ) async {
    final rows = await userDb.query(
      'reminder',
      where:
          "profile_id = ? AND deleted = 0 AND kind = 'visit' AND target_code = ?",
      whereArgs: [profileId, visitId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return ReminderRecord(
      id: r['id']! as String,
      profileId: r['profile_id']! as String,
      kind: r['kind']! as String,
      title: r['title']! as String,
      targetCode: r['target_code'] as String?,
      dueAt: DateTime.fromMillisecondsSinceEpoch(r['due_at']! as int),
      rrule: r['rrule'] as String?,
      notes: r['notes'] as String?,
    );
  }

  Future<ReminderRecord> updateReminder({
    required String id,
    required String title,
    required DateTime dueAt,
    String? notes,
    bool active = true,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final note = (notes == null || notes.trim().isEmpty) ? null : notes.trim();
    await userDb.update(
      'reminder',
      {
        'title': title,
        'due_at': dueAt.millisecondsSinceEpoch,
        if (notes != null) 'notes': note,
        'active': active ? 1 : 0,
        'updated_at': now,
        'hlc': '$now-0-local',
        'deleted': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    final rows = await userDb.query(
      'reminder',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final r = rows.first;
    return ReminderRecord(
      id: r['id']! as String,
      profileId: r['profile_id']! as String,
      kind: r['kind']! as String,
      title: r['title']! as String,
      targetCode: r['target_code'] as String?,
      dueAt: DateTime.fromMillisecondsSinceEpoch(r['due_at']! as int),
      rrule: r['rrule'] as String?,
      notes: r['notes'] as String?,
    );
  }

  Future<void> softDeleteReminder(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'reminder',
      {
        'deleted': 1,
        'active': 0,
        'updated_at': now,
        'hlc': '$now-0-local',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  ReminderRecord _reminderFromRow(Map<String, Object?> r) {
    List<String>? observers;
    final rawObs = r['observer_ids_json'] as String?;
    if (rawObs != null && rawObs.trim().isNotEmpty) {
      try {
        observers = [
          for (final e in (jsonDecode(rawObs) as List)) '$e',
        ];
      } catch (_) {}
    }
    return ReminderRecord(
      id: r['id']! as String,
      profileId: r['profile_id']! as String,
      kind: r['kind']! as String,
      title: r['title']! as String,
      targetCode: r['target_code'] as String?,
      dueAt: DateTime.fromMillisecondsSinceEpoch(r['due_at']! as int),
      rrule: r['rrule'] as String?,
      notes: r['notes'] as String?,
      assigneeProfileId: r['assignee_profile_id'] as String?,
      observerProfileIds: observers,
    );
  }

  bool _sameLocalDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Soft-delete every visit follow-up reminder for [visitId] except [keepId].
  Future<void> _purgeOtherVisitFollowUps({
    required String profileId,
    required String visitId,
    required String keepId,
    required String title,
    required DateTime dueDay,
  }) async {
    final rows = await userDb.query(
      'reminder',
      where:
          "profile_id = ? AND deleted = 0 AND kind = 'visit' AND id != ?",
      whereArgs: [profileId, keepId],
    );
    for (final r in rows) {
      final target = r['target_code'] as String?;
      final rowTitle = r['title']! as String;
      final due = DateTime.fromMillisecondsSinceEpoch(r['due_at']! as int);
      final linked = target == visitId;
      final orphanSame = (target == null || target.isEmpty) &&
          rowTitle == title &&
          _sameLocalDay(due, dueDay);
      if (linked || orphanSame) {
        await softDeleteReminder(r['id']! as String);
      }
    }
  }

  /// Keep a visit follow-up date mirrored as an active reminder (or cleared).
  /// Returns the reminder when present after sync; null when cleared.
  Future<ReminderRecord?> syncVisitFollowUpReminder({
    required String profileId,
    required String visitId,
    required String? followUpDateYmd,
    required String title,
  }) async {
    final ymd = followUpDateYmd?.trim();
    if (ymd == null || ymd.isEmpty) {
      final rows = await userDb.query(
        'reminder',
        where:
            "profile_id = ? AND deleted = 0 AND kind = 'visit' AND target_code = ?",
        whereArgs: [profileId, visitId],
      );
      for (final r in rows) {
        await softDeleteReminder(r['id']! as String);
      }
      return null;
    }
    final parts = ymd.split('-');
    if (parts.length != 3) {
      return findVisitFollowUpReminder(profileId, visitId);
    }
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) {
      return findVisitFollowUpReminder(profileId, visitId);
    }
    // Midnight local — notification layer fires at 09:00 for date-only dues.
    final dueAt = DateTime(y, m, d);

    // Prefer linked row; else claim any same-title/same-day visit orphan.
    ReminderRecord? keep = await findVisitFollowUpReminder(profileId, visitId);
    if (keep == null) {
      final candidates = await userDb.query(
        'reminder',
        where:
            "profile_id = ? AND deleted = 0 AND active = 1 AND kind = 'visit'",
        whereArgs: [profileId],
        orderBy: 'created_at ASC',
      );
      for (final r in candidates) {
        final target = r['target_code'] as String?;
        final due = DateTime.fromMillisecondsSinceEpoch(r['due_at']! as int);
        final titleMatch = (r['title']! as String) == title;
        final dayMatch = _sameLocalDay(due, dueAt);
        if (target == visitId ||
            ((target == null || target.isEmpty) && titleMatch && dayMatch)) {
          keep = _reminderFromRow(r);
          break;
        }
      }
    }

    if (keep != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await userDb.update(
        'reminder',
        {
          'target_code': visitId,
          'title': title,
          'due_at': dueAt.millisecondsSinceEpoch,
          'active': 1,
          'updated_at': now,
          'hlc': '$now-0-local',
          'deleted': 0,
        },
        where: 'id = ?',
        whereArgs: [keep.id],
      );
      keep = await updateReminder(id: keep.id, title: title, dueAt: dueAt);
    } else {
      keep = await addReminder(
        profileId: profileId,
        title: title,
        dueAt: dueAt,
        kind: 'visit',
        targetCode: visitId,
      );
    }

    await _purgeOtherVisitFollowUps(
      profileId: profileId,
      visitId: visitId,
      keepId: keep.id,
      title: title,
      dueDay: dueAt,
    );
    return keep;
  }

  /// Create missing follow-up reminders for visits that already have a date.
  /// Idempotent: collapses duplicates from earlier races / legacy rows.
  Future<List<ReminderRecord>> ensureVisitFollowUpReminders(
    String profileId,
  ) async {
    final visits = await listVisits(profileId);
    final out = <ReminderRecord>[];
    for (final v in visits) {
      final ymd = v.followUpDate?.trim();
      if (ymd == null || ymd.isEmpty) continue;
      final title = (v.reason == null || v.reason!.trim().isEmpty)
          ? 'Follow-up visit'
          : 'Follow-up: ${v.reason!.trim()}';
      final rem = await syncVisitFollowUpReminder(
        profileId: profileId,
        visitId: v.id,
        followUpDateYmd: ymd,
        title: title,
      );
      if (rem != null) out.add(rem);
    }
    return out;
  }

  /// One-shot → deactivate. Recurring → advance [due_at] and keep active.
  Future<ReminderRecord?> completeReminder(String id) async {
    final rows = await userDb.query(
      'reminder',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final rule = r['rrule'] as String?;
    final due = DateTime.fromMillisecondsSinceEpoch(r['due_at']! as int);

    if (rule != null && rule.trim().isNotEmpty) {
      final next = rollForwardDue(nextReminderDue(due, rule), rule, now);
      await userDb.update(
        'reminder',
        {
          'due_at': next.millisecondsSinceEpoch,
          'last_done_at': nowMs,
          'updated_at': nowMs,
          'hlc': '$nowMs-0-local',
          'active': 1,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return ReminderRecord(
        id: r['id']! as String,
        profileId: r['profile_id']! as String,
        kind: r['kind']! as String,
        title: r['title']! as String,
        targetCode: r['target_code'] as String?,
        dueAt: next,
        rrule: rule,
        notes: r['notes'] as String?,
      );
    }

    await userDb.update(
      'reminder',
      {
        'active': 0,
        'last_done_at': nowMs,
        'updated_at': nowMs,
        'hlc': '$nowMs-0-local',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return null;
  }

  /// Roll past-due recurring rows forward (call before scheduling).
  Future<List<ReminderRecord>> rollForwardRecurring(String profileId) async {
    final all = await listReminders(profileId);
    final now = DateTime.now();
    final out = <ReminderRecord>[];
    for (final rem in all) {
      if (!rem.isRecurring) {
        out.add(rem);
        continue;
      }
      final next = rollForwardDue(rem.dueAt, rem.rrule, now);
      if (next.millisecondsSinceEpoch == rem.dueAt.millisecondsSinceEpoch) {
        out.add(rem);
        continue;
      }
      final ms = DateTime.now().millisecondsSinceEpoch;
      await userDb.update(
        'reminder',
        {
          'due_at': next.millisecondsSinceEpoch,
          'updated_at': ms,
          'hlc': '$ms-0-local',
        },
        where: 'id = ?',
        whereArgs: [rem.id],
      );
      out.add(ReminderRecord(
        id: rem.id,
        profileId: rem.profileId,
        kind: rem.kind,
        title: rem.title,
        targetCode: rem.targetCode,
        dueAt: next,
        rrule: rem.rrule,
        notes: rem.notes,
      ));
    }
    return out;
  }
}
