import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/attention_prefs.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_pill.dart';

/// Hide flagged parameters from Needs attention (still in All tests).
Future<AttentionPrefs?> showCustomizeAttentionSheet({
  required BuildContext context,
  required AttentionPrefs prefs,
  required List<ObservationRecord> flaggedLatest,
}) {
  return showModalBottomSheet<AttentionPrefs>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BodylineColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _CustomizeAttentionSheet(
      initial: prefs,
      flaggedLatest: flaggedLatest,
    ),
  );
}

class _CustomizeAttentionSheet extends StatefulWidget {
  const _CustomizeAttentionSheet({
    required this.initial,
    required this.flaggedLatest,
  });

  final AttentionPrefs initial;
  final List<ObservationRecord> flaggedLatest;

  @override
  State<_CustomizeAttentionSheet> createState() =>
      _CustomizeAttentionSheetState();
}

class _CustomizeAttentionSheetState extends State<_CustomizeAttentionSheet> {
  late Set<String> _hidden;

  @override
  void initState() {
    super.initState();
    _hidden = Set<String>.from(widget.initial.hidden);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final rows = widget.flaggedLatest;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: BodylineColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Customize Needs attention',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Hide parameters that are flagged but not a concern right now. '
              'They still appear under All tests.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: BodylineColors.inkSubtle,
                  ),
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No flagged values yet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              SizedBox(
                height: MediaQuery.sizeOf(context).height *
                    (MediaQuery.sizeOf(context).width < 900 ? 0.55 : 0.42),
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: BodylineColors.divider),
                  itemBuilder: (context, i) {
                    final o = rows[i];
                    final show = !_hidden.contains(o.parameterCode);
                    final unit = o.unitReported.trim();
                    final latest = [
                      o.valueReported.trim(),
                      if (unit.isNotEmpty) unit,
                    ].join(' ');
                    final when = DateFormat('d MMM').format(o.observedAt);
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        o.parameterName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text(
                            'Latest $latest · $when',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            show
                                ? 'Shown on Needs attention'
                                : 'Hidden from Needs attention',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      secondary: o.flag == null
                          ? null
                          : StatusPill(flag: o.flag!),
                      value: show,
                      activeThumbColor: BodylineColors.onInk,
                      activeTrackColor: BodylineColors.teal,
                      onChanged: (v) {
                        setState(() {
                          if (v) {
                            _hidden.remove(o.parameterCode);
                          } else {
                            _hidden.add(o.parameterCode);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                AttentionPrefs(hidden: _hidden),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
