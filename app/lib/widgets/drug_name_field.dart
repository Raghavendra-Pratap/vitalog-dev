import 'package:flutter/material.dart';

import '../data/drug_index.dart';
import '../data/models.dart';
import '../theme/tokens.dart';

/// Medication / remedy name field with offline suggestions as a popup under the field.
class DrugNameField extends StatefulWidget {
  const DrugNameField({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(labelText: 'Medication name'),
    this.autofocus = false,
    this.textStyle,
    this.onSelected,
    this.onSubmitted,
    this.showKindSubtitle = false,
    this.preferredKind,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final bool autofocus;
  final TextStyle? textStyle;
  final ValueChanged<DrugSuggestion>? onSelected;
  final ValueChanged<String>? onSubmitted;
  final bool showKindSubtitle;
  /// When set (e.g. homeopathic), boost matching kinds in suggestions.
  final String? preferredKind;

  @override
  State<DrugNameField> createState() => _DrugNameFieldState();
}

class _DrugNameFieldState extends State<DrugNameField> {
  FocusNode? _ownedFocus;
  /// false = salt/generic, true = brand / bottle name.
  var _preferBrand = false;

  FocusNode get _focus => widget.focusNode ?? _ownedFocus!;

  @override
  void initState() {
    super.initState();
    DrugIndex.instance.ensureLoaded();
    if (widget.focusNode == null) {
      _ownedFocus = FocusNode();
    }
  }

  @override
  void didUpdateWidget(covariant DrugNameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferredKind != widget.preferredKind &&
        widget.controller.text.trim().isNotEmpty) {
      final v = widget.controller.value;
      widget.controller.value = v.copyWith(
        selection: TextSelection.collapsed(offset: v.text.length),
      );
    }
  }

  @override
  void dispose() {
    _ownedFocus?.dispose();
    super.dispose();
  }

  void _setPreferBrand(bool brand) {
    if (_preferBrand == brand) return;
    setState(() => _preferBrand = brand);
    // Nudge the controller so RawAutocomplete rebuilds options for the new mode.
    final v = widget.controller.value;
    widget.controller.value = v.copyWith(
      selection: TextSelection.collapsed(offset: v.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Salt')),
              ButtonSegment(value: true, label: Text('Brand')),
            ],
            selected: {_preferBrand},
            onSelectionChanged: (s) => _setPreferBrand(s.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        const SizedBox(height: 6),
        RawAutocomplete<DrugSuggestion>(
          key: ValueKey(
            '${_preferBrand ? 'brand' : 'salt'}-${widget.preferredKind ?? 'any'}',
          ),
          textEditingController: widget.controller,
          focusNode: _focus,
          optionsBuilder: (TextEditingValue tev) async {
            final q = tev.text.trim();
            if (q.isEmpty) return const Iterable<DrugSuggestion>.empty();
            return DrugIndex.instance.search(
              q,
              preferBrand: _preferBrand,
              preferredKind: widget.preferredKind,
            );
          },
          displayStringForOption: (s) => s.name,
          onSelected: (s) {
            widget.controller.value = TextEditingValue(
              text: s.name,
              selection: TextSelection.collapsed(offset: s.name.length),
            );
            widget.onSelected?.call(s);
          },
          fieldViewBuilder:
              (context, textController, focusNode, onFieldSubmitted) {
            return TextField(
              controller: textController,
              focusNode: focusNode,
              autofocus: widget.autofocus,
              style: widget.textStyle,
              textCapitalization: TextCapitalization.sentences,
              decoration: widget.decoration,
              onSubmitted: (v) {
                onFieldSubmitted();
                widget.onSubmitted?.call(v);
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final opts = options.toList(growable: false);
            if (opts.isEmpty) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 6,
                color: BodylineColors.surface,
                borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 200, minWidth: 240),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: opts.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: BodylineColors.border),
                    itemBuilder: (context, i) {
                      final s = opts[i];
                      final kindLabel = medicationKindLabel(s.kind);
                      final sub = s.saltName != null
                          ? '$kindLabel · ${s.saltName}'
                          : kindLabel;
                      return ListTile(
                        dense: true,
                        title: Text(s.name, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          sub,
                          style: TextStyle(
                            fontSize: 11,
                            color: BodylineColors.inkSubtle,
                          ),
                        ),
                        onTap: () => onSelected(s),
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
