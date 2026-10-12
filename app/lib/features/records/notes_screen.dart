import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/habits_notes_store.dart';
import '../../data/local_store.dart';
import '../../theme/tokens.dart';

/// Your notes — Labs › Notes (FR-010). Track observations, not diagnoses.
class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    required this.store,
    required this.onChanged,
    this.embedded = false,
  });

  final LocalStore store;
  final VoidCallback onChanged;
  final bool embedded;

  @override
  State<NotesScreen> createState() => NotesScreenState();
}

class NotesScreenState extends State<NotesScreen> {
  List<Map<String, Object?>> _notes = [];
  String? _selectedId;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NotesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  Future<void> _load() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      if (!mounted) return;
      setState(() {
        _notes = [];
        _selectedId = null;
        _loading = false;
      });
      return;
    }
    final notes = await widget.store.listNotes(pid);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
      if (_selectedId == null && notes.isNotEmpty) {
        _selectedId = notes.first['id'] as String?;
      } else if (_selectedId != null &&
          !notes.any((n) => n['id'] == _selectedId)) {
        _selectedId = notes.isEmpty ? null : notes.first['id'] as String?;
      }
    });
  }

  Future<void> promptAdd() => _add();

  Future<void> _add({Map<String, Object?>? existing}) async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;

    final title = TextEditingController(text: existing?['title'] as String? ?? '');
    final body = TextEditingController(text: existing?['body'] as String? ?? '');
    final tagsCtrl = TextEditingController(
      text: noteTags(existing ?? {}).join(', '),
    );
    final chartsCtrl = TextEditingController(
      text: noteChartCodes(existing ?? {}).join(', '),
    );
    var doctor = ((existing?['include_in_doctor_summary'] as int?) ?? 0) == 1;
    var whenKind = (existing?['when_kind'] as String?) ?? 'none';
    DateTime? start = _parseYmd(existing?['start_ymd'] as String?);
    DateTime? end = _parseYmd(existing?['end_ymd'] as String?);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New note' : 'Edit note'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: body,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      hintText: 'Things reports and prescriptions don’t say',
                    ),
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'When',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'none', label: Text('No date')),
                      ButtonSegment(value: 'day', label: Text('One day')),
                      ButtonSegment(value: 'period', label: Text('Period')),
                    ],
                    selected: {whenKind},
                    onSelectionChanged: (s) => setLocal(() => whenKind = s.first),
                  ),
                  if (whenKind == 'day' || whenKind == 'period') ...[
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        whenKind == 'period' ? 'From' : 'Date',
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        start == null
                            ? 'Pick a date'
                            : DateFormat.yMMMd().format(start!),
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: start ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) setLocal(() => start = d);
                      },
                    ),
                  ],
                  if (whenKind == 'period')
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('To', style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                        end == null
                            ? 'Pick end date'
                            : DateFormat.yMMMd().format(end!),
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: end ?? start ?? DateTime.now(),
                          firstDate: start ?? DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) setLocal(() => end = d);
                      },
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: tagsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tags (optional)',
                      hintText: 'travel, diet, …',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: chartsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Show on charts (optional)',
                      hintText: 'HbA1c, glucose',
                      helperText:
                          'Pins appear beside those trends — for context, not cause and effect.',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include in doctor summary (opt-in)'),
                    value: doctor,
                    onChanged: (v) => setLocal(() => doctor = v ?? false),
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
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || title.text.trim().isEmpty) {
      title.dispose();
      body.dispose();
      tagsCtrl.dispose();
      chartsCtrl.dispose();
      return;
    }

    final tags = tagsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final charts = chartsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    String? startY;
    String? endY;
    if (whenKind == 'day' && start != null) {
      startY = DateFormat('yyyy-MM-dd').format(start!);
      endY = startY;
    } else if (whenKind == 'period' && start != null) {
      startY = DateFormat('yyyy-MM-dd').format(start!);
      endY = DateFormat('yyyy-MM-dd').format(end ?? start!);
    } else {
      whenKind = 'none';
    }

    if (existing == null) {
      final id = await widget.store.addNote(
        profileId: pid,
        title: title.text.trim(),
        body: body.text.trim(),
        includeInDoctorSummary: doctor,
        whenKind: whenKind,
        startYmd: startY,
        endYmd: endY,
        tags: tags,
        chartCodes: charts,
      );
      widget.onChanged();
      await _load();
      if (mounted) setState(() => _selectedId = id);
    } else {
      await widget.store.updateNote(
        id: existing['id']! as String,
        title: title.text.trim(),
        body: body.text.trim(),
        includeInDoctorSummary: doctor,
        whenKind: whenKind,
        startYmd: startY,
        endYmd: endY,
        tags: tags,
        chartCodes: charts,
      );
      widget.onChanged();
      await _load();
    }

    title.dispose();
    body.dispose();
    tagsCtrl.dispose();
    chartsCtrl.dispose();
  }

  DateTime? _parseYmd(String? ymd) {
    if (ymd == null || ymd.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd').parse(ymd);
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?>? get _selected {
    for (final n in _notes) {
      if (n['id'] == _selectedId) return n;
    }
    return null;
  }

  String _whenLabel(Map<String, Object?> n) {
    final kind = (n['when_kind'] as String?) ?? 'none';
    if (kind == 'none') return 'No date';
    final s = n['start_ymd'] as String?;
    final e = n['end_ymd'] as String?;
    if (kind == 'day' && s != null) {
      try {
        return DateFormat.yMMMd().format(DateFormat('yyyy-MM-dd').parse(s));
      } catch (_) {
        return s;
      }
    }
    if (kind == 'period' && s != null) {
      return '$s → ${e ?? s}';
    }
    return 'Dated';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final desktop = MediaQuery.sizeOf(context).width >= 900;

    final list = _notes.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                'No notes yet.\nThings your reports and prescriptions don’t say.',
                textAlign: TextAlign.center,
                style: TextStyle(color: BodylineColors.inkSubtle, height: 1.4),
              ),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: _notes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final n = _notes[i];
              final id = n['id'] as String;
              final tags = noteTags(n);
              final charts = noteChartCodes(n);
              final selected = id == _selectedId;
              return Material(
                color: selected ? BodylineColors.tealTint : BodylineColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
                  side: BorderSide(
                    color: selected ? BodylineColors.teal : BodylineColors.border,
                  ),
                ),
                child: ListTile(
                  onTap: () => setState(() => _selectedId = id),
                  title: Text(
                    n['title'] as String? ?? 'Note',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      _whenLabel(n),
                      if (tags.isNotEmpty) tags.join(' · '),
                      if (charts.isNotEmpty) 'On: ${charts.join(", ")}',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          );

    final sel = _selected;
    final detail = sel == null
        ? Center(
            child: Text(
              _notes.isEmpty ? '' : 'Select a note',
              style: TextStyle(color: BodylineColors.inkSubtle),
            ),
          )
        : _NoteDetail(
            note: sel,
            onEdit: () => _add(existing: sel),
            onDelete: () async {
              await widget.store.softDeleteNote(sel['id']! as String);
              widget.onChanged();
              await _load();
            },
          );

    late final Widget body;
    if (desktop || widget.embedded) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                  child: Text(
                    'Undated first, then by date · ${_notes.length} notes',
                    style: TextStyle(
                      fontSize: 13,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                ),
                Expanded(child: list),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: BodylineColors.divider),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _add,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New note'),
                      style: FilledButton.styleFrom(
                        backgroundColor: BodylineColors.ink,
                      ),
                    ),
                  ),
                ),
                Expanded(child: detail),
              ],
            ),
          ),
        ],
      );
    } else {
      body = list;
    }

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(title: const Text('Notes')),
      floatingActionButton: desktop
          ? null
          : FloatingActionButton(
              onPressed: _add,
              child: const Icon(Icons.add),
            ),
      body: desktop
          ? body
          : (sel == null
              ? body
              : Column(
                  children: [
                    Expanded(flex: 2, child: list),
                    const Divider(height: 1),
                    Expanded(flex: 3, child: detail),
                  ],
                )),
    );
  }
}

