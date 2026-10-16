import 'package:flutter/material.dart';

/// Searchable multi-select for linking a note/habit to trend charts.
class ChartLinkPicker extends StatefulWidget {
  const ChartLinkPicker({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.labelFor,
    this.hintText = 'Search charts to add…',
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final String Function(String) labelFor;
  final String hintText;

  @override
  State<ChartLinkPicker> createState() => _ChartLinkPickerState();
}

class _ChartLinkPickerState extends State<ChartLinkPicker> {
  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selected.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in selected)
                InputChip(
                  label: Text(widget.labelFor(c)),
                  onDeleted: () {
                    final next = {...selected}..remove(c);
                    widget.onChanged(next);
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Autocomplete<String>(
          key: ValueKey('charts-${selected.join('|')}'),
          optionsBuilder: (text) {
            final q = text.text.trim().toLowerCase();
            final remaining = [
              for (final o in widget.options)
                if (!selected.contains(o)) o,
            ];
            if (q.isEmpty) return remaining.take(12);
            return remaining
                .where((o) =>
                    o.toLowerCase().contains(q) ||
                    widget.labelFor(o).toLowerCase().contains(q))
                .take(12);
          },
          displayStringForOption: widget.labelFor,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.hintText,
                prefixIcon: const Icon(Icons.search, size: 18),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                final q = v.trim().toLowerCase();
                if (q.isEmpty) return;
                String? match;
                for (final o in widget.options) {
                  if (selected.contains(o)) continue;
                  if (o.toLowerCase() == q ||
                      widget.labelFor(o).toLowerCase() == q) {
                    match = o;
                    break;
                  }
                }
                if (match != null) {
                  widget.onChanged({...selected, match});
                  controller.clear();
                }
              },
            );
          },
          onSelected: (value) {
            widget.onChanged({...selected, value});
            setState(() {});
          },
          optionsViewBuilder: (context, onSelected, options) {
            final opts = options.toList();
            if (opts.isEmpty) {
              return const SizedBox.shrink();
            }
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 220, maxWidth: 400),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: opts.length,
                    itemBuilder: (context, i) {
                      final o = opts[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.show_chart, size: 18),
                        title: Text(widget.labelFor(o)),
                        onTap: () => onSelected(o),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
