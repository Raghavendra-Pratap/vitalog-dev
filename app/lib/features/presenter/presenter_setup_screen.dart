import 'package:flutter/material.dart';
import '../../widgets/month_year_date_picker.dart';

import '../../data/local_store.dart';
import '../../theme/tokens.dart';
import 'presenter_filter.dart';
import 'presenter_session_screen.dart';

class PresenterSetupScreen extends StatefulWidget {
  const PresenterSetupScreen({super.key, required this.store});

  final LocalStore store;

  @override
  State<PresenterSetupScreen> createState() => _PresenterSetupScreenState();
}

class _PresenterSetupScreenState extends State<PresenterSetupScreen> {
  final _systems = <String>{};
  var _labs = true;
  var _visits = true;
  var _procedures = true;
  var _attachments = true;
  DateTime? _from;
  DateTime? _to;
  List<({String code, String name})> _allSystems = [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final systems = await widget.store.bodySystems();
    if (!mounted) return;
    setState(() {
      _allSystems = systems;
      _systems
        ..clear()
        ..addAll(systems.map((s) => s.code));
      _loading = false;
    });
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final d = await pickBodylineDate(
      context,
      initialDate: _from ?? DateTime(now.year - 2),
      firstDate: DateTime(now.year - 40),
      lastDate: now,
    );
    if (d != null) setState(() => _from = d);
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final d = await pickBodylineDate(
      context,
      initialDate: _to ?? now,
      firstDate: DateTime(now.year - 40),
      lastDate: now,
    );
    if (d != null) setState(() => _to = d);
  }

  PresenterFilter? _buildFilter() {
    final pid = widget.store.activeProfileId;
    if (pid == null) return null;
    return PresenterFilter(
      profileId: pid,
      systemCodes: Set<String>.from(_systems),
      includeLabs: _labs,
      includeVisits: _visits,
      includeProcedures: _procedures,
      includeAttachments: _attachments,
      from: _from,
      to: _to,
      allSystemsSelected:
          _allSystems.isNotEmpty && _systems.length == _allSystems.length,
    );
  }

  void _start() {
    final filter = _buildFilter();
    if (filter == null || !filter.isValid) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PresenterSessionScreen(
          store: widget.store,
          filter: filter,
        ),
      ),
    );
  }

  String get _profileName {
    final id = widget.store.activeProfileId;
    for (final p in widget.store.profiles) {
      if (p.id == id) return p.name;
    }
    return 'Profile';
  }

  @override
  Widget build(BuildContext context) {
    final filter = _buildFilter();
    final canStart = filter != null && filter.isValid;

    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(title: const Text('Present to doctor')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Text(
                  'Show a filtered view of $_profileName on this device. '
                  'Nothing is sent. Only hand the device in clinic.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'Body systems',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() {
                        _systems
                          ..clear()
                          ..addAll(_allSystems.map((s) => s.code));
                      }),
                      child: const Text('All'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _systems.clear()),
                      child: const Text('None'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _allSystems)
                      FilterChip(
                        label: Text(s.name),
                        selected: _systems.contains(s.code),
                        onSelected: (on) => setState(() {
                          if (on) {
                            _systems.add(s.code);
                          } else {
                            _systems.remove(s.code);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Include',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lab reports'),
                  value: _labs,
                  onChanged: (v) => setState(() => _labs = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Doctor visits'),
                  value: _visits,
                  onChanged: (v) => setState(() => _visits = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Treatments / procedures'),
                  value: _procedures,
                  onChanged: (v) => setState(() => _procedures = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Attached files'),
                  subtitle: const Text('Names only — open stays on this device'),
                  value: _attachments,
                  onChanged: (v) => setState(() => _attachments = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Date range',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    if (_from != null || _to != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _from = null;
                          _to = null;
                        }),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _from == null
                        ? 'From — any time'
                        : 'From ${_from!.day}/${_from!.month}/${_from!.year}',
                  ),
                  trailing: TextButton(
                    onPressed: _pickFrom,
                    child: const Text('Set'),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _to == null
                        ? 'To — any time'
                        : 'To ${_to!.day}/${_to!.month}/${_to!.year}',
                  ),
                  trailing: TextButton(
                    onPressed: _pickTo,
                    child: const Text('Set'),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: canStart ? _start : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: BodylineColors.ink,
                    foregroundColor: BodylineColors.onInk,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Start presentation'),
                ),
              ],
            ),
    );
  }
}
