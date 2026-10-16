import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../data/habits_notes_store.dart';
import '../../data/local_store.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../../widgets/chart_link_picker.dart';

enum _NotesFilter { all, none, day, period, linked }

/// Your notes — Labs › Notes (FR-010). Track observations, not diagnoses.
class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    required this.store,
    required this.onChanged,
    this.embedded = false,
    this.onOpenChart,
    this.searchController,
  });

  final LocalStore store;
  final VoidCallback onChanged;
  final bool embedded;
  /// Opens Tests focused on this chart code (desktop shell).
  final ValueChanged<String>? onOpenChart;
  /// When set (desktop shell), search lives in the top bar — no in-page header.
  final TextEditingController? searchController;

  @override
  State<NotesScreen> createState() => NotesScreenState();
}

class NotesScreenState extends State<NotesScreen> {
  List<Map<String, Object?>> _notes = [];
  String? _selectedId;
  String? _loadedProfileId;
  var _loading = true;
  var _loadGen = 0;
  _NotesFilter _filter = _NotesFilter.all;
  String? _tagFilter;
  TextEditingController? _ownedSearch;
  List<String> _customTags = [];

  static const _presetTags = <String>[
    'Illness',
    'Doctor said',
    'Travel',
    'Diet',
    'Other',
  ];
  static const _customTagsPrefsKey = 'vitalog.custom_note_tags';

  TextEditingController get _search =>
      widget.searchController ?? _ownedSearch!;

  @override
  void initState() {
    super.initState();
    if (widget.searchController == null) {
      _ownedSearch = TextEditingController();
    }
    _search.addListener(() {
      if (mounted) setState(() {});
    });
    _loadCustomTags();
    _load();
  }

  @override
  void dispose() {
    _ownedSearch?.dispose();
    super.dispose();
  }

