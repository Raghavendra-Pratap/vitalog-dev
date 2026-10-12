import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../notifications/reminder_notifications.dart';
import '../../widgets/clinical_attachments.dart';
import '../../widgets/drug_name_field.dart';
import '../../widgets/month_year_date_picker.dart';
import '../../desktop.dart';
import '../../theme/tokens.dart';


/// If the user typed a medicine but did not tap "Add to list", include it on Save.
void _flushDraftMedication({
  required List<({String name, String? strength, String? instructions})> pending,
  required TextEditingController name,
  required TextEditingController strength,
  required TextEditingController instructions,
}) {
  final n = name.text.trim();
  if (n.isEmpty) return;
  // Avoid duplicating if already flushed / already in list as last item.
  if (pending.isNotEmpty &&
      pending.last.name == n &&
      pending.last.strength ==
          (strength.text.trim().isEmpty ? null : strength.text.trim()) &&
      pending.last.instructions ==
          (instructions.text.trim().isEmpty ? null : instructions.text.trim())) {
    name.clear();
    strength.clear();
    instructions.clear();
    return;
  }
  pending.add((
    name: n,
    strength: strength.text.trim().isEmpty ? null : strength.text.trim(),
    instructions:
        instructions.text.trim().isEmpty ? null : instructions.text.trim(),
  ));
  name.clear();
  strength.clear();
  instructions.clear();
}

/// Shared Add visit dialog (Visits page + Doctors detail).
/// Returns true when a visit was saved.


Future<void> _wireVisitFollowUpReminder({
  required LocalStore store,
  required String profileId,
  required String visitId,
  required DateTime? followUp,
  required String reason,
}) async {
  final title = reason.trim().isEmpty
      ? 'Follow-up visit'
      : 'Follow-up: ${reason.trim()}';
  final ymd = followUp == null
      ? null
      : DateFormat('yyyy-MM-dd').format(followUp);
  final existing =
      await store.findVisitFollowUpReminder(profileId, visitId);
  final rem = await store.syncVisitFollowUpReminder(
    profileId: profileId,
    visitId: visitId,
    followUpDateYmd: ymd,
    title: title,
  );
  if (rem == null) {
    if (existing != null) {
      await ReminderNotifications.instance.cancelReminder(existing.id);
    }
    return;
  }
  await ReminderNotifications.instance.ensurePermission();
  await ReminderNotifications.instance.scheduleReminder(rem);
}

