import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../theme/tokens.dart';

/// Reports, medicines and notes in one chronological list.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.store,
    this.embedded = false,
  });

  final LocalStore store;
  final bool embedded;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineItem {
  _TimelineItem({
    required this.at,
    required this.kind,
    required this.title,
    required this.subtitle,
    this.isPeriod = false,
  });
  final DateTime at;
  final String kind; // report | medicine | note
  final String title;
  final String subtitle;
  final bool isPeriod;
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<_TimelineItem> _items = [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TimelineScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  Future<void> _load() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      if (mounted) setState(() { _items = []; _loading = false; });
      return;
    }
    final items = <_TimelineItem>[];

    for (final r in widget.store.reports.where((r) => r.profileId == pid)) {
      items.add(_TimelineItem(
        at: r.collectedAt,
        kind: 'report',
        title: r.title.isNotEmpty ? r.title : 'Lab report',
        subtitle: 'Report',
      ));
    }

    final doses = await widget.store.listTodaysDoses(pid);
    for (final d in doses.where((d) => d.isDone)) {
      items.add(_TimelineItem(
        at: d.scheduledFor,
        kind: 'medicine',
        title: d.name,
        subtitle: d.logStatus == 'skipped' ? 'Skipped' : 'Taken',
      ));
    }

    // Recent medication_log beyond today — sample last 60 days via raw if needed.
    // Keep thin: also pull notes.
    final notes = await widget.store.listNotes(pid);
    for (final n in notes) {
      final kind = (n['when_kind'] as String?) ?? 'none';
      DateTime at;
      var period = false;
      if (kind != 'none' && (n['start_ymd'] as String?) != null) {
        try {
          at = DateFormat('yyyy-MM-dd').parse(n['start_ymd'] as String);
        } catch (_) {
          at = DateTime.fromMillisecondsSinceEpoch((n['updated_at'] as int?) ?? 0);
        }
        period = kind == 'period';
      } else {
        at = DateTime.fromMillisecondsSinceEpoch((n['updated_at'] as int?) ?? 0);
      }
      items.add(_TimelineItem(
        at: at,
        kind: 'note',
        title: n['title'] as String? ?? 'Note',
        subtitle: period
            ? 'Note · ${(n['start_ymd'] as String?) ?? ''} → ${(n['end_ymd'] as String?) ?? ''}'
            : 'Note',
        isPeriod: period,
      ));
    }

    items.sort((a, b) => b.at.compareTo(a.at));
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty
            ? Center(
                child: Text(
                  'Nothing on the timeline yet.',
                  style: TextStyle(color: BodylineColors.inkSubtle),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final it = _items[i];
                  final side = BorderSide(
                    color: it.kind == 'note'
                        ? const Color(0xFFE07A3D)
                        : BodylineColors.border,
                    width: it.kind == 'note' ? 1.5 : 1,
                  );
                  return Material(
                    color: BodylineColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(BodylineRadii.cardSmall),
                      side: side,
                    ),
                    child: ListTile(
                      leading: Icon(
                        it.kind == 'report'
                            ? Icons.description_outlined
                            : it.kind == 'medicine'
                                ? Icons.medication_outlined
                                : Icons.sticky_note_2_outlined,
                        color: BodylineColors.teal,
                      ),
                      title: Text(
                        it.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${it.subtitle} · ${DateFormat.yMMMd().format(it.at)}'
                        '${it.isPeriod ? " (period)" : ""}',
                      ),
                    ),
                  );
                },
              );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(title: const Text('Timeline')),
      body: body,
    );
  }
}
