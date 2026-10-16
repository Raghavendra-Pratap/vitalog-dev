import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../theme/tokens.dart';

enum MedicalTimelineCategory {
  conditions,
  medicines,
  vaccinations,
  surgeries,
  visits,
}

extension MedicalTimelineCategoryX on MedicalTimelineCategory {
  String get label => switch (this) {
        MedicalTimelineCategory.conditions => 'Conditions',
        MedicalTimelineCategory.medicines => 'Medicines',
        MedicalTimelineCategory.vaccinations => 'Vaccinations',
        MedicalTimelineCategory.surgeries => 'Surgeries',
        MedicalTimelineCategory.visits => 'Visits',
      };

  Color get accent {
    switch (this) {
      case MedicalTimelineCategory.medicines:
        return const Color(0xFF6B4C9A);
      case MedicalTimelineCategory.visits:
        return BodylineColors.orange;
      case MedicalTimelineCategory.conditions:
        return BodylineColors.teal;
      case MedicalTimelineCategory.vaccinations:
        return BodylineColors.blue;
      case MedicalTimelineCategory.surgeries:
        return BodylineColors.inkMuted;
    }
  }

  Color get tint {
    switch (this) {
      case MedicalTimelineCategory.medicines:
        return const Color(0xFFEDE6F5);
      case MedicalTimelineCategory.visits:
        return BodylineColors.orangeTint;
      case MedicalTimelineCategory.conditions:
        return BodylineColors.tealTint;
      case MedicalTimelineCategory.vaccinations:
        return BodylineColors.blueTint;
      case MedicalTimelineCategory.surgeries:
        return BodylineColors.chip;
    }
  }

  Color get tagText {
    switch (this) {
      case MedicalTimelineCategory.medicines:
        return const Color(0xFF4A3270);
      case MedicalTimelineCategory.visits:
        return BodylineColors.orangeText;
      case MedicalTimelineCategory.conditions:
        return BodylineColors.tealDark;
      case MedicalTimelineCategory.vaccinations:
        return BodylineColors.blueText;
      case MedicalTimelineCategory.surgeries:
        return BodylineColors.inkMuted;
    }
  }
}

class MedicalTimelineEvent {
  const MedicalTimelineEvent({
    required this.id,
    required this.category,
    required this.at,
    required this.title,
    required this.detail,
  });

  final String id;
  final MedicalTimelineCategory category;
  final DateTime at;
  final String title;
  final String detail;
}

DateTime? _parseDate(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  try {
    return DateTime.parse(s);
  } catch (_) {
    return null;
  }
}

DateTime _fromCreated(Object? ms) {
  if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms);
  return DateTime.fromMillisecondsSinceEpoch(0);
}

