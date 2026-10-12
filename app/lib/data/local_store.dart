import 'dart:convert';
import 'dart:io';

import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'blob_vault.dart';
import 'care_store.dart';
import 'medical_store.dart';
import 'habits_notes_store.dart';
import 'legacy_container_migrate.dart';
import 'secure_keys.dart';
import 'models.dart';
import 'ref_range_suggestions.dart';
import 'panel_catalog.dart';
import '../features/import/lab_parse_quality.dart';

/// On-device persistence — SQLCipher user.db (ADR-001).
class LocalStore with MedicalStoreMixin, BlobVaultMixin, CareStoreMixin, HabitsNotesStoreMixin {
  LocalStore({SecureKeys? secureKeys})
      : secureKeys = secureKeys ?? SecureKeys();

  final _uuid = const Uuid();
  Database? _user;

  @override
  final SecureKeys secureKeys;

  @override
  Database get userDb => _user!;

  @override
  Uuid get uuid => _uuid;
  Database? _catalog;

  final List<ProfileRecord> profiles = [];
  final List<ReportRecord> reports = [];
  final List<ObservationRecord> observations = [];
  String? activeProfileId;

  Future<void> open() async {
    await migrateLegacyMacContainerIfNeeded();

    final dir = await getApplicationDocumentsDirectory();
    final userPath = p.join(dir.path, 'user.db');
    final plainMarker = File(p.join(dir.path, 'user.db.plain_migrated'));
    final userFile = File(userPath);

    // One-time wipe of M0 plaintext user.db before switching to SQLCipher.
    if (await userFile.exists() && !await plainMarker.exists()) {
      final header = await userFile.openRead(0, 16).first;
      final isPlain = String.fromCharCodes(header).startsWith('SQLite format 3');
      if (isPlain) {
        await userFile.delete();
        await plainMarker.writeAsString(
          'wiped plaintext user.db for SQLCipher ${DateTime.now().toIso8601String()}',
        );
      }
    }

    final password = await secureKeys.databasePassword();
    _user = await openDatabase(
      userPath,
      password: password,
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createUserSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS attachment (
  id TEXT PRIMARY KEY,
  owner_type TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  mime TEXT NOT NULL,
  byte_size INTEGER NOT NULL,
  page_count INTEGER,
  file_name TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_attachment_owner ON attachment(owner_type, owner_id)',
          );
        }
      },
    );

    final catalogPath = p.join(dir.path, 'catalog.db');
    final data = await rootBundle.load('assets/catalog/catalog.db');
    await File(catalogPath).writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    // Catalogue is unencrypted; empty password for SQLCipher opener.
    _catalog = await openDatabase(catalogPath, readOnly: true);

    await ensureMedicalTables();
    await ensureCareTables();
    await ensureHabitsNotesTables();
    await reload();
  }


  Future<void> close() async {
    await _user?.close();
    await _catalog?.close();
  }

  Future<void> reload() async {
    final db = _user!;
    final profileRows = await db.query(
      'profile',
      where: 'deleted = 0',
      orderBy: 'created_at ASC',
    );
    profiles
      ..clear()
      ..addAll(profileRows.map(ProfileRecord.fromRow));
    if (activeProfileId != null &&
        !profiles.any((p) => p.id == activeProfileId)) {
      activeProfileId = null;
    }
    if (activeProfileId == null && profiles.isNotEmpty) {
      activeProfileId = profiles.first.id;
    }

    final reportRows = await db.query(
      'report',
      where: 'deleted = 0',
      orderBy: 'collected_at ASC',
    );
    reports
      ..clear()
      ..addAll(reportRows.map((r) => ReportRecord(
            id: r['id']! as String,
            profileId: r['profile_id']! as String,
            title: (r['title'] as String?) ?? 'Report',
            collectedAt:
                DateTime.fromMillisecondsSinceEpoch(r['collected_at']! as int),
          )));

    final obsRows = await db.query(
      'observation',
      where: 'deleted = 0',
      orderBy: 'observed_at ASC',
    );
    final nameCache = <String, String>{};
    observations.clear();
    for (final r in obsRows) {
      final code = r['parameter_code']! as String;
      final name = await _parameterName(code, nameCache) ?? code;
      observations.add(
        ObservationRecord(
          id: r['id']! as String,
          profileId: r['profile_id']! as String,
          reportId: (r['report_id'] as String?) ?? '',
          parameterCode: code,
          parameterName: name,
          observedAt:
              DateTime.fromMillisecondsSinceEpoch(r['observed_at']! as int),
          valueReported: r['value_reported']! as String,
          unitReported: (r['unit_reported'] as String?) ?? '',
          valueNum: (r['value_num'] as num?)?.toDouble(),
          refLow: (r['ref_low'] as num?)?.toDouble(),
          refHigh: (r['ref_high'] as num?)?.toDouble(),
          refBands: decodeRefBandsJson(r['ref_bands_json'] as String?),
          flag: flagFromDb(r['flag'] as String?),
        ),
      );
    }
  }

  Future<String?> _parameterName(
    String code,
    Map<String, String> cache,
  ) async {
    if (cache.containsKey(code)) return cache[code];
    final rows = await _catalog!.query(
      'parameter',
      columns: ['name'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final name = rows.first['name']! as String;
    cache[code] = name;
    return name;
  }

  Future<ProfileRecord> createProfile({
    required String name,
    String relation = 'self',
    String? sex,
    String? dob,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    final hlc = '$now-0-local';
    final profile = ProfileRecord(
      id: id,
      name: name,
      relation: relation,
      sex: sex,
      dob: dob,
    );
    await _user!.insert('profile', profile.toRow(nowMs: now, hlc: hlc));
    await _user!.insert(
      'local_device',
      {'device_id': 'device-local', 'hlc_last': hlc},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    profiles.add(profile);
    activeProfileId ??= profile.id;
    return profile;
  }

  Future<ProfileRecord> updateProfile({
    required String id,
    String? name,
    String? relation,
    String? sex,
    String? dob,
    String? bloodGroup,
    bool clearSex = false,
    bool clearDob = false,
    bool clearBloodGroup = false,
  }) async {
    final i = profiles.indexWhere((p) => p.id == id);
    if (i < 0) {
      throw StateError('Profile not found');
    }
    final existing = profiles[i];
    final nextName = (name == null || name.trim().isEmpty) ? existing.name : name.trim();
    final updated = existing.copyWith(
      name: nextName,
      relation: relation,
      sex: sex,
      dob: dob,
      bloodGroup: bloodGroup,
      clearSex: clearSex,
      clearDob: clearDob,
      clearBloodGroup: clearBloodGroup,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = '$now-0-local';
    await _user!.update(
      'profile',
      {
        'name': updated.name,
        'relation': updated.relation,
        'sex': updated.sex,
        'dob': updated.dob,
        'blood_group': updated.bloodGroup,
        'updated_at': now,
        'hlc': hlc,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    profiles[i] = updated;
    return updated;
  }

  /// Soft-delete a family member. Blocks if this is the only profile.
  /// Related rows stay linked for history; lists filter deleted profiles.
  Future<void> softDeleteProfile(String id) async {
    if (profiles.length <= 1) {
      throw StateError('Cannot delete the only profile');
    }
    final i = profiles.indexWhere((p) => p.id == id);
    if (i < 0) {
      throw StateError('Profile not found');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = '$now-0-local';
    await _user!.update(
      'profile',
      {'deleted': 1, 'updated_at': now, 'hlc': hlc},
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
    profiles.removeAt(i);
    if (activeProfileId == id) {
      activeProfileId = profiles.isEmpty ? null : profiles.first.id;
    }
  }

  Future<ReportRecord?> addManualPanel({
    required String profileId,
    required String title,
    required DateTime collectedAt,
    required List<ManualObservationInput> values,
    String? reportId,
    String source = 'manual',
  }) async {
    final db = _user!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final collectedMs = collectedAt.millisecondsSinceEpoch;
    final id = reportId ?? _uuid.v4();
    final hlc = '$now-0-local';

    // Drop inputs already imported via external_id (Health Connect / HealthKit).
    final toInsert = <ManualObservationInput>[];
    for (final v in values) {
      if (v.externalId != null && v.externalId!.isNotEmpty) {
        final dup = await db.query(
          'observation',
          columns: ['id'],
          where: 'external_id = ? AND deleted = 0',
          whereArgs: [v.externalId],
          limit: 1,
        );
        if (dup.isNotEmpty) continue;
      }
      toInsert.add(v);
    }
    if (toInsert.isEmpty) return null;

    await db.transaction((txn) async {
      await txn.insert('report', {
        'id': id,
        'profile_id': profileId,
        'lab_id': null,
        'visit_id': null,
        'title': title,
        'collected_at': collectedMs,
        'reported_at': null,
        'source': source,
        'status': 'verified',
        'notes': null,
        'created_at': now,
        'updated_at': now,
        'hlc': hlc,
        'deleted': 0,
      });

      for (final v in toInsert) {
        final parsed = parseReportedValue(v.valueReported);
        final bands = v.refBands;
        var low = v.refLow;
        var high = v.refHigh;
        if (bands != null && bands.isNotEmpty) {
          final env = envelopeFromBands(bands);
          low ??= env.low;
          high ??= env.high;
        }
        final flag = computeFlagWithBands(
          value: parsed.numeric,
          refLow: low,
          refHigh: high,
          refBands: bands,
        );
        await txn.insert('observation', {
          'id': _uuid.v4(),
          'profile_id': profileId,
          'report_id': id,
          'parameter_code': v.parameterCode,
          'observed_at': collectedMs,
          'value_reported': v.valueReported,
          'unit_reported': v.unitReported,
          'comparator': parsed.comparator,
          'value_num': parsed.numeric,
          'value_text': parsed.text,
          'value_canonical': parsed.numeric,
          'unit_canonical': v.unitReported,
          'ref_low': low,
          'ref_high': high,
          'ref_text': null,
          'ref_bands_json': encodeRefBandsJson(bands),
          'ref_source':
              (low != null ||
                      high != null ||
                      (bands != null && bands.isNotEmpty))
                  ? 'lab'
                  : 'none',
          'flag': flagToDb(flag),
          'flag_source': flag == null ? null : 'computed',
          'source': v.source,
          'external_id': v.externalId,
          'ocr_confidence': null,
          'verified': 1,
          'group_id': null,
          'note': null,
          'created_at': now,
          'updated_at': now,
          'hlc': hlc,
          'deleted': 0,
        });
      }
    });

    await reload();
    return reports.firstWhere((r) => r.id == id);
  }

  /// Soft-delete a report and its observations / original files.
  Future<void> deleteReport(String reportId) async {
    final db = _user!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = '$now-0-local';
    await db.transaction((txn) async {
      await txn.update(
        'report',
        {'deleted': 1, 'updated_at': now, 'hlc': hlc},
        where: 'id = ? AND deleted = 0',
        whereArgs: [reportId],
      );
      await txn.update(
        'observation',
        {'deleted': 1, 'updated_at': now, 'hlc': hlc},
        where: 'report_id = ? AND deleted = 0',
        whereArgs: [reportId],
      );
      await txn.update(
        'attachment',
        {'deleted': 1, 'updated_at': now, 'hlc': hlc},
        where: "owner_type = 'report' AND owner_id = ? AND deleted = 0",
        whereArgs: [reportId],
      );
    });
    await reload();
  }

  /// Update a fetched / entered observation and recompute its flag.
  Future<void> updateObservation({
    required String id,
    required String valueReported,
    String? unitReported,
    double? refLow,
    double? refHigh,
    List<RefBand>? refBands,
    bool clearRefs = false,
    bool clearBands = false,
  }) async {
    final db = _user!;
    final i = observations.indexWhere((o) => o.id == id);
    if (i < 0) throw StateError('Observation not found');
    final existing = observations[i];
    final nextUnit = unitReported ?? existing.unitReported;
    var nextLow = clearRefs ? null : (refLow ?? existing.refLow);
    var nextHigh = clearRefs ? null : (refHigh ?? existing.refHigh);
    final nextBands = clearBands
        ? null
        : (refBands ?? existing.refBands);
    if (nextBands != null && nextBands.isNotEmpty) {
      final env = envelopeFromBands(nextBands);
      nextLow ??= env.low;
      nextHigh ??= env.high;
    }
    final parsed = parseReportedValue(valueReported.trim());
    final flag = computeFlagWithBands(
      value: parsed.numeric,
      refLow: nextLow,
      refHigh: nextHigh,
      refBands: nextBands,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = '$now-0-local';
    await db.update(
      'observation',
      {
        'value_reported': valueReported.trim(),
        'unit_reported': nextUnit,
        'comparator': parsed.comparator,
        'value_num': parsed.numeric,
        'value_text': parsed.text,
        'value_canonical': parsed.numeric,
        'unit_canonical': nextUnit,
        'ref_low': nextLow,
        'ref_high': nextHigh,
        'ref_bands_json': encodeRefBandsJson(nextBands),
        'ref_source':
            (nextLow != null ||
                    nextHigh != null ||
                    (nextBands != null && nextBands.isNotEmpty))
                ? 'lab'
                : 'none',
        'flag': flagToDb(flag),
        'flag_source': flag == null ? null : 'computed',
        'verified': 1,
        'updated_at': now,
        'hlc': hlc,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await reload();
  }

  /// Replace values on an existing manual/imported report (Edit values).
  ///
  /// [values] are the non-empty rows to keep. Existing observations for this
  /// report whose parameter is missing from [values] are soft-deleted.
  Future<void> updateManualPanel({
    required String reportId,
    required DateTime collectedAt,
    required List<ManualObservationInput> values,
  }) async {
    final db = _user!;
    final ri = reports.indexWhere((r) => r.id == reportId);
    if (ri < 0) throw StateError('Report not found');
    final report = reports[ri];
    final now = DateTime.now().millisecondsSinceEpoch;
    final collectedMs = collectedAt.millisecondsSinceEpoch;
    final hlc = '$now-0-local';

    final existing = observations
        .where((o) => o.reportId == reportId && !o.deleted)
        .toList();
    final byCode = <String, ObservationRecord>{
      for (final o in existing) o.parameterCode: o,
    };
    final keepCodes = {for (final v in values) v.parameterCode};

    await db.transaction((txn) async {
      await txn.update(
        'report',
        {
          'collected_at': collectedMs,
          'updated_at': now,
          'hlc': hlc,
        },
        where: 'id = ? AND deleted = 0',
        whereArgs: [reportId],
      );

      for (final o in existing) {
        if (keepCodes.contains(o.parameterCode)) continue;
        await txn.update(
          'observation',
          {'deleted': 1, 'updated_at': now, 'hlc': hlc},
          where: 'id = ? AND deleted = 0',
          whereArgs: [o.id],
        );
      }

      for (final v in values) {
        final parsed = parseReportedValue(v.valueReported);
        final bands = v.refBands;
        var low = v.refLow;
        var high = v.refHigh;
        if (bands != null && bands.isNotEmpty) {
          final env = envelopeFromBands(bands);
          low ??= env.low;
          high ??= env.high;
        }
        final flag = computeFlagWithBands(
          value: parsed.numeric,
          refLow: low,
          refHigh: high,
          refBands: bands,
        );
        final prev = byCode[v.parameterCode];
        if (prev != null) {
          await txn.update(
            'observation',
            {
              'observed_at': collectedMs,
              'value_reported': v.valueReported,
              'unit_reported': v.unitReported,
              'comparator': parsed.comparator,
              'value_num': parsed.numeric,
              'value_text': parsed.text,
              'value_canonical': parsed.numeric,
              'unit_canonical': v.unitReported,
              'ref_low': low,
              'ref_high': high,
              'ref_bands_json': encodeRefBandsJson(bands),
              'ref_source':
                  (low != null ||
                          high != null ||
                          (bands != null && bands.isNotEmpty))
                      ? 'lab'
                      : 'none',
              'flag': flagToDb(flag),
              'flag_source': flag == null ? null : 'computed',
              'verified': 1,
              'updated_at': now,
              'hlc': hlc,
            },
            where: 'id = ?',
            whereArgs: [prev.id],
          );
        } else {
          await txn.insert('observation', {
            'id': _uuid.v4(),
            'profile_id': report.profileId,
            'report_id': reportId,
            'parameter_code': v.parameterCode,
            'observed_at': collectedMs,
            'value_reported': v.valueReported,
            'unit_reported': v.unitReported,
            'comparator': parsed.comparator,
            'value_num': parsed.numeric,
            'value_text': parsed.text,
            'value_canonical': parsed.numeric,
            'unit_canonical': v.unitReported,
            'ref_low': low,
            'ref_high': high,
            'ref_text': null,
            'ref_bands_json': encodeRefBandsJson(bands),
            'ref_source':
                (low != null ||
                        high != null ||
                        (bands != null && bands.isNotEmpty))
                    ? 'lab'
                    : 'none',
            'flag': flagToDb(flag),
            'flag_source': flag == null ? null : 'computed',
            'source': 'manual',
            'external_id': null,
            'ocr_confidence': null,
            'verified': 1,
            'group_id': null,
            'note': null,
            'created_at': now,
            'updated_at': now,
            'hlc': hlc,
            'deleted': 0,
          });
        }
      }
    });

    await reload();
  }

  Future<List<Map<String, Object?>>> _activeTableRows(String table) async {
    return userDb.query(table, where: 'deleted = 0');
  }

  /// Full vault map for LAN sync (labs + care: doctors, visits, medicines, …).
  Future<Map<String, Object?>> exportVaultMap() async {
    return {
      'exported_at': DateTime.now().toIso8601String(),
      'format': 'bodyline-export-v1',
      'active_profile_id': activeProfileId,
      'profiles': [
        for (final pr in profiles)
          {
            'id': pr.id,
            'name': pr.name,
            'relation': pr.relation,
            'sex': pr.sex,
            'dob': pr.dob,
          },
      ],
      'reports': [
        for (final r in reports)
          {
            'id': r.id,
            'profile_id': r.profileId,
            'title': r.title,
            'collected_at': r.collectedAt.toIso8601String(),
          },
      ],
      'observations': [
        for (final o in observations)
          {
            'id': o.id,
            'profile_id': o.profileId,
            'report_id': o.reportId,
            'parameter_code': o.parameterCode,
            'parameter_name': o.parameterName,
            'observed_at': o.observedAt.toIso8601String(),
            'value_reported': o.valueReported,
            'unit_reported': o.unitReported,
            'value_num': o.valueNum,
            'ref_low': o.refLow,
            'ref_high': o.refHigh,
            'ref_bands_json': encodeRefBandsJson(o.refBands),
            'flag': flagToDb(o.flag),
          },
      ],
      'providers': await _activeTableRows('provider'),
      'visits': await _activeTableRows('visit'),
      'medications': await _activeTableRows('medication'),
      'medication_schedules': await _activeTableRows('medication_schedule'),
      'reminders': await _activeTableRows('reminder'),
      'conditions': await _activeTableRows('condition'),
      'allergies': await _activeTableRows('allergy'),
      'attachments': await _activeTableRows('attachment'),
      'blob_files': await _exportBlobFiles(),
      'habits': await _activeTableRows('habit'),
      'habit_logs': await _activeTableRows('habit_log'),
      'notes': await _activeTableRows('note'),
    };
  }

  /// Plain attachment bytes keyed by sha256 (outer LAN seal wraps the map).
  Future<Map<String, String>> _exportBlobFiles() async {
    final rows = await userDb.query(
      'attachment',
      columns: ['sha256'],
      where: 'deleted = 0',
    );
    final out = <String, String>{};
    for (final r in rows) {
      final sha = r['sha256'] as String?;
      if (sha == null || out.containsKey(sha)) continue;
      try {
        final att = AttachmentRecord(
          id: 'export',
          ownerType: 'export',
          ownerId: 'export',
          sha256: sha,
          mime: 'application/octet-stream',
          byteSize: 0,
        );
        final plain = await materializeAttachment(att);
        final bytes = await plain.readAsBytes();
        out[sha] = base64Encode(bytes);
        try {
          await plain.delete();
        } catch (_) {}
      } catch (_) {}
    }
    return out;
  }

  String? _mapProfileId(Map<String, String> idMap, String? remotePid) {
    if (remotePid == null) return null;
    return idMap[remotePid] ?? remotePid;
  }

  Future<int> _mergeTableById({
    required String table,
    required List? raw,
    required Set<String> existingIds,
    void Function(Map<String, Object?> row)? touch,
  }) async {
    var added = 0;
    for (final item in raw ?? const []) {
      final row = Map<String, Object?>.from(item as Map);
      final id = row['id'] as String?;
      if (id == null || existingIds.contains(id)) continue;
      touch?.call(row);
      await userDb.insert(table, row);
      existingIds.add(id);
      added++;
    }
    return added;
  }

  /// Merge a peer vault without wiping. Skips rows that already exist by id.
  Future<({
    int profilesAdded,
    int reportsAdded,
    int careRowsAdded,
  })> mergeFromExportJson(
    String jsonStr,
  ) async {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    if (map['format'] != 'bodyline-export-v1') {
      throw StateError('Not a Vitalog export');
    }
    var profilesAdded = 0;
    var reportsAdded = 0;
    final idMap = <String, String>{}; // remote profile id → local
    final remoteProfiles = (map['profiles'] as List?) ?? [];
    for (final raw in remoteProfiles) {
      final m = Map<String, dynamic>.from(raw as Map);
      final remoteId = m['id'] as String?;
      final name = (m['name'] as String?)?.trim() ?? 'Shared';
      if (remoteId == null) continue;
      ProfileRecord? local;
      for (final p in profiles) {
        if (p.id == remoteId || p.name.toLowerCase() == name.toLowerCase()) {
          local = p;
          break;
        }
      }
      if (local == null) {
        local = await createProfile(
          name: name,
          relation: m['relation'] as String? ?? 'other',
          sex: m['sex'] as String?,
          dob: m['dob'] as String?,
        );
        profilesAdded++;
      }
      idMap[remoteId] = local.id;
    }

    final existingReportIds = {for (final r in this.reports) r.id};
    final remoteObservations = (map['observations'] as List?) ?? [];
    final remoteReports = (map['reports'] as List?) ?? [];
    for (final raw in remoteReports) {
      final m = Map<String, dynamic>.from(raw as Map);
      final rid = m['id'] as String?;
      if (rid == null || existingReportIds.contains(rid)) continue;
      final remotePid = m['profile_id'] as String? ?? '';
      final localPid = idMap[remotePid] ?? activeProfileId;
      if (localPid == null) continue;
      final reportObs = [
        for (final o in remoteObservations)
          if ((o as Map)['report_id'] == rid)
            ManualObservationInput(
              parameterCode: o['parameter_code'] as String,
              parameterName:
                  o['parameter_name'] as String? ?? o['parameter_code'] as String,
              valueReported: o['value_reported'] as String? ?? '',
              unitReported: o['unit_reported'] as String? ?? '',
              refLow: (o['ref_low'] as num?)?.toDouble(),
              refHigh: (o['ref_high'] as num?)?.toDouble(),
              refBands: decodeRefBandsJson(o['ref_bands_json'] as String?),
            ),
      ];
      if (reportObs.isEmpty) continue;
      await addManualPanel(
        profileId: localPid,
        title: m['title'] as String? ?? 'Synced report',
        collectedAt:
            DateTime.tryParse(m['collected_at'] as String? ?? '') ??
                DateTime.now(),
        values: reportObs,
        reportId: rid,
        source: 'sync',
      );
      existingReportIds.add(rid);
      reportsAdded++;
    }

    var careRowsAdded = 0;
    final providerIds = {
      for (final r in await userDb.query('provider', columns: ['id']))
        r['id']! as String,
    };
    careRowsAdded += await _mergeTableById(
      table: 'provider',
      raw: map['providers'] as List?,
      existingIds: providerIds,
      touch: (row) {
        row['profile_id'] =
            _mapProfileId(idMap, row['profile_id'] as String?) ?? row['profile_id'];
      },
    );

    final visitIds = {
      for (final r in await userDb.query('visit', columns: ['id']))
        r['id']! as String,
    };
    careRowsAdded += await _mergeTableById(
      table: 'visit',
      raw: map['visits'] as List?,
      existingIds: visitIds,
      touch: (row) {
        row['profile_id'] =
            _mapProfileId(idMap, row['profile_id'] as String?) ?? row['profile_id'];
      },
    );

    final medicationIds = {
      for (final r in await userDb.query('medication', columns: ['id']))
        r['id']! as String,
    };
    careRowsAdded += await _mergeTableById(
      table: 'medication',
      raw: map['medications'] as List?,
      existingIds: medicationIds,
      touch: (row) {
        row['profile_id'] =
            _mapProfileId(idMap, row['profile_id'] as String?) ?? row['profile_id'];
      },
    );

    final scheduleIds = {
      for (final r in await userDb.query('medication_schedule', columns: ['id']))
        r['id']! as String,
    };
    careRowsAdded += await _mergeTableById(
      table: 'medication_schedule',
      raw: map['medication_schedules'] as List?,
      existingIds: scheduleIds,
    );

    final reminderIds = {
      for (final r in await userDb.query('reminder', columns: ['id']))
        r['id']! as String,
    };
    careRowsAdded += await _mergeTableById(
      table: 'reminder',
      raw: map['reminders'] as List?,
      existingIds: reminderIds,
      touch: (row) {
        row['profile_id'] =
            _mapProfileId(idMap, row['profile_id'] as String?) ?? row['profile_id'];
      },
    );

    final conditionIds = {
      for (final r in await userDb.query('condition', columns: ['id']))
        r['id']! as String,
    };
    careRowsAdded += await _mergeTableById(
      table: 'condition',
      raw: map['conditions'] as List?,
      existingIds: conditionIds,
      touch: (row) {
        row['profile_id'] =
            _mapProfileId(idMap, row['profile_id'] as String?) ?? row['profile_id'];
      },
    );

    final allergyIds = {
      for (final r in await userDb.query('allergy', columns: ['id']))
        r['id']! as String,
    };
    careRowsAdded += await _mergeTableById(
      table: 'allergy',
      raw: map['allergies'] as List?,
      existingIds: allergyIds,
      touch: (row) {
        row['profile_id'] =
            _mapProfileId(idMap, row['profile_id'] as String?) ?? row['profile_id'];
      },
    );

    final blobFiles = Map<String, String>.from(
      (map['blob_files'] as Map?)?.map(
            (k, v) => MapEntry('$k', '$v'),
          ) ??
          const {},
    );
    for (final e in blobFiles.entries) {
      try {
        final bytes = base64Decode(e.value);
        await ingestPlainBlob(sha256: e.key, bytes: bytes);
      } catch (_) {}
    }

    final attachmentIds = {
      for (final r in await userDb.query('attachment', columns: ['id']))
        r['id']! as String,
    };
    careRowsAdded += await _mergeTableById(
      table: 'attachment',
      raw: map['attachments'] as List?,
      existingIds: attachmentIds,
    );

    for (final table in ['habit', 'habit_log', 'note']) {
      final ids = {
        for (final r in await userDb.query(table, columns: ['id']))
          r['id']! as String,
      };
      final key = table == 'habit_log'
          ? 'habit_logs'
          : table == 'note'
              ? 'notes'
              : 'habits';
      careRowsAdded += await _mergeTableById(
        table: table,
        raw: map[key] as List?,
        existingIds: ids,
        touch: table == 'habit_log' || table == 'habit' || table == 'note'
            ? (row) {
                row['profile_id'] = _mapProfileId(
                      idMap,
                      row['profile_id'] as String?,
                    ) ??
                    row['profile_id'];
              }
            : null,
      );
    }

    await reload();
    return (
      profilesAdded: profilesAdded,
      reportsAdded: reportsAdded,
      careRowsAdded: careRowsAdded,
    );
  }

  List<ObservationRecord> trendFor(String profileId, String parameterCode) {
    final rows = observations
        .where((o) =>
            o.profileId == profileId &&
            o.parameterCode == parameterCode &&
            !o.deleted)
        .toList()
      ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
    return rows;
  }

  /// Observations for [parameterCode] across the family vault.
  /// Active [profileId] rows first so their ranges rank higher in suggestions.
  List<ObservationRecord> _familyParamHistory(
    String profileId,
    String parameterCode,
  ) {
    final own = <ObservationRecord>[];
    final others = <ObservationRecord>[];
    for (final o in observations) {
      if (o.deleted || o.parameterCode != parameterCode) continue;
      if (o.profileId == profileId) {
        own.add(o);
      } else {
        others.add(o);
      }
    }
    own.sort((a, b) => a.observedAt.compareTo(b.observedAt));
    others.sort((a, b) => a.observedAt.compareTo(b.observedAt));
    return [...own, ...others];
  }

  /// Distinct historical (ref_low, ref_high) pairs for this test across family,
  /// most frequent first (active profile weighted first). ADR-006: autofill only when empty.
  List<RefRangeSuggestion> refRangeSuggestions(
    String profileId,
    String parameterCode,
  ) {
    return buildRefRangeSuggestions([
      for (final o in _familyParamHistory(profileId, parameterCode))
        RefRangeHistoryRow(
          refLow: o.refLow,
          refHigh: o.refHigh,
          unit: o.unitReported,
        ),
    ]);
  }

  /// Distinct historical band sets across family, most frequent first.
  /// ADR-006: callers must only autofill when current bands + Low/High are empty.
  List<RefBandSetSuggestion> refBandSetSuggestions(
    String profileId,
    String parameterCode,
  ) {
    return buildRefBandSetSuggestions([
      for (final o in _familyParamHistory(profileId, parameterCode))
        RefBandSetHistoryRow(
          refBands: o.refBands,
          unit: o.unitReported,
        ),
    ]);
  }


  Future<void> switchProfile(String id) async {
    if (profiles.any((p) => p.id == id)) {
      activeProfileId = id;
    }
  }

  /// Latest flag per body_system.code for the active profile (null = untested).

  int flaggedCountForReport(String reportId) {
    return observations
        .where((o) =>
            o.reportId == reportId &&
            o.flag != null &&
            o.flag != ObservationFlag.normal)
        .length;
  }

  Future<String?> systemNameForParameter(String parameterCode) async {
    final code = await systemForParameter(parameterCode);
    if (code == null) return null;
    final rows = await _catalog!.query(
      'body_system',
      columns: ['name'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['name'] as String?;
  }

  Future<Map<String, ObservationFlag?>> organFlags() async {
    final profileId = activeProfileId;
    if (profileId == null || _catalog == null) return {};

    final systems = await _catalog!.query(
      'body_system',
      orderBy: 'sort_order ASC',
    );
    final links = await _catalog!.query('parameter_system');
    final bySystem = <String, List<String>>{};
    for (final row in links) {
      final sc = row['system_code']! as String;
      final pc = row['parameter_code']! as String;
      bySystem.putIfAbsent(sc, () => []).add(pc);
    }

    // latest observation per parameter for profile
    final latest = <String, ObservationRecord>{};
    for (final o in observations) {
      if (o.profileId != profileId || o.deleted) continue;
      final prev = latest[o.parameterCode];
      if (prev == null || o.observedAt.isAfter(prev.observedAt)) {
        latest[o.parameterCode] = o;
      }
    }

    ObservationFlag? worst(Iterable<ObservationFlag?> flags) {
      ObservationFlag? out;
      for (final f in flags) {
        if (f == null || f == ObservationFlag.normal) {
          out ??= f == ObservationFlag.normal ? ObservationFlag.normal : out;
          if (f == ObservationFlag.normal && out == null) out = f;
          continue;
        }
        // any abnormal wins over normal; high/low both "attention"
        if (out == null || out == ObservationFlag.normal) out = f;
      }
      // if we only saw normals
      final nonNull = flags.whereType<ObservationFlag>().toList();
      if (nonNull.isEmpty) return null;
      if (nonNull.any((f) =>
          f == ObservationFlag.high ||
          f == ObservationFlag.low ||
          f == ObservationFlag.criticalHigh ||
          f == ObservationFlag.criticalLow ||
          f == ObservationFlag.abnormal)) {
        return nonNull.firstWhere(
          (f) => f != ObservationFlag.normal,
          orElse: () => ObservationFlag.abnormal,
        );
      }
      return ObservationFlag.normal;
    }

    final result = <String, ObservationFlag?>{};
    for (final s in systems) {
      final code = s['code']! as String;
      final params = bySystem[code] ?? const [];
      if (params.isEmpty) {
        result[code] = null;
        continue;
      }
      final flags = params.map((pc) => latest[pc]?.flag);
      if (flags.every((f) => f == null) &&
          params.every((pc) => !latest.containsKey(pc))) {
        result[code] = null;
      } else {
        result[code] = worst(flags);
      }
    }
    return result;
  }

  Future<List<({String code, String name})>> bodySystems() async {
    final rows = await _catalog!.query(
      'body_system',
      orderBy: 'sort_order ASC',
    );
    return [
      for (final r in rows)
        (code: r['code']! as String, name: r['name']! as String)
    ];
  }

  Future<String?> systemForParameter(String parameterCode) async {
    final rows = await _catalog!.query(
      'parameter_system',
      where: 'parameter_code = ?',
      whereArgs: [parameterCode],
      orderBy: 'relevance ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['system_code'] as String?;
  }


  /// Systems with display name + rollup flag + high/low counts for the active profile.
  Future<List<OrganSummary>> organSummaries() async {
    final profileId = activeProfileId;
    final systems = await bodySystems();
    if (profileId == null) {
      return [
        for (final s in systems)
          OrganSummary(code: s.code, name: s.name, flag: null, highCount: 0, lowCount: 0),
      ];
    }

    final links = await _catalog!.query('parameter_system');
    final bySystem = <String, List<String>>{};
    for (final row in links) {
      bySystem
          .putIfAbsent(row['system_code']! as String, () => [])
          .add(row['parameter_code']! as String);
    }

    final latest = <String, ObservationRecord>{};
    for (final o in observations) {
      if (o.profileId != profileId || o.deleted) continue;
      final prev = latest[o.parameterCode];
      if (prev == null || o.observedAt.isAfter(prev.observedAt)) {
        latest[o.parameterCode] = o;
      }
    }

    ObservationFlag? rollup(List<ObservationFlag> flags) {
      if (flags.isEmpty) return null;
      if (flags.any((f) =>
          f == ObservationFlag.high ||
          f == ObservationFlag.criticalHigh ||
          f == ObservationFlag.abnormal)) {
        return ObservationFlag.high;
      }
      if (flags.any((f) =>
          f == ObservationFlag.low || f == ObservationFlag.criticalLow)) {
        return ObservationFlag.low;
      }
      return ObservationFlag.normal;
    }

    final out = <OrganSummary>[];
    for (final s in systems) {
      // Skip parent-only endocrine if thyroid is listed separately
      if (s.code == 'endocrine') continue;
      final params = bySystem[s.code] ?? const <String>[];
      final flags = <ObservationFlag>[];
      var high = 0;
      var low = 0;
      for (final code in params) {
        final o = latest[code];
        if (o?.flag == null) continue;
        flags.add(o!.flag!);
        if (o.flag == ObservationFlag.high ||
            o.flag == ObservationFlag.criticalHigh ||
            o.flag == ObservationFlag.abnormal) {
          high++;
        } else if (o.flag == ObservationFlag.low ||
            o.flag == ObservationFlag.criticalLow) {
          low++;
        }
      }
      out.add(
        OrganSummary(
          code: s.code,
          name: s.name,
          flag: params.any(latest.containsKey) ? rollup(flags) : null,
          highCount: high,
          lowCount: low,
        ),
      );
    }
    return out;
  }

  Future<void> _createUserSchema(Database db) async {
    await db.execute('''
CREATE TABLE profile (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  relation TEXT NOT NULL DEFAULT 'self',
  sex TEXT,
  dob TEXT,
  blood_group TEXT,
  color TEXT,
  is_primary INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE report (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profile(id),
  lab_id TEXT,
  visit_id TEXT,
  title TEXT,
  collected_at INTEGER NOT NULL,
  reported_at INTEGER,
  source TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft',
  notes TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE observation (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profile(id),
  report_id TEXT REFERENCES report(id),
  parameter_code TEXT NOT NULL,
  observed_at INTEGER NOT NULL,
  value_reported TEXT NOT NULL,
  unit_reported TEXT,
  comparator TEXT,
  value_num REAL,
  value_text TEXT,
  value_canonical REAL,
  unit_canonical TEXT,
  ref_low REAL,
  ref_high REAL,
  ref_text TEXT,
  ref_bands_json TEXT,
  ref_source TEXT NOT NULL DEFAULT 'none',
  flag TEXT,
  flag_source TEXT,
  source TEXT NOT NULL,
  external_id TEXT,
  ocr_confidence REAL,
  verified INTEGER NOT NULL DEFAULT 0,
  group_id TEXT,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute(
      'CREATE INDEX idx_obs_trend ON observation(profile_id, parameter_code, observed_at)',
    );
    await db.execute('''
CREATE TABLE attachment (
  id TEXT PRIMARY KEY,
  owner_type TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  mime TEXT NOT NULL,
  byte_size INTEGER NOT NULL,
  page_count INTEGER,
  file_name TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute(
      'CREATE INDEX idx_attachment_owner ON attachment(owner_type, owner_id)',
    );

    await db.execute('''
CREATE TABLE local_device (
  device_id TEXT PRIMARY KEY,
  hlc_last TEXT NOT NULL
)''');
  }

  Future<File> exportJsonArchive() async {
    final pid = activeProfileId;
    final payload = <String, Object?>{
      'exported_at': DateTime.now().toIso8601String(),
      'format': 'bodyline-export-v1',
      'active_profile_id': pid,
      'profiles': [
        for (final pr in profiles)
          {
            'id': pr.id,
            'name': pr.name,
            'relation': pr.relation,
            'sex': pr.sex,
            'dob': pr.dob,
          },
      ],
      'reports': [
        for (final r in reports)
          {
            'id': r.id,
            'profile_id': r.profileId,
            'title': r.title,
            'collected_at': r.collectedAt.toIso8601String(),
          },
      ],
      'observations': [
        for (final o in observations)
          {
            'id': o.id,
            'profile_id': o.profileId,
            'report_id': o.reportId,
            'parameter_code': o.parameterCode,
            'parameter_name': o.parameterName,
            'observed_at': o.observedAt.toIso8601String(),
            'value_reported': o.valueReported,
            'unit_reported': o.unitReported,
            'value_num': o.valueNum,
            'ref_low': o.refLow,
            'ref_high': o.refHigh,
            'ref_bands_json': encodeRefBandsJson(o.refBands),
            'flag': flagToDb(o.flag),
          },
      ],
    };

    if (pid != null) {
      payload['conditions'] = [
        for (final i in await listConditions(pid))
          {'id': i.id, 'title': i.title, 'subtitle': i.subtitle},
      ];
      payload['medications'] = [
        for (final i in await listMedications(pid))
          {'id': i.id, 'title': i.title, 'subtitle': i.subtitle},
      ];
      payload['allergies'] = [
        for (final i in await listAllergies(pid))
          {'id': i.id, 'title': i.title, 'subtitle': i.subtitle},
      ];
    }

    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(
        dir.path,
        'bodyline-export-${DateTime.now().millisecondsSinceEpoch}.json',
      ),
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    return file;
  }

  Future<File> exportObservationsCsv() async {
    final buf = StringBuffer(
      'profile_id,report_id,parameter_code,parameter_name,observed_at,value,unit,ref_low,ref_high,flag\n',
    );
    String esc(String? s) {
      final v = s ?? '';
      if (v.contains(',') || v.contains('"') || v.contains('\n')) {
        return '"${v.replaceAll('"', '""')}"';
      }
      return v;
    }

    for (final o in observations) {
      buf.writeln([
        esc(o.profileId),
        esc(o.reportId),
        esc(o.parameterCode),
        esc(o.parameterName),
        esc(o.observedAt.toIso8601String()),
        esc(o.valueReported),
        esc(o.unitReported),
        o.refLow?.toString() ?? '',
        o.refHigh?.toString() ?? '',
        esc(flagToDb(o.flag)),
      ].join(','));
    }
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(
        dir.path,
        'bodyline-observations-${DateTime.now().millisecondsSinceEpoch}.csv',
      ),
    );
    await file.writeAsString(buf.toString(), flush: true);
    return file;
  }


  /// Catalogue default Low/High for a parameter (adult). Prefer sex-specific, else `any`.
  Future<({double? low, double? high})?> defaultRefRange(
    String parameterCode, {
    String? sex,
  }) async {
    if (_catalog == null) return null;
    final code = parameterCode.trim();
    if (code.isEmpty) return null;
    final sexKey = (sex == 'M' || sex == 'F') ? sex! : null;
    Future<Map<String, Object?>?> pick(String s) async {
      final rows = await _catalog!.query(
        'default_ref_range',
        where: 'parameter_code = ? AND sex = ?',
        whereArgs: [code, s],
        orderBy: 'age_min_days DESC',
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    }

    Map<String, Object?>? row;
    if (sexKey != null) row = await pick(sexKey);
    row ??= await pick('any');
    if (row == null) return null;
    return (
      low: (row['low'] as num?)?.toDouble(),
      high: (row['high'] as num?)?.toDouble(),
    );
  }

    Future<List<PanelDef>> catalogPanels() async {
    final panels = await _catalog!.query('panel', orderBy: 'name ASC');
    final out = <PanelDef>[];
    for (final row in panels) {
      final code = row['code']! as String;
      final name = row['name']! as String;
      final links = await _catalog!.query(
        'panel_parameter',
        where: 'panel_code = ?',
        whereArgs: [code],
        orderBy: 'position ASC',
      );
      final params = <ParamDef>[];
      for (final link in links) {
        final pc = link['parameter_code']! as String;
        final prow = await _catalog!.query(
          'parameter',
          where: 'code = ?',
          whereArgs: [pc],
          limit: 1,
        );
        if (prow.isEmpty) continue;
        final fullName = prow.first['name']! as String;
        final short = (prow.first['short_name'] as String?)?.trim();
        params.add(
          ParamDef(
            pc,
            fullName,
            (prow.first['canonical_unit'] as String?) ?? '',
            shortName: (short != null && short.isNotEmpty) ? short : null,
          ),
        );
      }
      if (params.isNotEmpty) {
        out.add(PanelDef(code, name, params));
      }
    }
    return out;
  }

  /// Search on-device catalogue by name / short name / code (manual one-test entry).
  Future<ParamDef?> catalogParameter(String code) async {
    if (_catalog == null) return null;
    final c = code.trim();
    if (c.isEmpty) return null;
    final rows = await _catalog!.query(
      'parameter',
      where: 'code = ?',
      whereArgs: [c],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final short = (r['short_name'] as String?)?.trim();
    return ParamDef(
      r['code']! as String,
      r['name']! as String,
      (r['canonical_unit'] as String?) ?? '',
      shortName: (short != null && short.isNotEmpty) ? short : null,
    );
  }

  Future<List<ParamDef>> searchCatalogParameters(String query, {int limit = 40}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final rows = await _catalog!.query('parameter');
    final out = <ParamDef>[];
    for (final r in rows) {
      final code = r['code']! as String;
      final name = r['name']! as String;
      final short = (r['short_name'] as String?) ?? '';
      final unit = (r['canonical_unit'] as String?) ?? '';
      final hay = '$code $name $short'.toLowerCase();
      if (!hay.contains(q)) continue;
      out.add(
        ParamDef(
          code,
          name,
          unit,
          shortName: short.isNotEmpty ? short : null,
        ),
      );
      if (out.length >= limit) break;
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// Match free text (OCR / paste) to catalogue aliases. Best-effort.
  /// Handles same-line rows, dotted leaders, and Syncfusion stacks where the
  /// value (and unit) may sit a few lines below the test name.
  Future<List<ParsedLabLine>> parseLabText(
    String raw, {
    String? bandsSource,
  }) async {
    final aliases = await _catalog!.query('parameter_alias');
    final byAlias = <String, List<String>>{};
    void putAlias(String a, String code) {
      if (a.length < 2) return;
      final list = byAlias.putIfAbsent(a, () => <String>[]);
      if (!list.contains(code)) list.add(code);
    }

    for (final r in aliases) {
      putAlias(r['alias_norm']! as String, r['parameter_code']! as String);
    }
    final params = await _catalog!.query('parameter');
    final names = <String, String>{};
    final units = <String, String>{};
    for (final r in params) {
      final code = r['code']! as String;
      names[code] = r['name']! as String;
      units[code] = (r['canonical_unit'] as String?) ?? '';
      final shortNorm = _norm((r['short_name'] as String?) ?? '');
      putAlias(shortNorm, code);
      putAlias(code, code);
      putAlias(_norm(r['name']! as String), code);
    }

    // Longer aliases first for contains-token matching.
    final aliasList = byAlias.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    String? resolveCode(String label, {String unit = ''}) {
      final normLabel = _norm(label);
      if (normLabel.isEmpty || _noiseLabels.contains(normLabel)) return null;

      final keys = <String>{
        normLabel,
        ..._aliasKeysFromLabel(label),
      };
      final hits = <MapEntry<String, String>>[];
      for (final k in keys) {
        if (k.length < 2) continue;
        final codes = byAlias[k];
        if (codes == null) continue;
        for (final code in codes) {
          hits.add(MapEntry(k, code));
        }
      }

      // Soft: long alias (≥5) as prefix/suffix of a short PDF label (not prose).
      if (hits.isEmpty && normLabel.length >= 5) {
        for (final a in aliasList) {
          if (a.length < 5) break;
          if (!softAliasLengthOk(normLabel, a)) continue;
          if (normLabel == a ||
              normLabel.startsWith(a) ||
              normLabel.endsWith(a)) {
            for (final code in byAlias[a]!) {
              hits.add(MapEntry(a, code));
            }
            break;
          }
        }
      }

      if (hits.isEmpty) return null;
      hits.sort((a, b) => b.key.length.compareTo(a.key.length));
      final topLen = hits.first.key.length;
      final top = [
        for (final h in hits)
          if (h.key.length == topLen) h.value,
      ].toSet().toList();
      if (top.length == 1) return top.first;
      return _pickByUnit(top, unit, units) ??
          _pickPctCollision(top, unit) ??
          top.first;
    }

    final out = <ParsedLabLine>[];
    final hitScores = <String, int>{};
    void addHit({
      required String code,
      required String value,
      String unit = '',
      double? low,
      double? high,
      List<RefBand>? bands,
      required String sourceLine,
      required int page,
    }) {
      if (isEducationalProse(sourceLine)) return;
      if (isAccessionLikeValue(value, unit: unit)) return;
      if (isAmbiguousUrineBloodHit(
        parameterCode: code,
        sourceLine: sourceLine,
        unit: unit,
      )) {
        return;
      }
      final catalogUnit = units[code] ?? '';
      if (unit.isNotEmpty &&
          catalogUnit.isNotEmpty &&
          !labUnitsCompatible(unit, catalogUnit)) {
        return;
      }
      final score = labHitScore(
        sourceLine: sourceLine,
        value: value,
        unit: unit,
        refLow: low,
        refHigh: high,
        catalogUnit: catalogUnit,
      );
      // Reject clearly bad hits (prose/ID) even if somehow scored.
      if (score < -40) return;
      final refined = _refineThyroidCode(code, unit);
      final key = '$page::$refined';
      final candidate = ParsedLabLine(
        parameterCode: refined,
        parameterName: names[refined] ?? refined,
        valueReported: value.replaceAll(RegExp(r'[<>]'), '').trim(),
        unitReported: unit.isNotEmpty ? unit : (units[refined] ?? ''),
        refLow: low,
        refHigh: high,
        refBands: bands,
        sourceLine: sourceLine,
        pageIndex: page,
      );
      final existing = hitScores[key];
      if (existing != null) {
        final prev = out.indexWhere(
          (p) => p.pageIndex == page && p.parameterCode == refined,
        );
        if (prev >= 0) {
          final prevLine = out[prev];
          final replace = shouldReplaceLabHit(
            existingScore: existing,
            candidateScore: score,
            candidateHasUnitOrRange: unit.isNotEmpty ||
                low != null ||
                high != null ||
                (bands != null && bands.isNotEmpty),
            existingHasUnitOrRange: prevLine.unitReported.isNotEmpty ||
                prevLine.refLow != null ||
                prevLine.refHigh != null ||
                (prevLine.refBands != null && prevLine.refBands!.isNotEmpty),
          );
          if (!replace) return;
          out[prev] = candidate;
          hitScores[key] = score;
          return;
        }
      }
      hitScores[key] = score;
      out.add(candidate);
    }

    final cleaned = stripInterpretationBlocks(detachHlFlags(raw));
    final lines = [
      for (final line in cleaned.split(RegExp(r'[\r\n]+')))
        if (line.trim().isNotEmpty && !isEducationalProse(line.trim()))
          line.trim(),
    ];

    final pageMarker = RegExp(r'^--- page (\d+)', caseSensitive: false);
    final rangeOnly = RegExp(
      r'^(\d+(?:\.\d+)?)\s*[-–to]+\s*(\d+(?:\.\d+)?)\s*$',
      caseSensitive: false,
    );
    // Value, optional unit, optional range — all on one line.
    // Allow trailing H/L flags left after imperfect normalize.
    final valueUnitRe = RegExp(
      r'^([<>]?\d+(?:\.\d+)?)\s*(?:[HL]\*?)?\s*'
      r'([A-Za-z/%µμ][A-Za-z0-9/%µμ^.\-]*)?\s*'
      r'(?:'
      r'[\(\[]?\s*(\d+(?:\.\d+)?)\s*[-–to]+\s*(\d+(?:\.\d+)?)[\)\]]?|'
      r'up\s*to\s*(\d+(?:\.\d+)?)|'
      r'<\s*(\d+(?:\.\d+)?)'
      r')?\s*$',
      caseSensitive: false,
    );
    final valueOnly = RegExp(
      r'^([<>]?\d+(?:\.\d+)?)\s*(?:[HL]\*?)?\s*$',
      caseSensitive: false,
    );
    final unitOnly = RegExp(r'^[A-Za-z/%µμ][A-Za-z0-9/%µμ^.\-]*$');

    // 1) Same-line name + value
    // Agilus: name · result · range · units  OR classic: name · value · unit · range
    // Label charset (in lab_parse_quality) includes `:` for Redcliffe A/G rows.
    var currentPage = 1;
    for (final trimmed in lines) {
      final pm = pageMarker.firstMatch(trimmed);
      if (pm != null) {
        currentPage = int.tryParse(pm.group(1)!) ?? currentPage;
        continue;
      }
      if (_looksLikeRangeOnly(trimmed)) continue;
      final mRu = matchSameLineRangeUnitLabRow(trimmed);
      if (mRu != null) {
        if (isEducationalProse(mRu.label) || isEducationalProse(trimmed)) continue;
        final code = resolveCode(mRu.label, unit: mRu.unit);
        if (code == null) continue;
        addHit(
          code: code,
          value: mRu.value,
          unit: mRu.unit,
          low: mRu.refLow,
          high: mRu.refHigh,
          sourceLine: trimmed,
          page: currentPage,
        );
        continue;
      }
      final m = matchSameLineLabRow(trimmed);
      if (m == null) continue;
      if (isEducationalProse(m.label) || isEducationalProse(trimmed)) continue;
      final code = resolveCode(m.label, unit: m.unit);
      if (code == null) continue;
      addHit(
        code: code,
        value: m.value,
        unit: m.unit,
        low: m.refLow,
        high: m.refHigh,
        sourceLine: trimmed,
        page: currentPage,
      );
    }

    // 2) Dotted leaders
    currentPage = 1;
    for (final trimmed in lines) {
      final pm = pageMarker.firstMatch(trimmed);
      if (pm != null) {
        currentPage = int.tryParse(pm.group(1)!) ?? currentPage;
        continue;
      }
      final m = matchDottedLabRow(trimmed);
      if (m == null) continue;
      if (isEducationalProse(trimmed)) continue;
      final code = resolveCode(m.label, unit: m.unit);
      if (code == null) continue;
      addHit(
        code: code,
        value: m.value,
        unit: m.unit,
        sourceLine: trimmed,
        page: currentPage,
      );
    }

    // 3) Stacked: label, then value[/unit] within following lines
    // Value lines are consumed so two analytes cannot both borrow Bilirubin’s 0.7.
    currentPage = 1;
    final consumedValueLines = <int>{};
    for (var i = 0; i < lines.length; i++) {
      final label = lines[i];
      final pm = pageMarker.firstMatch(label);
      if (pm != null) {
        currentPage = int.tryParse(pm.group(1)!) ?? currentPage;
        continue;
      }
      if (valueOnly.hasMatch(label) ||
          valueUnitRe.hasMatch(label) ||
          rangeOnly.hasMatch(label)) {
        continue;
      }
      if (unitOnly.hasMatch(label) && label.length <= 10) continue;
      if (looksLikeSameLineLabRow(label)) continue;
      if (isEducationalProse(label)) continue;
      // Stacked labels should be short analyte names, not sentences.
      if (label.length > 60) continue;

      final codeEarly = resolveCode(label);
      if (codeEarly == null) continue;

      String? value;
      var unit = '';
      double? low;
      double? high;
      var valueAt = -1;

      for (var k = 1; k <= kStackedValueLookahead && i + k < lines.length; k++) {
        final peek = lines[i + k];
        if (pageMarker.hasMatch(peek)) break;
        if (isEducationalProse(peek)) break;
        if (consumedValueLines.contains(i + k)) continue;

        // Another catalogue label before/at the next line → stop (do not skip
        // over SGPT to steal SGOT’s value).
        if (resolveCode(peek) != null &&
            valueUnitRe.firstMatch(peek) == null &&
            valueOnly.firstMatch(peek) == null) {
          break;
        }

        final vu = valueUnitRe.firstMatch(peek);
        if (vu != null) {
          final cand = vu.group(1)!.replaceAll(RegExp(r'\s'), '');
          final candUnit = (vu.group(2) ?? '').trim();
          if (isAccessionLikeValue(cand, unit: candUnit)) {
            // Keep scanning — ID may sit between label and real value.
            continue;
          }
          value = cand;
          unit = candUnit;
          low = double.tryParse(vu.group(3) ?? '');
          high = double.tryParse(vu.group(4) ?? '');
          // "up to 40" → high only; "<1.00" → high only.
          if (low == null && high == null) {
            final upTo = double.tryParse(vu.group(5) ?? '');
            final lt = double.tryParse(vu.group(6) ?? '');
            if (upTo != null) high = upTo;
            if (lt != null) high = lt;
          }
          valueAt = i + k;
          break;
        }
        final vo = valueOnly.firstMatch(peek);
        if (vo != null) {
          final cand = vo.group(1)!.replaceAll(RegExp(r'\s'), '');
          if (isAccessionLikeValue(cand)) {
            continue;
          }
          value = cand;
          valueAt = i + k;
          break;
        }
      }
      if (value == null || valueAt < 0) continue;

      var j = valueAt + 1;
      // Dimensionless "-" unit column (A/G ratio) before the reference range.
      if (unit.isEmpty &&
          j < lines.length &&
          RegExp(r'^[-–—−]$').hasMatch(lines[j].trim())) {
        j++;
      }
      if (unit.isEmpty &&
          j < lines.length &&
          unitOnly.hasMatch(lines[j]) &&
          !valueOnly.hasMatch(lines[j]) &&
          !rangeOnly.hasMatch(lines[j])) {
        final maybeUnit = lines[j];
        if (!isAccessionLikeValue(value, unit: maybeUnit)) {
          unit = maybeUnit;
          j++;
        } else {
          j++; // skip accession-looking "unit" line
          if (j < lines.length &&
              unitOnly.hasMatch(lines[j]) &&
              !valueOnly.hasMatch(lines[j]) &&
              !rangeOnly.hasMatch(lines[j])) {
            unit = lines[j];
            j++;
          }
        }
      }
      if (low == null && j < lines.length) {
        final rm = rangeOnly.firstMatch(lines[j]);
        if (rm != null) {
          low = double.tryParse(rm.group(1)!);
          high = double.tryParse(rm.group(2)!);
          j++;
        }
      }
      // Agilus: value → range → units (unit sits after the ref interval).
      if (unit.isEmpty &&
          j < lines.length &&
          unitOnly.hasMatch(lines[j]) &&
          !valueOnly.hasMatch(lines[j]) &&
          !rangeOnly.hasMatch(lines[j])) {
        final maybeUnit = lines[j];
        if (!isAccessionLikeValue(value, unit: maybeUnit)) {
          unit = maybeUnit;
          j++;
        }
      }

      if (isAccessionLikeValue(value, unit: unit)) continue;

      unit = sanitizeReportedLabUnit(unit);
      final code = resolveCode(label, unit: unit) ?? codeEarly;
      // Mark value (+ optional unit/range) consumed so GGT cannot reuse them.
      consumedValueLines.add(valueAt);
      for (var c = valueAt + 1; c < j && c < lines.length; c++) {
        consumedValueLines.add(c);
      }
      addHit(
        code: code,
        value: value,
        unit: unit,
        low: low,
        high: high,
        sourceLine: label,
        page: currentPage,
      );
    }

    // Best-effort: attach multi-stage bands from pre-collapse biological blobs.
    // OCR imperfect is OK — manual Stages remains the floor (ADR-003/006).
    final bandMap = extractBiologicalRefBandsByLabel(
      prepTextForBiologicalBandExtract(bandsSource ?? raw),
    );
    if (bandMap.isNotEmpty) {
      for (var i = 0; i < out.length; i++) {
        final line = out[i];
        if (line.refBands != null && line.refBands!.isNotEmpty) continue;
        final bands = lookupBiologicalRefBands(
          bandMap,
          parameterName: line.parameterName,
          parameterCode: line.parameterCode,
          sourceLine: line.sourceLine,
        );
        if (bands == null || bands.length < 2) continue;
        final env = envelopeFromBands(bands);
        out[i] = line.copyWith(
          refBands: bands,
          refLow: line.refLow ?? env.low,
          refHigh: line.refHigh ?? env.high,
        );
      }
    }

    // Dedup already applied in addHit via scores; sort for stable UI.
    return out
      ..sort((a, b) {
        final c = a.pageIndex.compareTo(b.pageIndex);
        if (c != 0) return c;
        return a.parameterName.compareTo(b.parameterName);
      });
  }

  static const _noiseLabels = {
    'test', 'tests', 'result', 'results', 'unit', 'units', 'range', 'ref',
    'reference', 'method', 'page', 'patient', 'doctor', 'sample', 'collected',
    'reported', 'investigation', 'parameter', 'observed', 'biological',
    'download', 'report', 'lab', 'laboratory', 'specimen', 'technology',
    'interpretation', 'note', 'notes', 'end', 'of', 'the', 'and', 'for',
    'name', 'age', 'sex', 'male', 'female', 'mr', 'mrs', 'ms', 'dr',
    'value', 'values', 'normal', 'low', 'high', 'status', 'print',
  };

  /// Catalogue uses British spelling; lab PDFs often use American.
  String _norm(String s) {
    var n = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    n = n.replaceAll('hemoglobin', 'haemoglobin');
    n = n.replaceAll('hematocrit', 'haematocrit');
    return n;
  }

  Iterable<String> _aliasKeysFromLabel(String label) sync* {
    yield _norm(label);
    final paren = RegExp(r'\(([A-Za-z0-9\-]+)\)').allMatches(label);
    for (final m in paren) {
      yield _norm(m.group(1)!);
    }
    final stripped = label.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
    if (stripped.isNotEmpty && stripped != label) {
      yield _norm(stripped);
    }
    // Dual enzyme labels: SGOT/AST → sgot + ast
    for (final part in label.split(RegExp(r'[/|,]'))) {
      final p = part.trim();
      if (p.length >= 2) yield _norm(p);
    }
  }

  bool _looksLikeRangeOnly(String s) => RegExp(
        r'^\d+(?:\.\d+)?\s*[-–to]+\s*\d+(?:\.\d+)?\s*$',
        caseSensitive: false,
      ).hasMatch(s.trim());

  String? _pickByUnit(
    List<String> codes,
    String unit,
    Map<String, String> units,
  ) {
    if (unit.trim().isEmpty) return null;
    final u = _norm(unit);
    for (final c in codes) {
      final expected = _norm(units[c] ?? '');
      if (expected.isNotEmpty && expected == u) return c;
    }
    return null;
  }

  String? _pickPctCollision(List<String> codes, String unit) {
    final set = codes.toSet();
    if (!set.contains('plateletcrit') || !set.contains('procalcitonin')) {
      return null;
    }
    final u = _norm(unit);
    if (u.contains('ng') || u.contains('ug') || u == 'ugml' || u == 'ngml') {
      return 'procalcitonin';
    }
    if (u == '%' || u == 'percent') return 'plateletcrit';
    return null;
  }

  String _refineThyroidCode(String code, String unit) {
    final u = _norm(unit);
    if (code == 't4' && u == 'ngdl') return 'ft4';
    if (code == 't3' && (u == 'pgml' || u == 'pgdl')) return 'ft3';
    return code;
  }

  /// Restore from a decrypted bodyline-export-v1 JSON string (wipes first).
  Future<void> importFromExportJson(String jsonStr) async {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    if (map['format'] != 'bodyline-export-v1') {
      throw StateError('Not a bodyline export');
    }
    await wipeEverything();
    final profiles = (map['profiles'] as List?) ?? [];
    for (final raw in profiles) {
      final m = Map<String, dynamic>.from(raw as Map);
      await createProfile(
        name: m['name'] as String? ?? 'Restored',
        relation: m['relation'] as String? ?? 'self',
        sex: m['sex'] as String?,
        dob: m['dob'] as String?,
      );
    }
    await reload();
    // Map old profile ids → new by name
    final byName = {for (final p in this.profiles) p.name: p.id};
    final oldToNew = <String, String>{};
    for (final raw in profiles) {
      final m = Map<String, dynamic>.from(raw as Map);
      final name = m['name'] as String? ?? 'Restored';
      final oldId = m['id'] as String?;
      if (oldId != null && byName[name] != null) {
        oldToNew[oldId] = byName[name]!;
      }
    }

    final reports = (map['reports'] as List?) ?? [];
    final observations = (map['observations'] as List?) ?? [];
    for (final raw in reports) {
      final m = Map<String, dynamic>.from(raw as Map);
      final oldPid = m['profile_id'] as String?;
      final newPid = oldToNew[oldPid ?? ''] ?? activeProfileId;
      if (newPid == null) continue;
      final reportObs = [
        for (final o in observations)
          if ((o as Map)['report_id'] == m['id'])
            ManualObservationInput(
              parameterCode: o['parameter_code'] as String,
              parameterName: o['parameter_name'] as String? ?? o['parameter_code'] as String,
              valueReported: o['value_reported'] as String,
              unitReported: o['unit_reported'] as String? ?? '',
              refLow: (o['ref_low'] as num?)?.toDouble(),
              refHigh: (o['ref_high'] as num?)?.toDouble(),
              refBands: decodeRefBandsJson(o['ref_bands_json'] as String?),
            ),
      ];
      if (reportObs.isEmpty) continue;
      await addManualPanel(
        profileId: newPid,
        title: m['title'] as String? ?? 'Restored report',
        collectedAt: DateTime.tryParse(m['collected_at'] as String? ?? '') ??
            DateTime.now(),
        values: reportObs,
      );
    }
    await reload();
  }

  Future<void> wipeEverything() async {
    await deleteAllUserData();
    await wipeBlobs();
    activeProfileId = null;
    await reload();
  }
}
