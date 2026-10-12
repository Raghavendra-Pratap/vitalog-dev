import 'package:bodyline_core/bodyline_core.dart';

class ProfileRecord {
  ProfileRecord({
    required this.id,
    required this.name,
    required this.relation,
    this.sex,
    this.dob,
    this.bloodGroup,
  });

  final String id;
  final String name;
  final String relation;
  final String? sex;
  final String? dob;
  final String? bloodGroup;

  ProfileRecord copyWith({
    String? name,
    String? relation,
    String? sex,
    String? dob,
    String? bloodGroup,
    bool clearSex = false,
    bool clearDob = false,
    bool clearBloodGroup = false,
  }) =>
      ProfileRecord(
        id: id,
        name: name ?? this.name,
        relation: relation ?? this.relation,
        sex: clearSex ? null : (sex ?? this.sex),
        dob: clearDob ? null : (dob ?? this.dob),
        bloodGroup:
            clearBloodGroup ? null : (bloodGroup ?? this.bloodGroup),
      );

  Map<String, Object?> toRow({required int nowMs, required String hlc}) => {
        'id': id,
        'name': name,
        'relation': relation,
        'sex': sex,
        'dob': dob,
        'blood_group': bloodGroup,
        'color': null,
        'is_primary': 0,
        'notes': null,
        'created_at': nowMs,
        'updated_at': nowMs,
        'hlc': hlc,
        'deleted': 0,
      };

  static ProfileRecord fromRow(Map<String, Object?> row) => ProfileRecord(
        id: row['id']! as String,
        name: row['name']! as String,
        relation: row['relation']! as String,
        sex: row['sex'] as String?,
        dob: row['dob'] as String?,
        bloodGroup: row['blood_group'] as String?,
      );
}

class ReportRecord {
  ReportRecord({
    required this.id,
    required this.profileId,
    required this.title,
    required this.collectedAt,
  });

  final String id;
  final String profileId;
  final String title;
  final DateTime collectedAt;
}

class ManualObservationInput {
  ManualObservationInput({
    required this.parameterCode,
    required this.parameterName,
    required this.valueReported,
    required this.unitReported,
    this.refLow,
    this.refHigh,
    this.refBands,
    this.externalId,
    this.source = 'manual',
  });

  final String parameterCode;
  final String parameterName;
  final String valueReported;
  final String unitReported;
  final double? refLow;
  final double? refHigh;
  /// Printed stages / tiered bands (ADR-003 labels as entered).
  final List<RefBand>? refBands;
  /// Optional Health Connect / HealthKit uuid for dedupe on import.
  final String? externalId;
  /// Observation provenance: manual | health_connect | healthkit | …
  final String source;
}

class ObservationRecord {
  ObservationRecord({
    required this.id,
    required this.profileId,
    required this.reportId,
    required this.parameterCode,
    required this.parameterName,
    required this.observedAt,
    required this.valueReported,
    required this.unitReported,
    this.valueNum,
    this.refLow,
    this.refHigh,
    this.refBands,
    this.flag,
    this.deleted = false,
  });

  final String id;
  final String profileId;
  final String reportId;
  final String parameterCode;
  final String parameterName;
  final DateTime observedAt;
  final String valueReported;
  final String unitReported;
  final double? valueNum;
  final double? refLow;
  final double? refHigh;
  final List<RefBand>? refBands;
  final ObservationFlag? flag;
  final bool deleted;
}

ObservationFlag? flagFromDb(String? raw) {
  switch (raw) {
    case 'normal':
      return ObservationFlag.normal;
    case 'low':
      return ObservationFlag.low;
    case 'high':
      return ObservationFlag.high;
    case 'abnormal':
      return ObservationFlag.abnormal;
    case 'critical_low':
      return ObservationFlag.criticalLow;
    case 'critical_high':
      return ObservationFlag.criticalHigh;
    default:
      return null;
  }
}