Future<bool> promptAddVisit(
  BuildContext context, {
  required LocalStore store,
  required VoidCallback onChanged,
  String? prefillDoctor,
}) async {
    final pid = store.activeProfileId;
    if (pid == null) return false;

    final knownDoctors = await store.listDoctorNames(pid);
    final clinicByDoctor = <String, String>{};
    for (final n in knownDoctors) {
      final c = await store.clinicForDoctorName(n);
      if (c != null && c.trim().isNotEmpty) clinicByDoctor[n] = c.trim();
    }
    if (!context.mounted) return false;

    final reason = TextEditingController();
    final doctor = TextEditingController();
    final diagnosis = TextEditingController();
    final notes = TextEditingController();
    final medName = TextEditingController();
    final medStrength = TextEditingController();
    final medInstructions = TextEditingController();
    DateTime when = DateTime.now();
    DateTime? followUp;
    final pending = <PendingClinicalFile>[];
    final pendingMeds = <({String name, String? strength, String? instructions})>[];
    String? doctorChoice;
    if (prefillDoctor != null && prefillDoctor.trim().isNotEmpty) {
      final pref = prefillDoctor.trim();
      if (knownDoctors.any((n) => n.toLowerCase() == pref.toLowerCase())) {
        doctorChoice = knownDoctors.firstWhere(
          (n) => n.toLowerCase() == pref.toLowerCase(),
        );
        doctor.text = doctorChoice;
      } else {
        doctorChoice = '__new__';
        doctor.text = pref;
      }
    } else {
      doctorChoice = knownDoctors.isEmpty ? '__new__' : null;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add visit'),
          titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
          contentPadding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 12, 28, 20),
          insetPadding: bodylineDialogInset(ctx),
          content: SizedBox(
            width: bodylineDialogWidth(ctx, 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    key: ValueKey(doctorChoice ?? 'none'),
                    initialValue: doctorChoice,
                    decoration: const InputDecoration(
                      labelText: 'Doctor (optional)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None'),
                      ),
                      for (final n in knownDoctors)
                        DropdownMenuItem<String?>(
                          value: n,
                          child: Text(n),
                        ),
                      const DropdownMenuItem<String?>(
                        value: '__new__',
                        child: Text('New doctor…'),
                      ),
                    ],
                    onChanged: (v) => setLocal(() {
                      doctorChoice = v;
                      if (v != null && v != '__new__') {
                        doctor.text = v;
                      } else if (v == null) {
                        doctor.clear();
                      } else {
                        doctor.clear();
                      }
                    }),
                  ),
                  if (doctorChoice == '__new__') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: doctor,
                      decoration: const InputDecoration(
                        labelText: 'New doctor name',
                        helperText:
                            'Saved to Doctors when you save this visit',
                      ),
                      textCapitalization: TextCapitalization.words,
                      autofocus: knownDoctors.isEmpty,
                    ),
                  ],
                  if (doctorChoice != null &&
                      doctorChoice != '__new__' &&
                      clinicByDoctor[doctorChoice] != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Hospital / clinic: ${clinicByDoctor[doctorChoice]}',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: BodylineColors.inkSubtle,
                          ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: diagnosis,
                    decoration: const InputDecoration(
                      labelText: 'Diagnosis / findings (optional)',
                      helperText:
                          'What the doctor wrote or what you noted — not a bodyline diagnosis.',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    decoration:
                        const InputDecoration(labelText: 'Notes (optional)'),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title:
                        Text('Date: ${DateFormat('d MMM yyyy').format(when)}'),
                    onTap: () async {
                      final d = await pickBodylineDate(
                        ctx,
                        initialDate: when,
                        firstDate: DateTime(1990),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) setLocal(() => when = d);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      followUp == null
                          ? 'Follow-up date (optional)'
                          : 'Follow-up: ${DateFormat('d MMM yyyy').format(followUp!)}',
                    ),
                    trailing: followUp == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setLocal(() => followUp = null),
                          ),
                    onTap: () async {
                      final d = await pickBodylineDate(
                        ctx,
                        initialDate: followUp ??
                            DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (d != null) setLocal(() => followUp = d);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text('Appointment files (optional)',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    'Doctor note, findings, prescription — PDF or photo.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  if (pending.isNotEmpty)
                    for (var i = 0; i < pending.length; i++)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.attach_file, size: 18),
                        title: Text(pending[i].fileName,
                            style: const TextStyle(fontSize: 13)),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setLocal(() => pending.removeAt(i)),
                        ),
                      ),
                  TextButton.icon(
                    onPressed: () async {
                      final files = await pickClinicalFiles();
                      if (files.isEmpty) return;
                      setLocal(() => pending.addAll(files));
                    },
                    icon: const Icon(Icons.attach_file),
                    label: Text(pending.isEmpty
                        ? 'Attach PDF or image'
                        : 'Add another file'),
                  ),
                  const SizedBox(height: 12),
                  Text('Medications from this visit (optional)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Suggestions are offline names only — not advice.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (pendingMeds.isNotEmpty)
                    for (var i = 0; i < pendingMeds.length; i++)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          [
                            pendingMeds[i].name,
                            if (pendingMeds[i].strength != null)
                              pendingMeds[i].strength!,
                          ].join(' · '),
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () =>
                              setLocal(() => pendingMeds.removeAt(i)),
                        ),
                      ),
                  Builder(
                    builder: (rowCtx) {
                      final narrow = !useWideShell(rowCtx);
                      final nameField = DrugNameField(
                        controller: medName,
                        decoration: const InputDecoration(
                          labelText: 'Medication name',
                        ),
                      );
                      final strengthField = TextField(
                        controller: medStrength,
                        decoration: const InputDecoration(
                          labelText: 'Strength',
                        ),
                      );
                      final instructionsField = TextField(
                        controller: medInstructions,
                        decoration: const InputDecoration(
                          labelText: 'Instructions',
                        ),
                      );
                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            nameField,
                            const SizedBox(height: 10),
                            strengthField,
                            const SizedBox(height: 10),
                            instructionsField,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: nameField),
                          const SizedBox(width: 10),
                          Expanded(flex: 2, child: strengthField),
                          const SizedBox(width: 10),
                          Expanded(flex: 3, child: instructionsField),
                        ],
                      );
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        final n = medName.text.trim();
                        if (n.isEmpty) return;
                        setLocal(() {
                          pendingMeds.add((
                            name: n,
                            strength: medStrength.text.trim().isEmpty
                                ? null
                                : medStrength.text.trim(),
                            instructions: medInstructions.text.trim().isEmpty
                                ? null
                                : medInstructions.text.trim(),
                          ));
                          medName.clear();
                          medStrength.clear();
                          medInstructions.clear();
                        });
                      },
                      child: const Text('Add medication to list'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                _flushDraftMedication(
                  pending: pendingMeds,
                  name: medName,
                  strength: medStrength,
                  instructions: medInstructions,
                );
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return false;

    final visit = await store.addVisit(
      profileId: pid,
      visitedAt: when,
      reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
      diagnosis:
          diagnosis.text.trim().isEmpty ? null : diagnosis.text.trim(),
      notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      followUpDate: followUp == null
          ? null
          : DateFormat('yyyy-MM-dd').format(followUp!),
      providerName: () {
        if (doctorChoice == null) return null;
        if (doctorChoice == '__new__') {
          final n = doctor.text.trim();
          return n.isEmpty ? null : n;
        }
        return doctorChoice;
      }(),
    );

    // New free-text names are created via addVisit → _ensureProvider;
    // existing names already live in Doctors.

    await attachPendingFiles(
      store: store,
      ownerType: 'visit',
      ownerId: visit.id,
      files: pending,
    );

    for (final m in pendingMeds) {
      await store.addMedication(
        profileId: pid,
        name: m.name,
        kind: 'allopathic',
        strength: m.strength,
        instructions: m.instructions,
        visitId: visit.id,
      );
    }

    await _wireVisitFollowUpReminder(
      store: store,
      profileId: pid,
      visitId: visit.id,
      followUp: followUp,
      reason: reason.text,
    );

    onChanged();
    return true;
}