/// Newest-first medical timeline from vault tables (no demo rows).
Future<List<MedicalTimelineEvent>> loadMedicalTimelineEvents(
  LocalStore store,
  String profileId,
) async {
  final db = store.userDb;
  final out = <MedicalTimelineEvent>[];

  final conditions = await db.query(
    'condition',
    where: 'profile_id = ? AND deleted = 0',
    whereArgs: [profileId],
  );
  for (final r in conditions) {
    final name = (r['name'] as String?)?.trim() ?? 'Condition';
    final status = (r['status'] as String?)?.trim();
    final at = _parseDate(r['onset_date'] as String?) ??
        _fromCreated(r['created_at']);
    out.add(
      MedicalTimelineEvent(
        id: 'condition:${r['id']}',
        category: MedicalTimelineCategory.conditions,
        at: at,
        title: status == 'active' ? '$name diagnosed' : '$name noted',
        detail: status == null || status.isEmpty
            ? 'On file'
            : 'Status: $status',
      ),
    );
  }

  final meds = await db.query(
    'medication',
    where: 'profile_id = ? AND deleted = 0',
    whereArgs: [profileId],
  );
  for (final r in meds) {
    final name = (r['name'] as String?)?.trim() ?? 'Medicine';
    final end = (r['end_date'] as String?)?.trim();
    final ended = end != null && end.isNotEmpty;
    final at = ended
        ? (_parseDate(end) ?? _fromCreated(r['updated_at']))
        : (_parseDate(r['start_date'] as String?) ??
            _fromCreated(r['created_at']));
    final detail = [
      if ((r['strength'] as String?)?.trim().isNotEmpty == true)
        (r['strength'] as String).trim(),
      if ((r['instructions'] as String?)?.trim().isNotEmpty == true)
        (r['instructions'] as String).trim(),
    ].join(' · ');
    out.add(
      MedicalTimelineEvent(
        id: 'med:${r['id']}',
        category: MedicalTimelineCategory.medicines,
        at: at,
        title: ended ? '$name ended' : '$name started',
        detail: detail.isEmpty ? (ended ? 'Course completed' : 'On file') : detail,
      ),
    );
  }

  final vaccines = await db.query(
    'immunization',
    where: 'profile_id = ? AND deleted = 0',
    whereArgs: [profileId],
  );
  for (final r in vaccines) {
    final name = (r['vaccine'] as String?)?.trim() ?? 'Vaccination';
    final given = r['given_on'] as String?;
    final next = (r['next_due_on'] as String?)?.trim();
    final at = _parseDate(given) ?? _fromCreated(r['created_at']);
    final detail = [
      if (given != null && given.trim().isNotEmpty) 'Given ${given.trim()}',
      if (next != null && next.isNotEmpty) 'Next due $next',
    ].join(' · ');
    out.add(
      MedicalTimelineEvent(
        id: 'vax:${r['id']}',
        category: MedicalTimelineCategory.vaccinations,
        at: at,
        title: name,
        detail: detail.isEmpty ? 'On file' : detail,
      ),
    );
  }

  final procs = await db.query(
    'procedure_record',
    where: 'profile_id = ? AND deleted = 0',
    whereArgs: [profileId],
  );
  for (final r in procs) {
    final name = (r['name'] as String?)?.trim() ?? 'Procedure';
    final performed = r['performed_on'] as String?;
    final notes = (r['notes'] as String?)?.trim();
    final at = _parseDate(performed) ?? _fromCreated(r['created_at']);
    out.add(
      MedicalTimelineEvent(
        id: 'proc:${r['id']}',
        category: MedicalTimelineCategory.surgeries,
        at: at,
        title: name,
        detail: (notes != null && notes.isNotEmpty)
            ? notes
            : (performed != null && performed.trim().isNotEmpty
                ? performed.trim()
                : 'On file'),
      ),
    );
  }

  final visits = await store.listVisits(profileId);
  for (final v in visits) {
    final title = (v.reason != null && v.reason!.trim().isNotEmpty)
        ? v.reason!.trim()
        : (v.providerName != null && v.providerName!.trim().isNotEmpty
            ? '${v.providerName!.trim()} visit'
            : 'Visit');
    final detail = [
      if (v.providerName != null && v.providerName!.trim().isNotEmpty)
        v.providerName!.trim(),
      if (v.providerClinic != null && v.providerClinic!.trim().isNotEmpty)
        v.providerClinic!.trim(),
      if (v.notes != null && v.notes!.trim().isNotEmpty) v.notes!.trim(),
      if (v.diagnosis != null && v.diagnosis!.trim().isNotEmpty)
        v.diagnosis!.trim(),
    ].join(' · ');
    out.add(
      MedicalTimelineEvent(
        id: 'visit:${v.id}',
        category: MedicalTimelineCategory.visits,
        at: v.visitedAt,
        title: title,
        detail: detail.isEmpty ? 'Visit on file' : detail,
      ),
    );
  }

  out.sort((a, b) => b.at.compareTo(a.at));
  return out;
}

/// Timeline rail + filter chips.
class MedicalTimelineView extends StatefulWidget {
  const MedicalTimelineView({
    super.key,
    required this.events,
    this.onEventTap,
  });

  final List<MedicalTimelineEvent> events;
  final ValueChanged<MedicalTimelineEvent>? onEventTap;

  @override
  State<MedicalTimelineView> createState() => _MedicalTimelineViewState();
}

class _MedicalTimelineViewState extends State<MedicalTimelineView> {
  MedicalTimelineCategory? _filter; // null = All

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == null
        ? widget.events
        : [
            for (final e in widget.events)
              if (e.category == _filter) e,
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chip(null, 'All'),
              for (final c in MedicalTimelineCategory.values)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _chip(c, c.label),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text(
              widget.events.isEmpty
                  ? 'Nothing on the timeline yet. Add conditions, medicines, vaccinations, surgeries, or visits to see them here.'
                  : 'No items in this filter.',
              style: TextStyle(color: BodylineColors.inkSubtle, fontSize: 14),
            ),
          )
        else
          for (var i = 0; i < filtered.length; i++)
            _TimelineRow(
              event: filtered[i],
              isLast: i == filtered.length - 1,
              onTap: widget.onEventTap == null
                  ? null
                  : () => widget.onEventTap!(filtered[i]),
            ),
      ],
    );
  }

  Widget _chip(MedicalTimelineCategory? value, String label) {
    final selected = _filter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: BodylineColors.ink,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: selected ? BodylineColors.onInk : BodylineColors.ink,
      ),
      backgroundColor: BodylineColors.surface,
      side: BorderSide(
        color: selected ? BodylineColors.ink : BodylineColors.border,
      ),
      onSelected: (_) => setState(() => _filter = value),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.event,
    required this.isLast,
    this.onTap,
  });

  final MedicalTimelineEvent event;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final month = DateFormat('MMM yyyy').format(event.at);
    final cat = event.category;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 78,
            child: Padding(
              padding: const EdgeInsets.only(top: 14, right: 8),
              child: Text(
                month,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BodylineColors.inkSubtle,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: cat.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: BodylineColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Material(
                color: BodylineColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
                  side: BorderSide(color: BodylineColors.border),
                ),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (event.detail.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  event.detail,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: BodylineColors.inkSubtle,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cat.tint,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            cat.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: cat.tagText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