String? flagToDb(ObservationFlag? flag) {
  if (flag == null) return null;
  switch (flag) {
    case ObservationFlag.normal:
      return 'normal';
    case ObservationFlag.low:
      return 'low';
    case ObservationFlag.high:
      return 'high';
    case ObservationFlag.abnormal:
      return 'abnormal';
    case ObservationFlag.criticalLow:
      return 'critical_low';
    case ObservationFlag.criticalHigh:
      return 'critical_high';
  }
}


class OrganSummary {
  OrganSummary({
    required this.code,
    required this.name,
    required this.flag,
    required this.highCount,
    required this.lowCount,
  });

  final String code;
  final String name;
  final ObservationFlag? flag;
  final int highCount;
  final int lowCount;

  String get statusText {
    if (flag == null) return 'Not tested';
    if (highCount > 0) return '$highCount high';
    if (lowCount > 0) return '$lowCount low';
    return 'In range';
  }
}


class MedicalItem {
  MedicalItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.kind,
    this.strength,
    this.instructions,
    this.pillCount,
    this.restockOn,
    this.prescribedAs,
    this.visitId,
    this.endDate,
    this.dosageForm,
  });
  final String id;
  final String title;
  final String? subtitle;
  final String? kind;
  final String? strength;
  final String? instructions;
  final int? pillCount;
  final String? restockOn;
  final String? prescribedAs;
  final String? visitId;
  final String? dosageForm;
  /// ISO date when course ended; null = still active.
  final String? endDate;

  bool get isActiveCourse => endDate == null || endDate!.trim().isEmpty;

  /// active | completed — derived from [endDate].
  String get courseStatus => isActiveCourse ? 'active' : 'completed';
}


class AttachmentRecord {
  AttachmentRecord({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.sha256,
    required this.mime,
    required this.byteSize,
    this.fileName,
  });

  final String id;
  final String ownerType;
  final String ownerId;
  final String sha256;
  final String mime;
  final int byteSize;
  final String? fileName;
}


class ProviderRecord {
  ProviderRecord({
    required this.id,
    required this.profileId,
    required this.name,
    this.specialty,
    this.clinic,
    this.phone,
    this.notes,
  });
  final String id;
  final String profileId;
  final String name;
  final String? specialty;
  /// Hospital or clinic name (free text).
  final String? clinic;
  final String? phone;
  final String? notes;
}

class VisitRecord {
  VisitRecord({
    required this.id,
    required this.profileId,
    required this.visitedAt,
    this.reason,
    this.diagnosis,
    this.notes,
    this.followUpDate,
    this.providerId,
    this.providerName,
    this.providerClinic,
  });
  final String id;
  final String profileId;
  final DateTime visitedAt;
  final String? reason;
  final String? diagnosis;
  final String? notes;
  final String? followUpDate;
  final String? providerId;
  final String? providerName;
  final String? providerClinic;

  VisitRecord copyWith({
    String? reason,
    String? diagnosis,
    String? notes,
    String? followUpDate,
    DateTime? visitedAt,
    String? providerId,
    String? providerName,
    String? providerClinic,
  }) =>
      VisitRecord(
        id: id,
        profileId: profileId,
        visitedAt: visitedAt ?? this.visitedAt,
        reason: reason ?? this.reason,
        diagnosis: diagnosis ?? this.diagnosis,
        notes: notes ?? this.notes,
        followUpDate: followUpDate ?? this.followUpDate,
        providerId: providerId ?? this.providerId,
        providerName: providerName ?? this.providerName,
        providerClinic: providerClinic ?? this.providerClinic,
      );
}

