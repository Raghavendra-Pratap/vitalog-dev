import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../profiles/edit_profile_sheet.dart';
import '../../theme/tokens.dart';

Future<void> shareDoctorSummary({
  required BuildContext context,
  required LocalStore store,
}) async {
  final profile = store.profiles.cast<dynamic>().where(
        (p) => p.id == store.activeProfileId,
      );
  if (profile.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Create a profile first.')),
    );
    return;
  }
  final p = profile.first;
  final fmt = DateFormat('d MMM yyyy');
  final pid = store.activeProfileId!;

  final conditions = await store.listConditions(pid);
  final meds = await store.listMedications(pid);
  final allergies = await store.listAllergies(pid);

  final latest = <String, ObservationRecord>{};
  for (final o in store.observations) {
    if (o.profileId != pid) continue;
    final prev = latest[o.parameterCode];
    if (prev == null || o.observedAt.isAfter(prev.observedAt)) {
      latest[o.parameterCode] = o;
    }
  }
  final flagged = latest.values
      .where((o) =>
          o.flag != null && o.flag != ObservationFlag.normal)
      .toList()
    ..sort((a, b) => a.parameterName.compareTo(b.parameterName));

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text('Vitalog — doctor summary',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Generated ${fmt.format(DateTime.now())} · on-device only'),
        pw.SizedBox(height: 12),
        pw.Text(p.name,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text('${profileRelationLabel(p.relation)}${p.sex != null ? ' · ${p.sex}' : ''}'),
        pw.SizedBox(height: 16),
        pw.Text('Allergies',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        if (allergies.isEmpty)
          pw.Text('None recorded')
        else
          ...allergies.map((a) => pw.Text('• ${a.title}${a.subtitle != null ? ' (${a.subtitle})' : ''}')),
        pw.SizedBox(height: 10),
        pw.Text('Medications',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        if (meds.isEmpty)
          pw.Text('None recorded')
        else
          ...meds.map((m) => pw.Text('• ${m.title}${m.subtitle != null && m.subtitle!.isNotEmpty ? ' — ${m.subtitle}' : ''}')),
        pw.SizedBox(height: 10),
        pw.Text('Conditions',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        if (conditions.isEmpty)
          pw.Text('None recorded')
        else
          ...conditions.map((c) => pw.Text('• ${c.title}')),
        pw.SizedBox(height: 10),
        pw.Text('Values outside the lab’s printed range',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text(
          'These are comparisons to the lab range on file — not diagnoses.',
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.SizedBox(height: 6),
        if (flagged.isEmpty)
          pw.Text('None on the latest results')
        else
          ...flagged.map((o) => pw.Text(
                '• ${o.parameterName}: ${o.valueReported} ${o.unitReported} '
                '(${flagLabel(o.flag!)}) · ${fmt.format(o.observedAt)}',
              )),
        pw.SizedBox(height: 24),
        pw.Text(
          'Shared from bodyline on the patient’s device. No bodyline server.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ],
    ),
  );

  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'vitalog-doctor-summary.pdf',
  );
}

class DoctorSummaryButton extends StatelessWidget {
  const DoctorSummaryButton({super.key, required this.store});
  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => shareDoctorSummary(context: context, store: store),
      icon: const Icon(Icons.picture_as_pdf_outlined),
      label: const Text('Doctor summary (PDF)'),
      style: OutlinedButton.styleFrom(
        foregroundColor: BodylineColors.tealDark,
        minimumSize: const Size.fromHeight(44),
        side: BorderSide(color: BodylineColors.border),
      ),
    );
  }
}