/// Edit an existing visit (Visits page + Doctors detail).
Future<VisitRecord?> promptEditVisit(
  BuildContext context, {
  required LocalStore store,
  required VisitRecord visit,
  required VoidCallback onChanged,
}) async {
  final pid = store.activeProfileId;
  if (pid == null) return null;

  final knownDoctors = await store.listDoctorNames(pid);
  final clinicByDoctor = <String, String>{};
  for (final n in knownDoctors) {
    final c = await store.clinicForDoctorName(n);
    if (c != null && c.trim().isNotEmpty) clinicByDoctor[n] = c.trim();
  }
  if (!context.mounted) return null;

  final reason = TextEditingController(text: visit.reason ?? '');
  final doctor = TextEditingController();
  final diagnosis = TextEditingController(text: visit.diagnosis ?? '');
  final notes = TextEditingController(text: visit.notes ?? '');
  final medName = TextEditingController();
  final medStrength = TextEditingController();
  final medInstructions = TextEditingController();
  DateTime when = visit.visitedAt;
  DateTime? followUp;
  if (visit.followUpDate != null && visit.followUpDate!.trim().isNotEmpty) {
    try {
      final parts = visit.followUpDate!.trim().split('-');
      if (parts.length == 3) {
        followUp = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }
    } catch (_) {}
  }
  final pendingMeds =
      <({String name, String? strength, String? instructions})>[];
  final pendingFiles = <PendingClinicalFile>[];
  final existingAtts = await store.listAttachments(
    ownerType: 'visit',
    ownerId: visit.id,
  );
  final existingMeds = await store.listMedicationsForVisit(visit.id);
  if (!context.mounted) return null;
  var savedAtts = List<AttachmentRecord>.from(existingAtts);
  var savedMeds = List<MedicalItem>.from(existingMeds);
  final removeAttIds = <String>{};
  final removeMedIds = <String>{};
  String? doctorChoice;
  final existing = visit.providerName?.trim();
  if (existing != null && existing.isNotEmpty) {
    if (knownDoctors.any((n) => n.toLowerCase() == existing.toLowerCase())) {
      doctorChoice = knownDoctors.firstWhere(
        (n) => n.toLowerCase() == existing.toLowerCase(),
      );
      doctor.text = doctorChoice;
    } else {
      doctorChoice = '__new__';
      doctor.text = existing;
    }
  } else {
    doctorChoice = knownDoctors.isEmpty ? '__new__' : null;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Edit visit'),
        titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
        contentPadding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 12, 28, 20),
        insetPadding: bodylineDialogInset(ctx),
        content: SizedBox(
          width: bodylineDialogWidth(ctx, 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: ValueKey(doctorChoice ?? 'none'),
                  initialValue: doctorChoice,
                  decoration: const InputDecoration(
                    labelText: 'Doctor (optional)',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None'),
                    ),
                    for (final n in knownDoctors)
                      DropdownMenuItem<String?>(
                        value: n,
                        child: Text(n),
                      ),
                    const DropdownMenuItem<String?>(
                      value: '__new__',
                      child: Text('New doctor…'),
                    ),
                  ],
                  onChanged: (v) => setLocal(() {
                    doctorChoice = v;
                    if (v != null && v != '__new__') {
                      doctor.text = v;
                    } else if (v == null) {
                      doctor.clear();
                    } else {
                      doctor.clear();
                    }
                  }),
                ),
                if (doctorChoice == '__new__') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: doctor,
                    decoration: const InputDecoration(
                      labelText: 'Doctor name',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                ],
                if (doctorChoice != null &&
                    doctorChoice != '__new__' &&
                    clinicByDoctor[doctorChoice] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Hospital / clinic: ${clinicByDoctor[doctorChoice]}',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: BodylineColors.inkSubtle,
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: diagnosis,
                  decoration: const InputDecoration(
                    labelText: 'Diagnosis / findings (optional)',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  decoration:
                      const InputDecoration(labelText: 'Notes / remarks (optional)'),
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title:
                      Text('Date: ${DateFormat('d MMM yyyy').format(when)}'),
                  onTap: () async {
                    final d = await pickBodylineDate(
                      ctx,
                      initialDate: when,
                      firstDate: DateTime(1990),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setLocal(() => when = d);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    followUp == null
                        ? 'Follow-up date (optional)'
                        : 'Follow-up: ${DateFormat('d MMM yyyy').format(followUp!)}',
                  ),
                  trailing: followUp == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setLocal(() => followUp = null),
                        ),
                  onTap: () async {
                    final d = await pickBodylineDate(
                      ctx,
                      initialDate: followUp ??
                          DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime(1990),
                      lastDate:
                          DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (d != null) setLocal(() => followUp = d);
                  },
                ),
                const SizedBox(height: 8),
                Text('Appointment files (optional)',
                    style: Theme.of(ctx).textTheme.titleSmall),
                Text(
                  'Doctor note, findings, prescription — PDF or photo.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                if (savedAtts.isNotEmpty)
                  for (final a in List<AttachmentRecord>.from(savedAtts))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attach_file, size: 18),
                      title: Text(
                        a.fileName ?? 'Attachment',
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setLocal(() {
                          savedAtts.removeWhere((x) => x.id == a.id);
                          removeAttIds.add(a.id);
                        }),
                      ),
                    ),
                if (pendingFiles.isNotEmpty)
                  for (var i = 0; i < pendingFiles.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attach_file, size: 18),
                      title: Text(
                        pendingFiles[i].fileName,
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            setLocal(() => pendingFiles.removeAt(i)),
                      ),
                    ),
                TextButton.icon(
                  onPressed: () async {
                    final files = await pickClinicalFiles();
                    if (files.isEmpty) return;
                    setLocal(() => pendingFiles.addAll(files));
                  },
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    (savedAtts.isEmpty && pendingFiles.isEmpty)
                        ? 'Attach PDF or image'
                        : 'Add another file',
                  ),
                ),
                const SizedBox(height: 12),
                Text('Medications from this visit (optional)',
                    style: Theme.of(ctx).textTheme.titleSmall),
                Text(
                  'Suggestions are offline names only — not advice.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (savedMeds.isNotEmpty)
                  for (final m in List<MedicalItem>.from(savedMeds))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        [
                          m.title,
                          if (m.strength != null) m.strength!,
                        ].join(' · '),
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setLocal(() {
                          savedMeds.removeWhere((x) => x.id == m.id);
                          removeMedIds.add(m.id);
                        }),
                      ),
                    ),
                if (pendingMeds.isNotEmpty)
                  for (var i = 0; i < pendingMeds.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        [
                          pendingMeds[i].name,
                          if (pendingMeds[i].strength != null)
                            pendingMeds[i].strength!,
                        ].join(' · '),
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            setLocal(() => pendingMeds.removeAt(i)),
                      ),
                    ),
                Builder(
                  builder: (rowCtx) {
                    final narrow = !useWideShell(rowCtx);
                    final nameField = DrugNameField(
                      controller: medName,
                      decoration: const InputDecoration(
                        labelText: 'Medication name',
                      ),
                    );
                    final strengthField = TextField(
                      controller: medStrength,
                      decoration: const InputDecoration(
                        labelText: 'Strength',
                      ),
                    );
                    final instructionsField = TextField(
                      controller: medInstructions,
                      decoration: const InputDecoration(
                        labelText: 'Instructions',
                      ),
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          nameField,
                          const SizedBox(height: 10),
                          strengthField,
                          const SizedBox(height: 10),
                          instructionsField,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: nameField),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: strengthField),
                        const SizedBox(width: 10),
                        Expanded(flex: 3, child: instructionsField),
                      ],
                    );
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      final n = medName.text.trim();
                      if (n.isEmpty) return;
                      setLocal(() {
                        pendingMeds.add((
                          name: n,
                          strength: medStrength.text.trim().isEmpty
                              ? null
                              : medStrength.text.trim(),
                          instructions: medInstructions.text.trim().isEmpty
                              ? null
                              : medInstructions.text.trim(),
                        ));
                        medName.clear();
                        medStrength.clear();
                        medInstructions.clear();
                      });
                    },
                    child: const Text('Add medication to list'),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              _flushDraftMedication(
                pending: pendingMeds,
                name: medName,
                strength: medStrength,
                instructions: medInstructions,
              );
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return null;

  final updated = await store.updateVisit(
    visitId: visit.id,
    profileId: pid,
    visitedAt: when,
    reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
    diagnosis: diagnosis.text.trim().isEmpty ? null : diagnosis.text.trim(),
    notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
    followUpDate: followUp == null
        ? null
        : DateFormat('yyyy-MM-dd').format(followUp!),
    providerName: () {
      if (doctorChoice == null) return null;
      if (doctorChoice == '__new__') {
        final n = doctor.text.trim();
        return n.isEmpty ? null : n;
      }
      return doctorChoice;
    }(),
  );

  await _wireVisitFollowUpReminder(
    store: store,
    profileId: pid,
    visitId: visit.id,
    followUp: followUp,
    reason: reason.text,
  );

  for (final id in removeAttIds) {
    try {
      await store.softDeleteAttachment(id);
    } catch (_) {}
  }
  await attachPendingFiles(
    store: store,
    ownerType: 'visit',
    ownerId: visit.id,
    files: pendingFiles,
  );

  for (final id in removeMedIds) {
    try {
      await store.softDeleteMedication(id);
    } catch (_) {}
  }
  if (removeMedIds.isNotEmpty) {
    try {
      final schedules = await store.listAllMedicationSchedules();
      await ReminderNotifications.instance.rescheduleAllDoses(schedules);
    } catch (_) {}
  }

  var medError = false;
  for (final m in pendingMeds) {
    try {
      await store.addMedication(
        profileId: pid,
        name: m.name,
        kind: 'allopathic',
        strength: m.strength,
        instructions: m.instructions,
        visitId: visit.id,
      );
    } catch (_) {
      medError = true;
    }
  }

  onChanged();
  if (medError && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Visit saved, but a medicine could not be added. Try Medicines → Add.',
        ),
      ),
    );
  }
  return updated;
}
