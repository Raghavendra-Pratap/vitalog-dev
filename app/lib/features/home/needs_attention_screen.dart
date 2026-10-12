import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';

import '../../data/attention_prefs.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_pill.dart';
import '../tests/trend_screen.dart';
import 'customize_attention_sheet.dart';

/// Full-page Needs attention list (mobile home entry).
class NeedsAttentionScreen extends StatefulWidget {
  const NeedsAttentionScreen({
    super.key,
    required this.store,
    this.onChanged,
  });

  final LocalStore store;
  final VoidCallback? onChanged;

  @override
  State<NeedsAttentionScreen> createState() => _NeedsAttentionScreenState();
}

class _NeedsAttentionScreenState extends State<NeedsAttentionScreen> {
  AttentionPrefs _prefs = AttentionPrefs(hidden: {});
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final pid = widget.store.activeProfileId;
    final prefs = pid == null
        ? AttentionPrefs(hidden: {})
        : await AttentionPrefs.load(pid);
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _loading = false;
    });
  }

  List<ObservationRecord> get _flaggedLatest {
    final id = widget.store.activeProfileId;
    final flagged = widget.store.observations
        .where((o) =>
            o.profileId == id &&
            o.flag != null &&
            o.flag != ObservationFlag.normal)
        .toList()
      ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
    final seen = <String>{};
    final out = <ObservationRecord>[];
    for (final o in flagged) {
      if (seen.add(o.parameterCode)) out.add(o);
    }
    return out;
  }

  List<ObservationRecord> get _visible => [
        for (final o in _flaggedLatest)
          if (!_prefs.hidden.contains(o.parameterCode)) o,
      ];

  Future<void> _customize() async {
    final next = await showCustomizeAttentionSheet(
      context: context,
      prefs: _prefs,
      flaggedLatest: _flaggedLatest,
    );
    if (next == null || !mounted) return;
    final pid = widget.store.activeProfileId;
    if (pid != null) await next.save(pid);
    setState(() => _prefs = next);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final needs = _visible;
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(
        title: const Text('Needs attention'),
        actions: [
          IconButton(
            tooltip: 'Customize',
            onPressed: _loading ? null : _customize,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                Text(
                  needs.isEmpty
                      ? 'Flagged results that still need a look.'
                      : '${needs.length} flagged · tap to open the trend',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (needs.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: BodylineColors.surface,
                      borderRadius:
                          BorderRadius.circular(BodylineRadii.cardSmall),
                      border: Border.all(color: BodylineColors.border),
                    ),
                    child: Text(
                      _flaggedLatest.isNotEmpty
                          ? 'All flagged tests are hidden. Tap Customize to show them again.'
                          : 'No flagged values. Add a report with the lab\u2019s printed range to see what needs attention.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  for (final o in needs) _card(o),
              ],
            ),
    );
  }

  Widget _card(ObservationRecord o) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        child: InkWell(
          borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TrendScreen(
                  store: widget.store,
                  parameterCode: o.parameterCode,
                  title: o.parameterName,
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
              border: Border.all(color: BodylineColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.parameterName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        o.refLow != null || o.refHigh != null
                            ? 'Lab ${o.refLow ?? '\u2014'}\u2013${o.refHigh ?? '\u2014'} ${o.unitReported}'
                            : o.unitReported,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  o.valueReported,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontSize: 20,
                      ),
                ),
                const SizedBox(width: 8),
                if (o.flag != null) StatusPill(flag: o.flag!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
