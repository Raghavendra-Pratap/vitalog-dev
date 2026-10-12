import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../desktop.dart';
import '../../theme/desktop_layout.dart';
import '../../theme/tokens.dart';
import '../../widgets/clinical_attachments.dart';
import '../visits/visit_forms.dart';

class DoctorsScreen extends StatefulWidget {
  const DoctorsScreen({
    super.key,
    required this.store,
    required this.onChanged,
    this.embedded = false,
  });

  final LocalStore store;
  final VoidCallback onChanged;
  /// When true (e.g. nested under another Scaffold), skip AppBar.
  final bool embedded;

  @override
  DoctorsScreenState createState() => DoctorsScreenState();
}

class DoctorsScreenState extends State<DoctorsScreen> {
  Future<void> promptAdd() => _addDoctor();

  List<_DoctorRow> _rows = [];
  var _loading = true;
  String? _selectedKey;
  var _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant DoctorsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // IndexedStack keeps State; reload after visits added on Visits page.
    _reload();
  }

  Future<void> _reload() async {
    final gen = ++_loadGen;
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _rows = [];
        _loading = false;
        _selectedKey = null;
      });
      return;
    }
    final providers = await widget.store.listProviders(pid);
    final visits = await widget.store.listVisits(pid);
    final byName = <String, _DoctorRow>{};
    final byId = <String, _DoctorRow>{};
    for (final p in providers) {
      final row = _DoctorRow(
        id: p.id,
        name: p.name,
        specialty: p.specialty,
        clinic: p.clinic,
        phone: p.phone,
        notes: p.notes,
      );
      byName[p.name.toLowerCase()] = row;
      byId[p.id] = row;
    }
    for (final v in visits) {
      _DoctorRow? row;
      final vid = v.providerId;
      if (vid != null && vid.isNotEmpty) {
        row = byId[vid];
      }
      final n = v.providerName?.trim();
      if (row == null) {
        if (n == null || n.isEmpty) continue;
        final key = n.toLowerCase();
        row = byName.putIfAbsent(
          key,
          () => _DoctorRow(id: null, name: n),
        );
      } else if (n != null && n.isNotEmpty) {
        // Keep name index pointing at the same card.
        byName.putIfAbsent(n.toLowerCase(), () => row!);
      }
      row.visits.add(v);
    }
    final list = byName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted || gen != _loadGen) return;
    setState(() {
      _rows = list;
      _loading = false;
      if (_selectedKey != null &&
          !list.any((d) => d.name.toLowerCase() == _selectedKey)) {
        _selectedKey = list.isEmpty ? null : list.first.name.toLowerCase();
      } else if (_selectedKey == null && list.isNotEmpty) {
        _selectedKey = list.first.name.toLowerCase();
      }
    });
  }

  Future<void> _addDoctor() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;
    final name = TextEditingController();
    final specialty = TextEditingController();
    final clinic = TextEditingController();
    final phone = TextEditingController();
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add doctor'),
        titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
        contentPadding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 12, 28, 20),
        insetPadding: bodylineDialogInset(context),
        content: SizedBox(
          width: bodylineDialogWidth(context, 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: specialty,
                  decoration: const InputDecoration(
                    labelText: 'Specialty (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: clinic,
                  decoration: const InputDecoration(
                    labelText: 'Hospital / clinic (optional)',
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: 'Phone (optional)'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
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
    );
    if (ok != true || name.text.trim().isEmpty) return;
    await widget.store.upsertProvider(
      profileId: pid,
      name: name.text.trim(),
      specialty: specialty.text.trim().isEmpty ? null : specialty.text.trim(),
      clinic: clinic.text.trim().isEmpty ? null : clinic.text.trim(),
      phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
      notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
    );
    widget.onChanged();
    await _reload();
    setState(() => _selectedKey = name.text.trim().toLowerCase());
  }

  _DoctorRow? get _selected {
    if (_selectedKey == null) return null;
    for (final d in _rows) {
      if (d.name.toLowerCase() == _selectedKey) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (useWideShell(context)) {
      return _buildDesktop(context);
    }
    return _buildMobile(context);
  }

  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('Doctors')),
      floatingActionButton: FloatingActionButton(
        heroTag: widget.embedded ? 'care-tab-doctors-fab' : 'page-doctors-fab',
        onPressed: _addDoctor,
        tooltip: 'Add doctor',
        backgroundColor: BodylineColors.teal,
        foregroundColor: BodylineColors.isDark
            ? const Color(0xFF04201C)
            : Colors.white,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            'Shared across your family on this device. Notes stay here.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: BodylineColors.inkSubtle,
                ),
          ),
        ),
        Expanded(
          child: _rows.isEmpty
              ? Center(
                  child: Text(
                    'No doctors yet. Add one, or record a visit with a doctor name.',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = _rows[i];
                    return _doctorTile(
                      d,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _DoctorDetailPage(
                              store: widget.store,
                              doctor: d,
                              onChanged: () {
                                widget.onChanged();
                                _reload();
                              },
                            ),
                          ),
                        );
                        await _reload();
                      },
                    );
                  },
                ),
        ),
      ],
    ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final selected = _selected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesktopLayout.mainPaddingH,
        8,
        DesktopLayout.mainPaddingH,
        DesktopLayout.mainPaddingV,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: DesktopLayout.testsMasterCol,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Shared across your family on this device.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: BodylineColors.inkSubtle,
                      ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _rows.isEmpty
                      ? Center(
                          child: Text(
                            'No doctors yet.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final d = _rows[i];
                            final key = d.name.toLowerCase();
                            return _doctorCard(
                              d,
                              selected: key == _selectedKey,
                              onTap: () =>
                                  setState(() => _selectedKey = key),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: selected == null
                ? Center(
                    child: Text(
                      'Select a doctor to see details and visits.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: BodylineColors.surface,
                      borderRadius: BorderRadius.circular(BodylineRadii.card),
                      border: Border.all(color: BodylineColors.border),
                    ),
                    child: _DoctorDetailPane(
                      key: ValueKey(selected.name),
                      store: widget.store,
                      doctor: selected,
                      onChanged: () {
                        widget.onChanged();
                        _reload();
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _doctorTile(_DoctorRow d, {required VoidCallback onTap}) {
    final last = d.visits.isEmpty
        ? null
        : (d.visits.toList()
              ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt)))
            .first;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: BodylineColors.tealTint,
        child: Text(
          d.name.isNotEmpty ? d.name[0].toUpperCase() : '?',
          style: TextStyle(color: BodylineColors.tealDark),
        ),
      ),
      title: Text(d.name),
      subtitle: Text(
        [
          if (d.specialty != null && d.specialty!.isNotEmpty) d.specialty!,
          if (d.clinic != null && d.clinic!.isNotEmpty) d.clinic!,
          if (d.visits.isNotEmpty)
            '${d.visits.length} visit${d.visits.length == 1 ? '' : 's'}',
          if (last != null)
            'Last ${DateFormat.yMMMd().format(last.visitedAt)}',
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _doctorCard(
    _DoctorRow d, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final last = d.visits.isEmpty
        ? null
        : (d.visits.toList()
              ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt)))
            .first;
    return Material(
      color: selected ? BodylineColors.selectedWash : BodylineColors.surface,
      borderRadius: BorderRadius.circular(BodylineRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BodylineRadii.card),
            border: Border.all(
              color: selected ? BodylineColors.teal : BodylineColors.border,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: BodylineColors.tealTint,
                child: Text(
                  d.name.isNotEmpty ? d.name[0].toUpperCase() : '?',
                  style: TextStyle(color: BodylineColors.tealDark),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? BodylineColors.tealDark
                            : BodylineColors.ink,
                      ),
                    ),
                    Text(
                      [
                        if (d.specialty != null && d.specialty!.isNotEmpty)
                          d.specialty!,
                        if (d.clinic != null && d.clinic!.isNotEmpty)
                          d.clinic!,
                        if (d.visits.isNotEmpty)
                          '${d.visits.length} visit${d.visits.length == 1 ? '' : 's'}',
                        if (last != null)
                          'Last ${DateFormat.yMMMd().format(last.visitedAt)}',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorRow {
  _DoctorRow({
    required this.id,
    required this.name,
    this.specialty,
    this.clinic,
    this.phone,
    this.notes,
  });
  String? id;
  String name;
  String? specialty;
  String? clinic;
  String? phone;
  String? notes;
  final List<VisitRecord> visits = [];
}

class _DoctorDetailPage extends StatefulWidget {
  const _DoctorDetailPage({
    required this.store,
    required this.doctor,
    required this.onChanged,
  });

  final LocalStore store;
  final _DoctorRow doctor;
  final VoidCallback onChanged;

  @override
  State<_DoctorDetailPage> createState() => _DoctorDetailPageState();
}

class _DoctorDetailPageState extends State<_DoctorDetailPage> {
  final _paneKey = GlobalKey<_DoctorDetailPaneState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(title: Text(widget.doctor.name)),
      floatingActionButton: FloatingActionButton(
        heroTag: 'doctor-detail-add-visit-fab',
        onPressed: () => _paneKey.currentState?.openAddVisit(),
        tooltip: 'Add visit',
        backgroundColor: BodylineColors.teal,
        foregroundColor: BodylineColors.isDark
            ? const Color(0xFF04201C)
            : Colors.white,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: _DoctorDetailPane(
        key: _paneKey,
        store: widget.store,
        doctor: widget.doctor,
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _DoctorDetailPane extends StatefulWidget {
  const _DoctorDetailPane({
    super.key,
    required this.store,
    required this.doctor,
    required this.onChanged,
  });

  final LocalStore store;
  final _DoctorRow doctor;
  final VoidCallback onChanged;

  @override
  State<_DoctorDetailPane> createState() => _DoctorDetailPaneState();
}

class _DoctorDetailPaneState extends State<_DoctorDetailPane> {
  Future<void> openAddVisit() => _addVisit();

  late final TextEditingController _name;
  late final TextEditingController _notes;
  late final TextEditingController _specialty;
  late final TextEditingController _clinic;
  late final TextEditingController _phone;
  String? _providerId;
  var _editing = false;

  @override
  void initState() {
    super.initState();
    _syncControllersFromDoctor();
    _providerId = widget.doctor.id;
    _ensureIdOnly();
  }

  void _syncControllersFromDoctor() {
    _name = TextEditingController(text: widget.doctor.name);
    _notes = TextEditingController(text: widget.doctor.notes ?? '');
    _specialty = TextEditingController(text: widget.doctor.specialty ?? '');
    _clinic = TextEditingController(text: widget.doctor.clinic ?? '');
    _phone = TextEditingController(text: widget.doctor.phone ?? '');
  }

  void _reloadControllers() {
    _name.text = widget.doctor.name;
    _notes.text = widget.doctor.notes ?? '';
    _specialty.text = widget.doctor.specialty ?? '';
    _clinic.text = widget.doctor.clinic ?? '';
    _phone.text = widget.doctor.phone ?? '';
  }

  @override
  void didUpdateWidget(covariant _DoctorDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doctor.name != widget.doctor.name) {
      _reloadControllers();
      _providerId = widget.doctor.id;
      _editing = false;
      _ensureIdOnly();
    } else if (!_editing) {
      // Refresh read-only fields after parent reload (e.g. save).
      _name.text = widget.doctor.name;
      _notes.text = widget.doctor.notes ?? '';
      _specialty.text = widget.doctor.specialty ?? '';
      _clinic.text = widget.doctor.clinic ?? '';
      _phone.text = widget.doctor.phone ?? '';
      _providerId = widget.doctor.id ?? _providerId;
    }
  }

  /// Ensure a provider row exists for attachments — do not treat as "edit".
  Future<void> _ensureIdOnly() async {
    if (_providerId != null) return;
    final pid = widget.store.activeProfileId;
    if (pid == null) return;
    final id = await widget.store.upsertProvider(
      profileId: pid,
      name: widget.doctor.name,
      specialty: widget.doctor.specialty,
      clinic: widget.doctor.clinic,
      phone: widget.doctor.phone,
      notes: widget.doctor.notes,
      existingId: null,
    );
    if (!mounted) return;
    setState(() => _providerId = id);
  }

  void _startEdit() {
    _reloadControllers();
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    _reloadControllers();
    setState(() => _editing = false);
  }

  Future<void> _saveMeta() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;
    final newName = _name.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doctor name is required')),
      );
      return;
    }
    final id = await widget.store.upsertProvider(
      profileId: pid,
      name: newName,
      specialty: _specialty.text.trim().isEmpty ? null : _specialty.text.trim(),
      clinic: _clinic.text.trim().isEmpty ? null : _clinic.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      existingId: _providerId,
    );
    _providerId = id;
    widget.doctor.name = newName;
    widget.doctor.specialty = _specialty.text.trim().isEmpty ? null : _specialty.text.trim();
    widget.doctor.clinic = _clinic.text.trim().isEmpty ? null : _clinic.text.trim();
    widget.doctor.phone = _phone.text.trim().isEmpty ? null : _phone.text.trim();
    widget.doctor.notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    widget.doctor.id = id;
    widget.onChanged();
    if (!mounted) return;
    setState(() => _editing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Doctor details saved')),
    );
  }

  Future<void> _deleteDoctor() async {
    final pid = widget.store.activeProfileId;
    if (pid == null) return;
    final id = _providerId ?? widget.doctor.id;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to delete yet')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete doctor?'),
        content: Text(
          'Remove ${widget.doctor.name} from your doctors list? '
          'Past visits stay; they will no longer be linked to this doctor card.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.softDeleteProvider(id);
    widget.onChanged();
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Doctor deleted')),
    );
  }

  Future<void> _addVisit() async {
    final ok = await promptAddVisit(
      context,
      store: widget.store,
      onChanged: widget.onChanged,
      prefillDoctor: widget.doctor.name,
    );
    if (ok) widget.onChanged();
  }

  Future<void> _editVisit(VisitRecord visit) async {
    final updated = await promptEditVisit(
      context,
      store: widget.store,
      visit: visit,
      onChanged: widget.onChanged,
    );
    if (updated != null && mounted) {
      widget.onChanged();
    }
  }

  Widget _readField(String label, String? value) {
    final v = (value ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: BodylineColors.inkSubtle,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            v.isEmpty ? '—' : v,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _specialty.dispose();
    _clinic.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visits = widget.doctor.visits.toList()
      ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    final fmt = DateFormat.yMMMMd();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                widget.doctor.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            if (!_editing) ...[
              IconButton(
                tooltip: 'Edit details',
                onPressed: _startEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Delete doctor',
                onPressed: _deleteDoctor,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (_editing) ...[
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Doctor name'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _specialty,
            decoration: const InputDecoration(labelText: 'Specialty'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _clinic,
            decoration: const InputDecoration(labelText: 'Hospital / clinic'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Phone'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Preferences, clinic, reminders…',
            ),
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: _saveMeta,
                child: const Text('Save details'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _cancelEdit,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ] else ...[
          _readField('Specialty', widget.doctor.specialty),
          _readField('Hospital / clinic', widget.doctor.clinic),
          _readField('Phone', widget.doctor.phone),
          _readField('Notes', widget.doctor.notes),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Visits',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            // Desktop detail pane has no page FAB — keep inline Add there only.
            if (useWideShell(context))
              IconButton(
                tooltip: 'Add visit (past or upcoming)',
                onPressed: _addVisit,
                icon: const Icon(Icons.add),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Past visits and upcoming appointments with this doctor.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: BodylineColors.inkSubtle,
              ),
        ),
        const SizedBox(height: 8),
        if (visits.isEmpty)
          Text(
            'No visits linked yet. Tap + to add one.',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
              border: Border.all(color: BodylineColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < visits.length; i++) ...[
                  ListTile(
                    title: Text(fmt.format(visits[i].visitedAt)),
                    subtitle: Text(
                      [
                        if (visits[i].reason != null &&
                            visits[i].reason!.isNotEmpty)
                          visits[i].reason!,
                        if (visits[i].diagnosis != null &&
                            visits[i].diagnosis!.isNotEmpty)
                          visits[i].diagnosis!,
                        if (visits[i].notes != null &&
                            visits[i].notes!.isNotEmpty)
                          visits[i].notes!,
                      ].join(' · '),
                    ),
                    trailing: IconButton(
                      tooltip: 'Edit visit',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _editVisit(visits[i]),
                    ),
                    onTap: () => _editVisit(visits[i]),
                  ),
                  if (i < visits.length - 1)
                    Divider(height: 1, color: BodylineColors.divider),
                ],
              ],
            ),
          ),
        const SizedBox(height: 24),
        Text(
          'Prescriptions & files',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Attach PDFs or photos for this doctor. Files stay encrypted on device.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: BodylineColors.inkSubtle,
              ),
        ),
        const SizedBox(height: 8),
        if (_providerId != null)
          ClinicalAttachmentsSection(
            store: widget.store,
            ownerType: 'provider',
            ownerId: _providerId!,
            onChanged: widget.onChanged,
          )
        else
          const Text('Saving doctor record…'),
      ],
    );
  }
}