class _NoteDetail extends StatelessWidget {
  const _NoteDetail({
    required this.note,
    required this.onDelete,
    required this.onEdit,
  });
  final Map<String, Object?> note;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final updated = DateTime.fromMillisecondsSinceEpoch(
      (note['updated_at'] as int?) ?? 0,
    );
    final doctor = (note['include_in_doctor_summary'] as int? ?? 0) == 1;
    final tags = noteTags(note);
    final charts = noteChartCodes(note);
    final whenKind = (note['when_kind'] as String?) ?? 'none';
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 40),
      children: [
        Text(
          note['title'] as String? ?? 'Note',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: 'Fraunces',
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Last edited ${DateFormat.yMMMd().add_jm().format(updated)}',
          style: TextStyle(fontSize: 13, color: BodylineColors.inkSubtle),
        ),
        if (whenKind != 'none') ...[
          const SizedBox(height: 4),
          Text(
            whenKind == 'period'
                ? 'Period ${(note['start_ymd'] as String?) ?? ''} → ${(note['end_ymd'] as String?) ?? ''}'
                : 'Date ${(note['start_ymd'] as String?) ?? ''}',
            style: TextStyle(fontSize: 13, color: BodylineColors.inkSubtle),
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [for (final t in tags) Chip(label: Text(t))],
          ),
        ],
        const SizedBox(height: 20),
        Text(
          note['body'] as String? ?? '',
          style: const TextStyle(fontSize: 18, height: 1.45),
        ),
        if (charts.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Shown on: ${charts.join(", ")} — context only, not cause and effect.',
            style: TextStyle(fontSize: 13, color: BodylineColors.inkSubtle),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          doctor
              ? 'Included in doctor summary when you share it.'
              : 'Not in the doctor summary. Only you see it.',
          style: TextStyle(fontSize: 13, color: BodylineColors.inkSubtle),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            TextButton(onPressed: onEdit, child: const Text('Edit')),
            TextButton(
              onPressed: onDelete,
              style: TextButton.styleFrom(foregroundColor: BodylineColors.danger),
              child: const Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }
}