  Future<void> _loadCustomTags() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_customTagsPrefsKey) ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _customTags = [
        for (final t in raw)
          if (t.trim().isNotEmpty) t.trim(),
      ];
    });
  }

  Future<void> _persistCustomTag(String tag) async {
    final cleaned = tag.trim();
    if (cleaned.isEmpty) return;
    final lower = cleaned.toLowerCase();
    if (_presetTags.any((p) => p.toLowerCase() == lower)) return;
    if (_customTags.any((c) => c.toLowerCase() == lower)) return;
    final next = [..._customTags, cleaned]..sort();
    setState(() => _customTags = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customTagsPrefsKey, next);
  }

  List<String> get _allTagOptions {
    final fromNotes = <String>{};
    for (final n in _notes) {
      for (final t in noteTags(n)) {
        fromNotes.add(_canonicalTag(t));
      }
    }
    final out = <String>{..._presetTags, ..._customTags, ...fromNotes};
    final list = out.toList()
      ..sort((a, b) {
        final ai = _presetTags.indexOf(a);
        final bi = _presetTags.indexOf(b);
        if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
        if (ai >= 0) return -1;
        if (bi >= 0) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return list;
  }

  @override
  void didUpdateWidget(covariant NotesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_profileId != _loadedProfileId) {
      _load();
    }
  }

  /// Public so the shell can refresh when the Notes tab is selected.
  Future<void> reload() => _load();

  Future<void> promptAdd() => _add();

  String? get _profileId {
    final id = widget.store.activeProfileId;
    if (id != null) return id;
    return widget.store.profiles.isEmpty ? null : widget.store.profiles.first.id;
  }

  Future<void> _load({bool quiet = false}) async {
    final gen = ++_loadGen;
    final pid = _profileId;
    if (pid == null) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _notes = [];
        _selectedId = null;
        _loadedProfileId = null;
        _loading = false;
      });
      return;
    }
    if (!quiet && mounted) {
      setState(() => _loading = _notes.isEmpty);
    }
    try {
      final notes = await widget.store.listNotes(pid);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _notes = notes;
        _loadedProfileId = pid;
        _loading = false;
        if (_selectedId == null && notes.isNotEmpty) {
          _selectedId = notes.first['id'] as String?;
        } else if (_selectedId != null &&
            !notes.any((n) => n['id'] == _selectedId)) {
          _selectedId = notes.isEmpty ? null : notes.first['id'] as String?;
        }
      });
    } catch (e, st) {
      // ignore: avoid_print
      print('NotesScreen._load failed: $e\n$st');
      if (!mounted || gen != _loadGen) return;
      setState(() => _loading = false);
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load notes: $e')),
        );
      }
    }
  }

  Future<void> _add({Map<String, Object?>? existing}) async {
    final pid = _profileId;
    if (pid == null) return;

    final title = TextEditingController(text: existing?['title'] as String? ?? '');
    final body = TextEditingController(text: existing?['body'] as String? ?? '');
    var selectedTags = {...noteTags(existing ?? {})};
    final existingCharts = noteChartCodes(existing ?? {});
    var showOnAllCharts = chartCodesAreAll(existingCharts);
    var selectedCharts = {
      for (final c in existingCharts)
        if (c != kChartCodeAll) c,
    };
    var doctor = ((existing?['include_in_doctor_summary'] as int?) ?? 0) == 1;
    var whenKind = (existing?['when_kind'] as String?) ?? 'none';
    DateTime? start = _parseYmd(existing?['start_ymd'] as String?);
    DateTime? end = _parseYmd(existing?['end_ymd'] as String?);

    final knownCharts = <String>{
      for (final o in widget.store.observations)
        if (o.profileId == pid) o.parameterName,
      for (final o in widget.store.observations)
        if (o.profileId == pid) o.parameterCode,
      ...selectedCharts,
    }.toList()
      ..sort();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New note' : 'Edit note'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: body,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      hintText: 'Things reports and prescriptions don’t say',
                    ),
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    autofocus: existing == null,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Title (optional)',
                    ),
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
                    onSelectionChanged: (s) =>
                        setLocal(() => whenKind = s.first),
                  ),
                  if (whenKind == 'day' || whenKind == 'period') ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ListTile(
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
                            trailing: const Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                            ),
                            onTap: () async {
                              final d = await showDatePicker(
                                context: ctx,
                                initialDate: start ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)),
                              );
                              if (d != null) {
                                setLocal(() {
                                  start = d;
                                  if (whenKind == 'day') end = d;
                                  if (end != null && end!.isBefore(d)) {
                                    end = d;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        if (whenKind == 'period') ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'To',
                                style: TextStyle(fontSize: 14),
                              ),
                              subtitle: Text(
                                end == null
                                    ? 'Pick end date'
                                    : DateFormat.yMMMd().format(end!),
                              ),
                              trailing: const Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                              ),
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: ctx,
                                  initialDate: end ?? start ?? DateTime.now(),
                                  firstDate: start ?? DateTime(2000),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 365)),
                                );
                                if (d != null) setLocal(() => end = d);
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      whenKind == 'period'
                          ? 'Shows as a shaded band across this period on linked charts.'
                          : 'Shows as a pin on this day on linked charts.',
                      style: TextStyle(
                        fontSize: 12,
                        color: BodylineColors.inkSubtle,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Tag optional',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in _allTagOptions)
                        FilterChip(
                          label: Text(tag),
                          selected: selectedTags.contains(tag),
                          onSelected: (v) => setLocal(() {
                            selectedTags = {if (v) tag};
                          }),
                          selectedColor: _tagStyle(tag).bg,
                          labelStyle: TextStyle(
                            color: selectedTags.contains(tag)
                                ? _tagStyle(tag).fg
                                : BodylineColors.inkMuted,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          side: BorderSide(
                            color: selectedTags.contains(tag)
                                ? _tagStyle(tag).fg.withValues(alpha: 0.45)
                                : BodylineColors.border,
                          ),
                          showCheckmark: false,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _AddCustomTagField(
                    onAdd: (tag) async {
                      await _persistCustomTag(tag);
                      setLocal(() => selectedTags = {tag});
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Show on charts',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('All charts'),
                    subtitle: const Text(
                      'Pin this note on every trend — for context, not cause and effect.',
                    ),
                    value: showOnAllCharts,
                    onChanged: (v) => setLocal(() {
                      showOnAllCharts = v;
                      if (v) selectedCharts.clear();
                    }),
                  ),
                  if (!showOnAllCharts) ...[
                    Text(
                      selectedCharts.isEmpty
                          ? 'Search and add a chart'
                          : 'Shows on ${selectedCharts.length} chart${selectedCharts.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: BodylineColors.inkSubtle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ChartLinkPicker(
                      options: knownCharts,
                      selected: selectedCharts,
                      labelFor: (c) => c,
                      onChanged: (next) => setLocal(() {
                        selectedCharts
                          ..clear()
                          ..addAll(next);
                      }),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Add to doctor summary'),
                    subtitle: Text(
                      doctor
                          ? 'Included when you share a doctor summary.'
                          : 'Off. Only you see this note.',
                      style: TextStyle(
                        fontSize: 12,
                        color: BodylineColors.inkSubtle,
                      ),
                    ),
                    value: doctor,
                    onChanged: (v) => setLocal(() => doctor = v),
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
              child: const Text('Save note'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) {
      title.dispose();
      body.dispose();
      return;
    }

    var titleText = title.text.trim();
    final bodyText = body.text.trim();
    if (titleText.isEmpty && bodyText.isEmpty) {
      title.dispose();
      body.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add a title or note text to save.')),
        );
      }
      return;
    }
    if (titleText.isEmpty) {
      final line = bodyText.split('\n').first.trim();
      titleText = line.length <= 60 ? line : '${line.substring(0, 57)}...';
    }

    final tags = selectedTags.toList();
    for (final tag in tags) {
      await _persistCustomTag(tag);
    }
    final charts = showOnAllCharts
        ? const [kChartCodeAll]
        : selectedCharts.toList();
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
        title: titleText,
        body: bodyText,
        includeInDoctorSummary: doctor,
        whenKind: whenKind,
        startYmd: startY,
        endYmd: endY,
        tags: tags,
        chartCodes: charts,
      );
      final row = await widget.store.getNote(id);
      if (mounted) {
        setState(() {
          if (row != null) {
            _notes = [row, ..._notes.where((n) => n['id'] != id)];
          }
          _selectedId = id;
          _loadedProfileId = pid;
          _loading = false;
        });
      }
      widget.onChanged();
      await _load(quiet: true);
    } else {
      final id = existing['id']! as String;
      await widget.store.updateNote(
        id: id,
        title: titleText,
        body: bodyText,
        includeInDoctorSummary: doctor,
        whenKind: whenKind,
        startYmd: startY,
        endYmd: endY,
        tags: tags,
        chartCodes: charts,
      );
      widget.onChanged();
      await _load(quiet: true);
    }

    title.dispose();
    body.dispose();
  }

  Future<void> _setDoctor(Map<String, Object?> note, bool value) async {
    final id = note['id'] as String?;
    if (id == null) return;
    await widget.store.updateNote(
      id: id,
      title: note['title'] as String? ?? '',
      body: note['body'] as String? ?? '',
      includeInDoctorSummary: value,
      whenKind: (note['when_kind'] as String?) ?? 'none',
      startYmd: note['start_ymd'] as String?,
      endYmd: note['end_ymd'] as String?,
      tags: noteTags(note),
      chartCodes: noteChartCodes(note),
    );
    widget.onChanged();
    await _load(quiet: true);
  }

  Future<void> _confirmDelete(Map<String, Object?> note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This removes the note from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: BodylineColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.softDeleteNote(note['id']! as String);
    widget.onChanged();
    await _load();
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

  List<Map<String, Object?>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final n in _notes)
        if (_matchesFilter(n) && _matchesSearch(n, q)) n,
    ];
  }

  bool _matchesFilter(Map<String, Object?> n) {
    if (_tagFilter != null) {
      final tags = noteTags(n).map((t) => t.toLowerCase());
      if (!tags.contains(_tagFilter!.toLowerCase())) return false;
    }
    final kind = (n['when_kind'] as String?) ?? 'none';
    switch (_filter) {
      case _NotesFilter.all:
        return true;
      case _NotesFilter.none:
        return kind == 'none';
      case _NotesFilter.day:
        return kind == 'day';
      case _NotesFilter.period:
        return kind == 'period';
      case _NotesFilter.linked:
        return noteChartCodes(n).isNotEmpty;
    }
  }

  bool _matchesSearch(Map<String, Object?> n, String q) {
    if (q.isEmpty) return true;
    final title = (n['title'] as String? ?? '').toLowerCase();
    final body = (n['body'] as String? ?? '').toLowerCase();
    final tags = noteTags(n).join(' ').toLowerCase();
    final charts = noteChartCodes(n).join(' ').toLowerCase();
    return title.contains(q) ||
        body.contains(q) ||
        tags.contains(q) ||
        charts.contains(q);
  }

  int _count(_NotesFilter f) {
    return _notes.where((n) {
      final kind = (n['when_kind'] as String?) ?? 'none';
      switch (f) {
        case _NotesFilter.all:
          return true;
        case _NotesFilter.none:
          return kind == 'none';
        case _NotesFilter.day:
          return kind == 'day';
        case _NotesFilter.period:
          return kind == 'period';
        case _NotesFilter.linked:
          return noteChartCodes(n).isNotEmpty;
      }
    }).length;
  }

  Map<String, int> get _tagCounts {
    final out = <String, int>{};
    for (final n in _notes) {
      for (final t in noteTags(n)) {
        final key = _canonicalTag(t);
        out[key] = (out[key] ?? 0) + 1;
      }
    }
    return out;
  }

  String _canonicalTag(String t) {
    for (final p in _presetTags) {
      if (p.toLowerCase() == t.toLowerCase()) return p;
    }
    return t;
  }

  String _chartLabel(String code) {
    if (code == kChartCodeAll || code == 'all charts') return 'All charts';
    final pid = _profileId;
    for (final o in widget.store.observations) {
      if (pid != null && o.profileId != pid) continue;
      if (o.parameterCode == code || o.parameterName == code) {
        return o.parameterName;
      }
    }
    return code;
  }

  String _whenHeader(Map<String, Object?> n) {
    final kind = (n['when_kind'] as String?) ?? 'none';
    if (kind == 'none') return 'No date';
    final s = _parseYmd(n['start_ymd'] as String?);
    final e = _parseYmd(n['end_ymd'] as String?);
    if (kind == 'day' && s != null) {
      return DateFormat('d MMM yyyy').format(s);
    }
    if (kind == 'period' && s != null) {
      final end = e ?? s;
      if (s.year == end.year && s.month == end.month) {
        return '${s.day} – ${end.day} ${DateFormat('MMM yyyy').format(end)}';
      }
      if (s.year == end.year) {
        return '${DateFormat('d MMM').format(s)} – ${DateFormat('d MMM yyyy').format(end)}';
      }
      return '${DateFormat('d MMM yyyy').format(s)} – ${DateFormat('d MMM yyyy').format(end)}';
    }
    return 'Dated';
  }

  String _detailWhenLine(Map<String, Object?> n) {
    final kind = (n['when_kind'] as String?) ?? 'none';
    if (kind == 'none') return 'No date';
    if (kind == 'day') return 'One day · ${_whenHeader(n)}';
    if (kind == 'period') return 'Period · ${_whenHeader(n)}';
    return _whenHeader(n);
  }

  IconData _whenIcon(String kind) {
    switch (kind) {
      case 'day':
        return Icons.calendar_today_outlined;
      case 'period':
        return Icons.horizontal_rule;
      default:
        return Icons.event_busy_outlined;
    }
  }

  String _relativeEdited(int updatedMs) {
    if (updatedMs <= 0) return 'Unknown';
    final updated = DateTime.fromMillisecondsSinceEpoch(updatedMs);
    final days = DateTime.now().difference(updated).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 14) return '$days days ago';
    return DateFormat.yMMMd().format(updated);
  }

  List<MapEntry<String, List<Map<String, Object?>>>> _grouped(
    List<Map<String, Object?>> notes,
  ) {
    final undated = <Map<String, Object?>>[];
    final byYear = <int, List<Map<String, Object?>>>{};
    for (final n in notes) {
      final kind = (n['when_kind'] as String?) ?? 'none';
      final start = _parseYmd(n['start_ymd'] as String?);
      if (kind == 'none' || start == null) {
        undated.add(n);
      } else {
        byYear.putIfAbsent(start.year, () => []).add(n);
      }
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final y in years) {
      byYear[y]!.sort((a, b) {
        final as = (a['start_ymd'] as String?) ?? '';
        final bs = (b['start_ymd'] as String?) ?? '';
        return bs.compareTo(as);
      });
    }
    return [
      if (undated.isNotEmpty) MapEntry('NO DATE', undated),
      for (final y in years) MapEntry('$y', byYear[y]!),
    ];
  }

  Future<void> _promptLinkCharts(Map<String, Object?> note) async {
    final pid = _profileId;
    if (pid == null) return;
    final existing = noteChartCodes(note);
    var showOnAllCharts = chartCodesAreAll(existing);
    final selected = {
      for (final c in existing)
        if (c != kChartCodeAll) c,
    };
    final knownCharts = <String>{
      for (final o in widget.store.observations)
        if (o.profileId == pid) o.parameterName,
      for (final o in widget.store.observations)
        if (o.profileId == pid) o.parameterCode,
      ...selected,
    }.toList()
      ..sort();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Link charts'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('All charts'),
                  subtitle: const Text(
                    'Pin on every trend — for context, not cause and effect.',
                  ),
                  value: showOnAllCharts,
                  onChanged: (v) => setLocal(() {
                    showOnAllCharts = v;
                    if (v) selected.clear();
                  }),
                ),
                if (!showOnAllCharts)
                  ChartLinkPicker(
                    options: knownCharts,
                    selected: selected,
                    labelFor: _chartLabel,
                    onChanged: (next) => setLocal(() {
                      selected
                        ..clear()
                        ..addAll(next);
                    }),
                  ),
              ],
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
    if (ok != true) return;
    await widget.store.updateNote(
      id: note['id']! as String,
      title: note['title'] as String? ?? '',
      body: note['body'] as String? ?? '',
      includeInDoctorSummary:
          (note['include_in_doctor_summary'] as int? ?? 0) == 1,
      whenKind: (note['when_kind'] as String?) ?? 'none',
      startYmd: note['start_ymd'] as String?,
      endYmd: note['end_ymd'] as String?,
      tags: noteTags(note),
      chartCodes: showOnAllCharts ? const [kChartCodeAll] : selected.toList(),
    );
    widget.onChanged();
    await _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    BodylineColors.syncFrom(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final desktop = MediaQuery.sizeOf(context).width >= 900;
    final filtered = _filtered;
    final groups = _grouped(filtered);
    final sel = _selected;

    final body = desktop || widget.embedded
        ? _buildDesktop(context, groups, filtered, sel)
        : _buildMobile(context, groups, filtered, sel);

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
      body: body,
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    List<MapEntry<String, List<Map<String, Object?>>>> groups,
    List<Map<String, Object?>> filtered,
    Map<String, Object?>? sel,
  ) {
    final tagChoices = _tagCounts.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final tagValue =
        (_tagFilter != null && tagChoices.contains(_tagFilter)) ? _tagFilter : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesktopLayout.mainPaddingH,
        8,
        DesktopLayout.mainPaddingH,
        DesktopLayout.mainPaddingV,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.embedded) ...[
            _HeaderBar(
              count: _notes.length,
              search: _search,
              onNew: _add,
            ),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: DesktopLayout.recordsMasterCol,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _NotesWhenFilterPill(
                            filter: _filter,
                            counts: {
                              _NotesFilter.all: _count(_NotesFilter.all),
                              _NotesFilter.none: _count(_NotesFilter.none),
                              _NotesFilter.day: _count(_NotesFilter.day),
                              _NotesFilter.period: _count(_NotesFilter.period),
                              _NotesFilter.linked: _count(_NotesFilter.linked),
                            },
                            onChanged: (f) => setState(() {
                              _filter = f;
                              // Keep tag filter independent.
                            }),
                          ),
                          if (tagChoices.isNotEmpty)
                            _NotesTagFilterPill(
                              selected: tagValue,
                              tags: tagChoices,
                              counts: _tagCounts,
                              onChanged: (tag) => setState(() {
                                _tagFilter = tag;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _NotesListPane(
                          groups: groups,
                          empty: _notes.isEmpty,
                          filteredEmpty:
                              filtered.isEmpty && _notes.isNotEmpty,
                          selectedId: _selectedId,
                          whenHeader: _whenHeader,
                          chartLabel: _chartLabel,
                          onSelect: (id) =>
                              setState(() => _selectedId = id),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DesktopLayout.mainGap),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                    decoration: BoxDecoration(
                      color: BodylineColors.surface,
                      borderRadius:
                          BorderRadius.circular(BodylineRadii.card),
                      border: Border.all(color: BodylineColors.border),
                    ),
                    child: sel == null
                        ? Center(
                            child: Text(
                              filtered.isEmpty ? '' : 'Select a note',
                              style: TextStyle(
                                color: BodylineColors.inkSubtle,
                              ),
                            ),
                          )
                        : _NoteDetail(
                            note: sel,
                            whenLine: _detailWhenLine(sel),
                            whenIcon: _whenIcon(
                              (sel['when_kind'] as String?) ?? 'none',
                            ),
                            chartLabel: _chartLabel,
                            relativeEdited: _relativeEdited,
                            onEdit: () => _add(existing: sel),
                            onDelete: () => _confirmDelete(sel),
                            onDoctorChanged: (v) => _setDoctor(sel, v),
                            onOpenChart: widget.onOpenChart,
                            onLink: () => _promptLinkCharts(sel),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(
    BuildContext context,
    List<MapEntry<String, List<Map<String, Object?>>>> groups,
    List<Map<String, Object?>> filtered,
    Map<String, Object?>? sel,
  ) {
    final list = _NotesListPane(
      groups: groups,
      empty: _notes.isEmpty,
      filteredEmpty: filtered.isEmpty && _notes.isNotEmpty,
      selectedId: _selectedId,
      whenHeader: _whenHeader,
      chartLabel: _chartLabel,
      onSelect: (id) => setState(() => _selectedId = id),
    );
    if (sel == null) return list;
    return Column(
      children: [
        Expanded(flex: 2, child: list),
        const Divider(height: 1),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _NoteDetail(
              note: sel,
              whenLine: _detailWhenLine(sel),
              whenIcon: _whenIcon((sel['when_kind'] as String?) ?? 'none'),
              chartLabel: _chartLabel,
              relativeEdited: _relativeEdited,
              onEdit: () => _add(existing: sel),
              onDelete: () => _confirmDelete(sel),
              onDoctorChanged: (v) => _setDoctor(sel, v),
              onOpenChart: widget.onOpenChart,
              onLink: () => _promptLinkCharts(sel),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.count,
    required this.search,
    required this.onNew,
  });

  final int count;
  final TextEditingController search;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notes',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Things your reports and prescriptions don’t say · $count notes',
                style: TextStyle(
                  fontSize: 13,
                  color: BodylineColors.inkSubtle,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 220,
          height: 40,
          child: TextField(
            controller: search,
            decoration: InputDecoration(
              hintText: 'Search notes',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              filled: true,
              fillColor: BodylineColors.chip,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: onNew,
          style: FilledButton.styleFrom(
            backgroundColor: BodylineColors.ink,
            foregroundColor: BodylineColors.onInk,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New note'),
        ),
      ],
    );
  }
}

class _NotesWhenFilterPill extends StatelessWidget {
  const _NotesWhenFilterPill({
    required this.filter,
    required this.counts,
    required this.onChanged,
  });

  final _NotesFilter filter;
  final Map<_NotesFilter, int> counts;
  final ValueChanged<_NotesFilter> onChanged;

  String get _label {
    final n = counts[filter] ?? 0;
    return switch (filter) {
      _NotesFilter.all => 'All notes · $n',
      _NotesFilter.none => 'No date · $n',
      _NotesFilter.day => 'One day · $n',
      _NotesFilter.period => 'Period · $n',
      _NotesFilter.linked => 'Linked · $n',
    };
  }

  bool get _narrowed => filter != _NotesFilter.all;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_NotesFilter>(
      tooltip: 'Filter by when',
      offset: const Offset(0, 42),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: BodylineColors.border),
      ),
      color: BodylineColors.surface,
      initialValue: filter,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final f in _NotesFilter.values)
          PopupMenuItem(
            value: f,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    switch (f) {
                      _NotesFilter.all =>
                        'All notes · ${counts[_NotesFilter.all] ?? 0}',
                      _NotesFilter.none =>
                        'No date · ${counts[_NotesFilter.none] ?? 0}',
                      _NotesFilter.day =>
                        'One day · ${counts[_NotesFilter.day] ?? 0}',
                      _NotesFilter.period =>
                        'Period · ${counts[_NotesFilter.period] ?? 0}',
                      _NotesFilter.linked =>
                        'Linked · ${counts[_NotesFilter.linked] ?? 0}',
                    },
                    style: TextStyle(
                      fontWeight:
                          f == filter ? FontWeight.w700 : FontWeight.w500,
                      color: BodylineColors.ink,
                    ),
                  ),
                ),
                if (f == filter)
                  Icon(Icons.check, size: 16, color: BodylineColors.teal),
              ],
            ),
          ),
      ],
      child: _FilterPillChrome(
        narrowed: _narrowed,
        icon: Icons.event_note_outlined,
        label: _label,
      ),
    );
  }
}