class ReminderRecord {
  ReminderRecord({
    required this.id,
    required this.profileId,
    required this.kind,
    required this.title,
    required this.dueAt,
    this.targetCode,
    this.rrule,
    this.notes,
    this.assigneeProfileId,
    this.observerProfileIds,
  });
  final String id;
  final String profileId;
  final String kind;
  final String title;
  final DateTime dueAt;
  final String? targetCode;
  /// Null = one-shot. Presets: FREQ=WEEKLY | MONTHLY | MONTHLY;INTERVAL=3|6 | YEARLY.
  final String? rrule;
  final String? notes;
  /// Delegated owner (ADR-010).
  final String? assigneeProfileId;
  /// Extra profiles that should see this reminder.
  final List<String>? observerProfileIds;

  bool get isRecurring => rrule != null && rrule!.trim().isNotEmpty;

  static String? labelForRrule(String? rrule) {
    switch (rrule) {
      case 'FREQ=WEEKLY':
        return 'Weekly';
      case 'FREQ=MONTHLY':
        return 'Monthly';
      case 'FREQ=MONTHLY;INTERVAL=3':
        return 'Every 3 months';
      case 'FREQ=MONTHLY;INTERVAL=6':
        return 'Every 6 months';
      case 'FREQ=YEARLY':
        return 'Yearly';
      default:
        return null;
    }
  }
}


class ParsedLabLine {
  ParsedLabLine({
    required this.parameterCode,
    required this.parameterName,
    required this.valueReported,
    required this.unitReported,
    this.refLow,
    this.refHigh,
    this.refBands,
    this.sourceLine,
    this.pageIndex = 1,
  });
  final String parameterCode;
  final String parameterName;
  final String valueReported;
  final String unitReported;
  final double? refLow;
  final double? refHigh;
  /// Multi-stage bands from OCR when the slip prints several labeled intervals.
  final List<RefBand>? refBands;
  final String? sourceLine;
  /// 1-based PDF page where this row was found (1 if unknown / paste).
  final int pageIndex;

  ParsedLabLine copyWith({
    String? parameterCode,
    String? parameterName,
    String? valueReported,
    String? unitReported,
    double? refLow,
    double? refHigh,
    List<RefBand>? refBands,
    String? sourceLine,
    int? pageIndex,
    bool clearBands = false,
  }) {
    return ParsedLabLine(
      parameterCode: parameterCode ?? this.parameterCode,
      parameterName: parameterName ?? this.parameterName,
      valueReported: valueReported ?? this.valueReported,
      unitReported: unitReported ?? this.unitReported,
      refLow: refLow ?? this.refLow,
      refHigh: refHigh ?? this.refHigh,
      refBands: clearBands ? null : (refBands ?? this.refBands),
      sourceLine: sourceLine ?? this.sourceLine,
      pageIndex: pageIndex ?? this.pageIndex,
    );
  }
}


const kMedicationKinds = <String>[
  'allopathic',
  'ayurvedic',
  'homeopathic',
  'supplement',
  'other',
];

String medicationKindLabel(String? kind) {
  switch (kind) {
    case 'allopathic':
      return 'Allopathic';
    case 'ayurvedic':
      return 'Ayurvedic / AYUSH';
    case 'homeopathic':
      return 'Homeopathic';
    case 'supplement':
      return 'Supplement';
    case 'other':
      return 'Other';
    default:
      return 'Medicine';
  }
}

class MedicationDoseSlot {
  MedicationDoseSlot({
    required this.medicationId,
    required this.name,
    required this.kind,
    required this.timeHm,
    required this.scheduledFor,
    this.strength,
    this.logStatus,
  });

  final String medicationId;
  final String name;
  final String kind;
  final String timeHm;
  final DateTime scheduledFor;
  final String? strength;
  final String? logStatus;

  bool get isDone => logStatus == 'taken' || logStatus == 'skipped';
}

class MedicationScheduleInfo {
  MedicationScheduleInfo({
    required this.scheduleId,
    required this.medicationId,
    required this.medicationName,
    required this.kind,
    required this.times,
    this.strength,
  });

  final String scheduleId;
  final String medicationId;
  final String medicationName;
  final String kind;
  final List<String> times;
  final String? strength;
}
