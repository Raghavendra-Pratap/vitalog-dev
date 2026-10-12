import 'dart:convert';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

/// Medical-profile tables + CRUD on the shared user.db.
mixin MedicalStoreMixin {
  Database get userDb;
  Uuid get uuid;

  Future<void> ensureMedicalTables() async {
    final db = userDb;
    await db.execute('''
CREATE TABLE IF NOT EXISTS condition (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  onset_date TEXT,
  notes TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS allergy (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  substance TEXT NOT NULL,
  reaction TEXT,
  severity TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS medication (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  name TEXT NOT NULL,
  strength TEXT,
  instructions TEXT,
  visit_id TEXT,
  start_date TEXT,
  end_date TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS immunization (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  vaccine TEXT NOT NULL,
  given_on TEXT,
  next_due_on TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS procedure_record (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  name TEXT NOT NULL,
  performed_on TEXT,
  notes TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS family_history (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  relation TEXT NOT NULL,
  condition_name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS emergency_contact (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  name TEXT NOT NULL,
  relation TEXT,
  phone TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS medication_schedule (
  id TEXT PRIMARY KEY,
  medication_id TEXT NOT NULL,
  rrule TEXT NOT NULL,
  times_json TEXT NOT NULL,
  dose_amount REAL,
  dose_unit TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS medication_log (
  id TEXT PRIMARY KEY,
  medication_id TEXT NOT NULL,
  scheduled_for INTEGER NOT NULL,
  status TEXT NOT NULL,
  acted_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');


    final medCols = await db.rawQuery('PRAGMA table_info(medication)');
    final hasVisitId = medCols.any((c) => c['name'] == 'visit_id');
    if (!hasVisitId) {
      await db.execute('ALTER TABLE medication ADD COLUMN visit_id TEXT');
    }
    final hasKind = medCols.any((c) => c['name'] == 'kind');
    if (!hasKind) {
      await db.execute(
        "ALTER TABLE medication ADD COLUMN kind TEXT NOT NULL DEFAULT 'other'",
      );
    }
    final hasPills = medCols.any((c) => c['name'] == 'pill_count');
    if (!hasPills) {
      await db.execute('ALTER TABLE medication ADD COLUMN pill_count INTEGER');
    }
    final hasRestock = medCols.any((c) => c['name'] == 'restock_on');
    if (!hasRestock) {
      await db.execute('ALTER TABLE medication ADD COLUMN restock_on TEXT');
    }
    final hasPrescribed = medCols.any((c) => c['name'] == 'prescribed_as');
    if (!hasPrescribed) {
      await db.execute('ALTER TABLE medication ADD COLUMN prescribed_as TEXT');
    }
    final hasForm = medCols.any((c) => c['name'] == 'dosage_form');
    if (!hasForm) {
      await db.execute('ALTER TABLE medication ADD COLUMN dosage_form TEXT');
    }
    final logCols = await db.rawQuery('PRAGMA table_info(medication_log)');
    if (!logCols.any((c) => c['name'] == 'acted_by_profile_id')) {
      await db.execute(
        'ALTER TABLE medication_log ADD COLUMN acted_by_profile_id TEXT',
      );
    }

  }

  Future<List<MedicalItem>> listConditions(String profileId) async {
    final rows = await userDb.query(
      'condition',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
    return [
      for (final r in rows)
        MedicalItem(
          id: r['id']! as String,
          title: r['name']! as String,
          subtitle: r['status'] as String?,
        ),
    ];
  }

  MedicalItem _medicationFromRow(Map<String, Object?> r) {
    final prescribed = r['prescribed_as'] as String?;
    return MedicalItem(
      id: r['id']! as String,
      title: r['name']! as String,
      subtitle: [
        medicationKindLabel(r['kind'] as String?),
        if ((r['strength'] as String?)?.isNotEmpty == true)
          r['strength'] as String,
        if (prescribed != null && prescribed.isNotEmpty)
          'prescribed as $prescribed',
        if (r['pill_count'] != null) '${r['pill_count']} left',
        if ((r['restock_on'] as String?)?.isNotEmpty == true)
          'restock ${r['restock_on']}',
      ].join(' · '),
      kind: r['kind'] as String?,
      strength: r['strength'] as String?,
      instructions: r['instructions'] as String?,
      pillCount: r['pill_count'] as int?,
      restockOn: r['restock_on'] as String?,
      prescribedAs: prescribed,
      visitId: r['visit_id'] as String?,
      endDate: r['end_date'] as String?,
      dosageForm: r['dosage_form'] as String?,
    );
  }

  Future<List<MedicalItem>> listMedications(String profileId) async {
    final rows = await userDb.query(
      'medication',
      where: 'profile_id = ? AND deleted = 0 AND end_date IS NULL',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
    return [for (final r in rows) _medicationFromRow(r)];
  }

  /// Active + completed courses (for visit grouping).
  Future<List<MedicalItem>> listAllMedications(String profileId) async {
    final rows = await userDb.query(
      'medication',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
    return [for (final r in rows) _medicationFromRow(r)];
  }

  Future<List<MedicalItem>> listMedicationsForVisit(String visitId) async {
    final rows = await userDb.query(
      'medication',
      where: 'visit_id = ? AND deleted = 0',
      whereArgs: [visitId],
      orderBy: 'created_at ASC',
    );
    return [for (final r in rows) _medicationFromRow(r)];
  }

  Future<MedicalItem?> getMedication(String id) async {
    final rows = await userDb.query(
      'medication',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _medicationFromRow(rows.first);
  }

  Future<List<MedicalItem>> listAllergies(String profileId) async {
    final rows = await userDb.query(
      'allergy',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
    return [
      for (final r in rows)
        MedicalItem(
          id: r['id']! as String,
          title: r['substance']! as String,
          subtitle: [
            if ((r['reaction'] as String?)?.isNotEmpty == true) r['reaction'],
            if ((r['severity'] as String?)?.isNotEmpty == true) r['severity'],
          ].whereType<String>().join(' · '),
        ),
    ];
  }

  Future<List<MedicalItem>> listImmunizations(String profileId) async {
    final rows = await userDb.query(
      'immunization',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
    return [
      for (final r in rows)
        MedicalItem(
          id: r['id']! as String,
          title: r['vaccine']! as String,
          subtitle: r['given_on'] as String?,
        ),
    ];
  }

  Future<List<MedicalItem>> listProcedures(String profileId) async {
    final rows = await userDb.query(
      'procedure_record',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
    return [
      for (final r in rows)
        MedicalItem(
          id: r['id']! as String,
          title: r['name']! as String,
          subtitle: r['performed_on'] as String?,
        ),
    ];
  }

  Future<List<MedicalItem>> listFamilyHistory(String profileId) async {
    final rows = await userDb.query(
      'family_history',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
    return [
      for (final r in rows)
        MedicalItem(
          id: r['id']! as String,
          title: r['condition_name']! as String,
          subtitle: r['relation'] as String?,
        ),
    ];
  }

  Future<List<MedicalItem>> listEmergencyContacts(String profileId) async {
    final rows = await userDb.query(
      'emergency_contact',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
    return [
      for (final r in rows)
        MedicalItem(
          id: r['id']! as String,
          title: r['name']! as String,
          subtitle: [
            if ((r['relation'] as String?)?.isNotEmpty == true) r['relation'],
            if ((r['phone'] as String?)?.isNotEmpty == true) r['phone'],
          ].whereType<String>().join(' · '),
        ),
    ];
  }

  Future<void> addCondition({
    required String profileId,
    required String name,
    String status = 'active',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.insert('condition', {
      'id': uuid.v4(),
      'profile_id': profileId,
      'name': name,
      'status': status,
      'onset_date': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
  }

  Future<void> addAllergy({
    required String profileId,
    required String substance,
    String? reaction,
    String? severity,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.insert('allergy', {
      'id': uuid.v4(),
      'profile_id': profileId,
      'substance': substance,
      'reaction': reaction,
      'severity': severity,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
  }

  Future<String> addMedication({
    required String profileId,
    required String name,
    String kind = 'other',
    String? strength,
    String? instructions,
    String? visitId,
    int? pillCount,
    String? restockOn,
    String? prescribedAs,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = uuid.v4();
    final safeKind = kMedicationKinds.contains(kind) ? kind : 'other';
    await userDb.insert('medication', {
      'id': id,
      'profile_id': profileId,
      'name': name,
      'kind': safeKind,
      'strength': strength,
      'instructions': instructions,
      'visit_id': visitId,
      'pill_count': pillCount,
      'restock_on': restockOn,
      'prescribed_as': prescribedAs,
      'start_date': null,
      'end_date': null,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
    return id;
  }

  Future<void> updateMedication({
    required String id,
    required String name,
    String kind = 'other',
    String? strength,
    String? instructions,
    int? pillCount,
    String? restockOn,
    String? prescribedAs,
    String? dosageForm,
    String? endDate,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final safeKind = kMedicationKinds.contains(kind) ? kind : 'other';
    await userDb.update(
      'medication',
      {
        'name': name,
        'kind': safeKind,
        'strength': strength,
        'instructions': instructions,
        'pill_count': pillCount,
        'restock_on': restockOn,
        'prescribed_as': prescribedAs,
        'dosage_form': dosageForm,
        'end_date': endDate,
        'updated_at': now,
        'hlc': '$now-0-local',
      },
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
  }

  /// Soft-delete a medicine and its schedules (dose logs kept for history).
  Future<void> softDeleteMedication(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = '$now-0-local';
    await userDb.update(
      'medication',
      {'deleted': 1, 'updated_at': now, 'hlc': hlc},
      where: 'id = ?',
      whereArgs: [id],
    );
    await userDb.update(
      'medication_schedule',
      {'deleted': 1, 'updated_at': now, 'hlc': hlc},
      where: 'medication_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _softDeleteRow(String table, String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      table,
      {'deleted': 1, 'updated_at': now, 'hlc': '$now-0-local'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDeleteCondition(String id) => _softDeleteRow('condition', id);
  Future<void> softDeleteAllergy(String id) => _softDeleteRow('allergy', id);
  Future<void> softDeleteImmunization(String id) =>
      _softDeleteRow('immunization', id);
  Future<void> softDeleteProcedure(String id) =>
      _softDeleteRow('procedure_record', id);
  Future<void> softDeleteFamilyHistory(String id) =>
      _softDeleteRow('family_history', id);
  Future<void> softDeleteEmergencyContact(String id) =>
      _softDeleteRow('emergency_contact', id);

  Future<void> updateCondition({
    required String id,
    required String name,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'condition',
      {
        'name': name.trim(),
        'updated_at': now,
        'hlc': '$now-0-local',
      },
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
  }

  Future<void> updateAllergy({
    required String id,
    required String substance,
    String? reaction,
    String? severity,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'allergy',
      {
        'substance': substance.trim(),
        'reaction': reaction,
        'severity': severity,
        'updated_at': now,
        'hlc': '$now-0-local',
      },
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
  }

  Future<void> updateImmunization({
    required String id,
    required String vaccine,
    String? givenOn,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'immunization',
      {
        'vaccine': vaccine.trim(),
        'given_on': givenOn,
        'updated_at': now,
        'hlc': '$now-0-local',
      },
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
  }

  Future<void> updateProcedure({
    required String id,
    required String name,
    String? performedOn,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'procedure_record',
      {
        'name': name.trim(),
        'performed_on': performedOn,
        'updated_at': now,
        'hlc': '$now-0-local',
      },
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
  }

  Future<void> updateFamilyHistory({
    required String id,
    required String conditionName,
    required String relation,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'family_history',
      {
        'condition_name': conditionName.trim(),
        'relation': relation.trim(),
        'updated_at': now,
        'hlc': '$now-0-local',
      },
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
  }

  Future<void> updateEmergencyContact({
    required String id,
    required String name,
    String? relation,
    String? phone,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'emergency_contact',
      {
        'name': name.trim(),
        'relation': relation,
        'phone': phone,
        'updated_at': now,
        'hlc': '$now-0-local',
      },
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
  }

  /// Record that the bottle/brand differs from what was prescribed.
  Future<void> setMedicationAlternative({
    required String id,
    required String takenAs,
    String? previousName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await userDb.query(
      'medication',
      columns: ['name', 'prescribed_as'],
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final current = rows.first['name']! as String;
    final existingPrescribed = rows.first['prescribed_as'] as String?;
    final prescribed = (existingPrescribed != null &&
            existingPrescribed.trim().isNotEmpty)
        ? existingPrescribed
        : (previousName ?? current);
    await userDb.update(
      'medication',
      {
        'name': takenAs.trim(),
        'prescribed_as': prescribed,
        'updated_at': now,
        'hlc': '$now-0-local',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> addImmunization({
    required String profileId,
    required String vaccine,
    String? givenOn,
    String? nextDueOn,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.insert('immunization', {
      'id': uuid.v4(),
      'profile_id': profileId,
      'vaccine': vaccine,
      'given_on': givenOn,
      'next_due_on': nextDueOn,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
  }

  Future<String> addProcedure({
    required String profileId,
    required String name,
    String? performedOn,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = uuid.v4();
    await userDb.insert('procedure_record', {
      'id': id,
      'profile_id': profileId,
      'name': name,
      'performed_on': performedOn,
      'notes': notes,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
    return id;
  }

  Future<void> addFamilyHistory({
    required String profileId,
    required String relation,
    required String conditionName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.insert('family_history', {
      'id': uuid.v4(),
      'profile_id': profileId,
      'relation': relation,
      'condition_name': conditionName,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
  }

  Future<void> addEmergencyContact({
    required String profileId,
    required String name,
    String? relation,
    String? phone,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.insert('emergency_contact', {
      'id': uuid.v4(),
      'profile_id': profileId,
      'name': name,
      'relation': relation,
      'phone': phone,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
  }


  Future<void> addMedicationSchedule({
    required String medicationId,
    required List<String> times,
    String rrule = 'FREQ=DAILY',
    double? doseAmount,
    String? doseUnit,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.insert('medication_schedule', {
      'id': uuid.v4(),
      'medication_id': medicationId,
      'rrule': rrule,
      'times_json': jsonEncode(times),
      'dose_amount': doseAmount,
      'dose_unit': doseUnit,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
  }

  Future<List<MedicalItem>> listMedicationSchedules(String medicationId) async {
    final rows = await userDb.query(
      'medication_schedule',
      where: 'medication_id = ? AND deleted = 0',
      whereArgs: [medicationId],
    );
    return [
      for (final r in rows)
        MedicalItem(
          id: r['id']! as String,
          title: (r['times_json'] as String?) ?? '',
          subtitle: r['rrule'] as String?,
        ),
    ];
  }

  Future<void> logMedicationTaken({
    required String medicationId,
    required DateTime scheduledFor,
    String? actedByProfileId,
  }) =>
      _logMedicationStatus(
        medicationId: medicationId,
        scheduledFor: scheduledFor,
        status: 'taken',
        actedByProfileId: actedByProfileId,
      );

  Future<void> logMedicationSkipped({
    required String medicationId,
    required DateTime scheduledFor,
    String? actedByProfileId,
  }) =>
      _logMedicationStatus(
        medicationId: medicationId,
        scheduledFor: scheduledFor,
        status: 'skipped',
        actedByProfileId: actedByProfileId,
      );

  Future<void> _logMedicationStatus({
    required String medicationId,
    required DateTime scheduledFor,
    required String status,
    String? actedByProfileId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dayStart = DateTime(
      scheduledFor.year,
      scheduledFor.month,
      scheduledFor.day,
      scheduledFor.hour,
      scheduledFor.minute,
    ).millisecondsSinceEpoch;
    await userDb.delete(
      'medication_log',
      where: 'medication_id = ? AND scheduled_for = ? AND deleted = 0',
      whereArgs: [medicationId, dayStart],
    );
    await userDb.insert('medication_log', {
      'id': uuid.v4(),
      'medication_id': medicationId,
      'scheduled_for': dayStart,
      'status': status,
      'acted_at': now,
      'acted_by_profile_id': actedByProfileId,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });
  }

  Future<List<MedicationScheduleInfo>> listAllMedicationSchedules() async {
    final rows = await userDb.rawQuery('''
SELECT s.id AS schedule_id, s.medication_id, s.times_json,
       m.name AS med_name, m.kind AS med_kind, m.strength AS med_strength
FROM medication_schedule s
JOIN medication m ON m.id = s.medication_id
WHERE s.deleted = 0 AND m.deleted = 0 AND m.end_date IS NULL
''');
    final out = <MedicationScheduleInfo>[];
    for (final r in rows) {
      List<String> times = const [];
      try {
        final decoded = jsonDecode(r['times_json'] as String? ?? '[]');
        if (decoded is List) {
          times = [for (final e in decoded) '$e'.trim()]
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {}
      if (times.isEmpty) continue;
      out.add(
        MedicationScheduleInfo(
          scheduleId: r['schedule_id']! as String,
          medicationId: r['medication_id']! as String,
          medicationName: r['med_name']! as String,
          kind: (r['med_kind'] as String?) ?? 'other',
          times: times,
          strength: r['med_strength'] as String?,
        ),
      );
    }
    return out;
  }

  Future<List<MedicationDoseSlot>> listTodaysDoses(String profileId) async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final schedules = await userDb.rawQuery('''
SELECT s.medication_id, s.times_json, m.name, m.kind, m.strength
FROM medication_schedule s
JOIN medication m ON m.id = s.medication_id
WHERE m.profile_id = ? AND s.deleted = 0 AND m.deleted = 0
  AND m.end_date IS NULL
''', [profileId]);

    final logs = await userDb.query(
      'medication_log',
      where: 'deleted = 0 AND scheduled_for >= ? AND scheduled_for < ?',
      whereArgs: [
        day.millisecondsSinceEpoch,
        day.add(const Duration(days: 1)).millisecondsSinceEpoch,
      ],
    );
    final logByKey = <String, String>{};
    for (final l in logs) {
      final mid = l['medication_id']! as String;
      final when = DateTime.fromMillisecondsSinceEpoch(
        l['scheduled_for']! as int,
      );
      final key =
          '$mid|${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
      logByKey[key] = l['status']! as String;
    }

    final out = <MedicationDoseSlot>[];
    for (final r in schedules) {
      List<String> times = const [];
      try {
        final decoded = jsonDecode(r['times_json'] as String? ?? '[]');
        if (decoded is List) {
          times = [for (final e in decoded) '$e'.trim()]
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {}
      final mid = r['medication_id']! as String;
      for (final hm in times) {
        final parts = hm.split(':');
        if (parts.length < 2) continue;
        final h = int.tryParse(parts[0]) ?? 0;
        final mi = int.tryParse(parts[1]) ?? 0;
        final scheduled = DateTime(day.year, day.month, day.day, h, mi);
        final key =
            '$mid|${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
        out.add(
          MedicationDoseSlot(
            medicationId: mid,
            name: r['name']! as String,
            kind: (r['kind'] as String?) ?? 'other',
            timeHm:
                '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}',
            scheduledFor: scheduled,
            strength: r['strength'] as String?,
            logStatus: logByKey[key],
          ),
        );
      }
    }
    out.sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    return out;
  }


  Future<void> deleteAllUserData() async {
    final db = userDb;
    await db.transaction((txn) async {
      for (final table in [
        'attachment',
        'visit',
        'reminder',
        'observation',
        'report',
        'condition',
        'allergy',
        'medication',
        'immunization',
        'procedure_record',
        'family_history',
        'emergency_contact',
        'profile',
      ]) {
        await txn.delete(table);
      }
    });
  }
}