class _NotesTagFilterPill extends StatelessWidget {
  const _NotesTagFilterPill({
    required this.selected,
    required this.tags,
    required this.counts,
    required this.onChanged,
  });

  /// Sentinel — PopupMenuButton ignores null values, so "clear" needs a real key.
  static const _allKey = '__all_tags__';

  final String? selected;
  final List<String> tags;
  final Map<String, int> counts;
  final ValueChanged<String?> onChanged;

  String get _label {
    if (selected == null) return 'All tags';
    return '$selected · ${counts[selected] ?? 0}';
  }

  @override
  Widget build(BuildContext context) {
    final narrowed = selected != null;
    return PopupMenuButton<String>(
      tooltip: 'Filter by tag',
      offset: const Offset(0, 42),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: BodylineColors.border),
      ),
      color: BodylineColors.surface,
      initialValue: selected ?? _allKey,
      onSelected: (key) {
        if (key == _allKey) {
          onChanged(null);
        } else {
          onChanged(key);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: _allKey,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'All tags',
                  style: TextStyle(
                    fontWeight:
                        selected == null ? FontWeight.w700 : FontWeight.w500,
                    color: BodylineColors.ink,
                  ),
                ),
              ),
              if (selected == null)
                Icon(Icons.check, size: 16, color: BodylineColors.teal),
            ],
          ),
        ),
        const PopupMenuDivider(),
        for (final tag in tags)
          PopupMenuItem<String>(
            value: tag,
            child: Row(
              children: [
                _TagPill(label: tag),
                const Spacer(),
                Text(
                  '${counts[tag] ?? 0}',
                  style: TextStyle(
                    fontSize: 12,
                    color: BodylineColors.inkSubtle,
                  ),
                ),
                if (selected == tag) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check, size: 16, color: BodylineColors.teal),
                ],
              ],
            ),
          ),
      ],
      child: _FilterPillChrome(
        narrowed: narrowed,
        icon: Icons.label_outline,
        label: _label,
      ),
    );
  }
}

