import 'package:flutter/material.dart';

import '../../data/body_panel_prefs.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

Future<BodyPanelPrefs?> showCustomizeBodySheet({
  required BuildContext context,
  required BodyPanelPrefs prefs,
  required List<OrganSummary> allOrgans,
}) {
  return showModalBottomSheet<BodyPanelPrefs>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BodylineColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _CustomizeBodySheet(
      initial: prefs,
      allOrgans: allOrgans,
    ),
  );
}

class _CustomizeBodySheet extends StatefulWidget {
  const _CustomizeBodySheet({
    required this.initial,
    required this.allOrgans,
  });

  final BodyPanelPrefs initial;
  final List<OrganSummary> allOrgans;

  @override
  State<_CustomizeBodySheet> createState() => _CustomizeBodySheetState();
}

class _CustomizeBodySheetState extends State<_CustomizeBodySheet> {
  late List<String> _order;
  late Set<String> _hidden;

  @override
  void initState() {
    super.initState();
    _order = List<String>.from(widget.initial.order);
    _hidden = Set<String>.from(widget.initial.hidden);
  }

  String _name(String code) {
    for (final o in widget.allOrgans) {
      if (o.code == code) return o.name;
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
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
              'Customize body panel',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Show, hide, and reorder systems. The map only paints organs that are on and have a silhouette.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: BodylineColors.inkSubtle,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.48,
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: _order.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    var to = newIndex;
                    if (to > oldIndex) to -= 1;
                    final code = _order.removeAt(oldIndex);
                    _order.insert(to, code);
                  });
                },
                itemBuilder: (context, index) {
                  final code = _order[index];
                  final on = !_hidden.contains(code);
                  final hasGlyph = BodyPanelPrefs.glyphCodes.contains(code);
                  return Material(
                    key: ValueKey(code),
                    color: BodylineColors.surface,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          Icons.drag_handle,
                          color: BodylineColors.inkSubtle,
                        ),
                      ),
                      title: Text(
                        _name(code),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: on
                              ? BodylineColors.ink
                              : BodylineColors.inkSubtle,
                        ),
                      ),
                      subtitle: Text(
                        hasGlyph ? 'Shown on body map' : 'List only',
                        style: TextStyle(
                          fontSize: 12,
                          color: BodylineColors.inkSubtle,
                        ),
                      ),
                      trailing: Switch(
                        value: on,
                        onChanged: (v) {
                          setState(() {
                            if (v) {
                              _hidden.remove(code);
                            } else {
                              _hidden.add(code);
                            }
                          });
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _order = [for (final o in widget.allOrgans) o.code];
                      _hidden.clear();
                    });
                  },
                  child: const Text('Reset'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _hidden.length == _order.length
                      ? null
                      : () {
                          Navigator.of(context).pop(
                            BodyPanelPrefs(order: _order, hidden: _hidden),
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: BodylineColors.ink,
                    foregroundColor: BodylineColors.onInk,
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