class _FilterPillChrome extends StatelessWidget {
  const _FilterPillChrome({
    required this.narrowed,
    required this.icon,
    required this.label,
  });

  final bool narrowed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: narrowed ? BodylineColors.ink : BodylineColors.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: narrowed ? BodylineColors.ink : BodylineColors.outlineSoft,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: narrowed ? BodylineColors.onInk : BodylineColors.inkMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: narrowed ? BodylineColors.onInk : BodylineColors.ink,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: narrowed ? BodylineColors.onInk : BodylineColors.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesListPane extends StatelessWidget {
  const _NotesListPane({
    required this.groups,
    required this.empty,
    required this.filteredEmpty,
    required this.selectedId,
    required this.whenHeader,
    required this.chartLabel,
    required this.onSelect,
  });

  final List<MapEntry<String, List<Map<String, Object?>>>> groups;
  final bool empty;
  final bool filteredEmpty;
  final String? selectedId;
  final String Function(Map<String, Object?>) whenHeader;
  final String Function(String) chartLabel;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (empty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            'No notes yet.\nThings your reports and prescriptions don’t say.',
            textAlign: TextAlign.center,
            style: TextStyle(color: BodylineColors.inkSubtle, height: 1.4),
          ),
        ),
      );
    }
    if (filteredEmpty) {
      return Center(
        child: Text(
          'No notes match this filter.',
          style: TextStyle(color: BodylineColors.inkSubtle),
        ),
      );
    }

    return ListView(
      children: [
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
            child: Text(
              g.key,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: BodylineColors.inkSubtle,
              ),
            ),
          ),
          for (final n in g.value)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _NoteCard(
                note: n,
                selected: n['id'] == selectedId,
                whenLabel: whenHeader(n),
                chartLabel: chartLabel,
                onTap: () {
                  final id = n['id'] as String?;
                  if (id != null) onSelect(id);
                },
              ),
            ),
        ],
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.selected,
    required this.whenLabel,
    required this.chartLabel,
    required this.onTap,
  });

  final Map<String, Object?> note;
  final bool selected;
  final String whenLabel;
  final String Function(String) chartLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = (note['when_kind'] as String?) ?? 'none';
    final tags = noteTags(note);
    final charts = noteChartCodes(note);
    final body = (note['body'] as String?)?.trim() ?? '';
    final title = (note['title'] as String?)?.trim() ?? '';
    final preview = body.isNotEmpty ? body : title;
    final icon = switch (kind) {
      'day' => Icons.calendar_today_outlined,
      'period' => Icons.horizontal_rule,
      _ => Icons.event_busy_outlined,
    };

    return Material(
      color: BodylineColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? BodylineColors.orange : BodylineColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: BodylineColors.orangeText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      whenLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: BodylineColors.orangeText,
                      ),
                    ),
                  ),
                  if (tags.isNotEmpty) _TagPill(label: tags.first),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                preview.isEmpty ? 'Empty note' : preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (charts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in (chartCodesAreAll(charts)
                        ? const [kChartCodeAll]
                        : charts))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: BodylineColors.chip,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: BodylineColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.link,
                              size: 12,
                              color: BodylineColors.inkSubtle,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              chartLabel(c),
                              style: TextStyle(
                                fontSize: 11,
                                color: BodylineColors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteDetail extends StatelessWidget {
  const _NoteDetail({
    required this.note,
    required this.whenLine,
    required this.whenIcon,
    required this.chartLabel,
    required this.relativeEdited,
    required this.onEdit,
    required this.onDelete,
    required this.onDoctorChanged,
    required this.onLink,
    this.onOpenChart,
  });

  final Map<String, Object?> note;
  final String whenLine;
  final IconData whenIcon;
  final String Function(String) chartLabel;
  final String Function(int) relativeEdited;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onDoctorChanged;
  final VoidCallback onLink;
  final ValueChanged<String>? onOpenChart;

  @override
  Widget build(BuildContext context) {
    final updatedMs = switch (note['updated_at']) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v) ?? 0,
      _ => 0,
    };
    final doctor = (note['include_in_doctor_summary'] as int? ?? 0) == 1;
    final tags = noteTags(note);
    final charts = noteChartCodes(note);
    final body = (note['body'] as String?)?.trim() ?? '';
    final title = (note['title'] as String?)?.trim() ?? '';
    final display = body.isNotEmpty ? body : title;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(whenIcon, size: 18, color: BodylineColors.orangeText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      whenLine,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: BodylineColors.orangeText,
                      ),
                    ),
                  ),
                  if (tags.isNotEmpty) _TagPill(label: tags.first),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                display.isEmpty ? 'Empty note' : display,
                style: const TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 26,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (body.isNotEmpty &&
                  title.isNotEmpty &&
                  title != body &&
                  !body.startsWith(title)) ...[
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: BodylineColors.inkSubtle,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Written by You · last edited ${relativeEdited(updatedMs)}',
                style: TextStyle(
                  fontSize: 12,
                  color: BodylineColors.inkSubtle,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Shown on',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: BodylineColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              if (charts.isEmpty)
                Text(
                  'Not linked to a chart yet.',
                  style: TextStyle(
                    fontSize: 13,
                    color: BodylineColors.inkSubtle,
                  ),
                )
              else if (chartCodesAreAll(charts))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.show_chart,
                        size: 18,
                        color: BodylineColors.inkMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          chartLabel(kChartCodeAll),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final c in charts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.show_chart,
                          size: 18,
                          color: BodylineColors.inkMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            chartLabel(c),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: onOpenChart == null
                              ? null
                              : () => onOpenChart!(c),
                          style: TextButton.styleFrom(
                            foregroundColor: BodylineColors.teal,
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Open chart →'),
                        ),
                      ],
                    ),
                  ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onLink,
                  style: TextButton.styleFrom(
                    foregroundColor: BodylineColors.teal,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('+ Link to a test, habit or medicine'),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: BodylineColors.chip,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Doctor summary',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            doctor
                                ? 'Included in the doctor summary when you share it.'
                                : 'Not in the doctor summary. Only you see it.',
                            style: TextStyle(
                              fontSize: 12,
                              color: BodylineColors.inkSubtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(value: doctor, onChanged: onDoctorChanged),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit note'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onDelete,
              style: TextButton.styleFrom(
                foregroundColor: BodylineColors.danger,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }
}

class _TagStyle {
  const _TagStyle(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

_TagStyle _tagStyle(String raw) {
  final t = raw.toLowerCase();
  if (t.contains('illness')) {
    return const _TagStyle(Color(0xFFF8E4E0), Color(0xFF9A3B2E));
  }
  if (t.contains('doctor')) {
    return const _TagStyle(Color(0xFFE2F0E6), Color(0xFF2F6B45));
  }
  if (t.contains('travel')) {
    return const _TagStyle(Color(0xFFE3ECF8), Color(0xFF1E4478));
  }
  if (t.contains('diet')) {
    return const _TagStyle(Color(0xFFFBE9DC), Color(0xFF8A3E10));
  }
  return _TagStyle(BodylineColors.chip, BodylineColors.inkMuted);
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = _tagStyle(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: s.fg,
        ),
      ),
    );
  }
}

class _AddCustomTagField extends StatefulWidget {
  const _AddCustomTagField({required this.onAdd});
  final ValueChanged<String> onAdd;

  @override
  State<_AddCustomTagField> createState() => _AddCustomTagFieldState();
}

class _AddCustomTagFieldState extends State<_AddCustomTagField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    widget.onAdd(t);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Add custom tag',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Add tag',
          onPressed: _submit,
          icon: const Icon(Icons.add, size: 20),
        ),
      ],
    );
  }
}
