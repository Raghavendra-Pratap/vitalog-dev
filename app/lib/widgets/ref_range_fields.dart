import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ref_range_suggestions.dart';
import '../theme/tokens.dart';

/// How reference limits are entered for a parameter.
enum RefRangeMode {
  /// One Low / High pair.
  single,
  /// Ordered or life-stage bands (child / adult, …).
  stage,
  /// Patient-state bands (non-pregnant, trimester, …).
  condition,
}

bool _looksLikeConditionLabel(String label) {
  final n = label.toLowerCase();
  return n.contains('pregnant') ||
      n.contains('trimester') ||
      n.contains('postpartum') ||
      n.contains('menopaus') ||
      n.contains('fasting') && n.contains('non');
}

RefRangeMode modeFromBands(List<RefBand> bands) {
  for (final b in bands) {
    final lab = b.label;
    if (lab != null && lab.isNotEmpty && _looksLikeConditionLabel(lab)) {
      return RefRangeMode.condition;
    }
  }
  return RefRangeMode.stage;
}

/// Simple Low/High fields with optional history chips (ADR-006).
/// Prefer [RefRangeEditor] when Stages / multi-bands are needed.
class RefRangeFields extends StatelessWidget {
  const RefRangeFields({
    super.key,
    required this.lowController,
    required this.highController,
    required this.suggestions,
    this.enabled = true,
    this.dense = false,
    this.onChanged,
    this.lowLabel = 'Low',
    this.highLabel = 'High',
  });

  final TextEditingController lowController;
  final TextEditingController highController;
  final List<RefRangeSuggestion> suggestions;
  final bool enabled;
  final bool dense;
  final VoidCallback? onChanged;
  final String lowLabel;
  final String highLabel;

  void _apply(RefRangeSuggestion s, {required bool onlyIfEmpty}) {
    if (onlyIfEmpty && !refsBothEmpty(lowController.text, highController.text)) {
      return;
    }
    lowController.text = s.low == null ? '' : formatRefNum(s.low!);
    highController.text = s.high == null ? '' : formatRefNum(s.high!);
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final primary = suggestions.isEmpty ? null : suggestions.first;
    final alternates = suggestions.length <= 1
        ? const <RefRangeSuggestion>[]
        : suggestions.skip(1).toList();

    final fields = Row(
      children: [
        Expanded(
          child: TextField(
            controller: lowController,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
            ],
            decoration: InputDecoration(
              labelText: lowLabel,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onChanged: (_) => onChanged?.call(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: highController,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
            ],
            decoration: InputDecoration(
              labelText: highLabel,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onChanged: (_) => onChanged?.call(),
          ),
        ),
      ],
    );

    if (primary == null) return fields;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fields,
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'From your history (${primary.count}×)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: BodylineColors.inkSubtle,
                  ),
            ),
            ActionChip(
              label: Text(primary.chipLabel),
              onPressed: enabled
                  ? () => _apply(primary, onlyIfEmpty: false)
                  : null,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
        if (alternates.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Other ranges you’ve used',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: BodylineColors.inkSubtle,
                ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final s in alternates)
                ActionChip(
                  label: Text('${s.chipLabel} (${s.count}×)'),
                  onPressed: enabled
                      ? () => _apply(s, onlyIfEmpty: false)
                      : null,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Prefill Low/High from the top suggestion when both empty (ADR-006).
void autofillRefsFromHistory({
  required TextEditingController low,
  required TextEditingController high,
  required List<RefRangeSuggestion> suggestions,
}) {
  if (suggestions.isEmpty) return;
  if (!refsBothEmpty(low.text, high.text)) return;
  final s = suggestions.first;
  low.text = s.low == null ? '' : formatRefNum(s.low!);
  high.text = s.high == null ? '' : formatRefNum(s.high!);
}

/// Controllers for one stage row in Stages mode.
class RefBandRowControllers {
  RefBandRowControllers({
    String label = '',
    String low = '',
    String high = '',
    this.safe,
  })  : label = TextEditingController(text: label),
        low = TextEditingController(text: low),
        high = TextEditingController(text: high);

  factory RefBandRowControllers.fromBand(RefBand b) => RefBandRowControllers(
        label: b.label ?? '',
        low: b.low == null ? '' : formatRefNum(b.low!),
        high: b.high == null ? '' : formatRefNum(b.high!),
        safe: b.safe,
      );

  final TextEditingController label;
  final TextEditingController low;
  final TextEditingController high;
  /// null = unset, true = safe, false = unsafe (lab/user attributed).
  bool? safe;

  RefBand? toBand() {
    final lo = double.tryParse(low.text.trim().replaceAll(',', ''));
    final hi = double.tryParse(high.text.trim().replaceAll(',', ''));
    final lab = label.text.trim();
    if (lo == null && hi == null) return null;
    return RefBand(
      label: lab.isEmpty ? null : lab,
      low: lo,
      high: hi,
      safe: safe,
    );
  }

  void dispose() {
    label.dispose();
    low.dispose();
    high.dispose();
  }
}

/// Mutable holder for Single / Stage / Condition reference entry.
class RefRangeEditState {
  RefRangeEditState({
    TextEditingController? low,
    TextEditingController? high,
    List<RefBand>? initialBands,
    this.rangeSuggestions = const [],
    this.bandSetSuggestions = const [],
    bool preferStages = false,
    RefRangeMode? preferMode,
  })  : low = low ?? TextEditingController(),
        high = high ?? TextEditingController() {
    if (initialBands != null && initialBands.isNotEmpty) {
      mode = preferMode ?? modeFromBands(initialBands);
      bandRows = [
        for (final b in initialBands) RefBandRowControllers.fromBand(b),
      ];
      if (bandRows.isEmpty) {
        bandRows = [RefBandRowControllers()];
      }
    } else if (preferMode != null && preferMode != RefRangeMode.single) {
      mode = preferMode;
      bandRows = [RefBandRowControllers(), RefBandRowControllers()];
    } else if (preferStages) {
      mode = RefRangeMode.stage;
      bandRows = [RefBandRowControllers(), RefBandRowControllers()];
    } else {
      mode = RefRangeMode.single;
      bandRows = [];
    }
  }

  final TextEditingController low;
  final TextEditingController high;
  List<RefRangeSuggestion> rangeSuggestions;
  List<RefBandSetSuggestion> bandSetSuggestions;
  RefRangeMode mode = RefRangeMode.single;
  List<RefBandRowControllers> bandRows = [];
  /// Which condition band applies to this reading (Condition mode only).
  int? selectedConditionIndex;

  /// Back-compat for callers that still check [stages].
  bool get stages => mode != RefRangeMode.single;
  set stages(bool v) {
    if (v) {
      if (mode == RefRangeMode.single) mode = RefRangeMode.stage;
    } else {
      mode = RefRangeMode.single;
    }
  }

  List<RefBand>? get parsedBands {
    if (mode == RefRangeMode.single) return null;
    final out = <RefBand>[];
    for (final r in bandRows) {
      final b = r.toBand();
      if (b != null) out.add(b);
    }
    return out.isEmpty ? null : out;
  }

  double? get parsedLow {
    final t = low.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', ''));
  }

  double? get parsedHigh {
    final t = high.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', ''));
  }

  /// Effective refs for save.
  /// Condition mode: Low/High from the **selected** condition.
  /// Stage mode: outer envelope of all bands.
  ({double? low, double? high, List<RefBand>? bands}) snapshot() {
    final bands = parsedBands;
    if (bands != null && bands.isNotEmpty) {
      if (mode == RefRangeMode.condition) {
        final idx = (selectedConditionIndex ?? 0).clamp(0, bands.length - 1);
        final b = bands[idx];
        return (low: b.low, high: b.high, bands: bands);
      }
      final env = envelopeFromBands(bands);
      return (
        low: parsedLow ?? env.low,
        high: parsedHigh ?? env.high,
        bands: bands,
      );
    }
    return (low: parsedLow, high: parsedHigh, bands: null);
  }

  bool get hasSelectedCondition {
    if (mode != RefRangeMode.condition) return true;
    final bands = parsedBands;
    if (bands == null || bands.isEmpty) return false;
    final idx = selectedConditionIndex;
    return idx != null && idx >= 0 && idx < bands.length;
  }

  void disposeBandsOnly() {
    for (final r in bandRows) {
      r.dispose();
    }
    bandRows = [];
  }

  void dispose() {
    low.dispose();
    high.dispose();
    disposeBandsOnly();
  }

  void applyBandSet(List<RefBand> bands) {
    disposeBandsOnly();
    mode = modeFromBands(bands);
    bandRows = [
      for (final b in bands) RefBandRowControllers.fromBand(b),
    ];
    if (bandRows.isEmpty) {
      bandRows = [RefBandRowControllers()];
    }
    selectedConditionIndex =
        mode == RefRangeMode.condition ? 0 : null;
    final env = envelopeFromBands(bands);
    low.text = env.low == null ? '' : formatRefNum(env.low!);
    high.text = env.high == null ? '' : formatRefNum(env.high!);
  }
}

/// Prefill stages from history when empty (ADR-006).
void autofillBandsFromHistory({
  required RefRangeEditState state,
}) {
  if (state.bandSetSuggestions.isEmpty) return;
  if (!refsAndBandsEmpty(
    lowText: state.low.text,
    highText: state.high.text,
    bands: state.parsedBands,
  )) {
    return;
  }
  // Only auto-switch to Stages when history has a band set and simple is empty.
  state.applyBandSet(state.bandSetSuggestions.first.bands);
}

/// Single / Stage / Condition editor. Labels stay lab/user text (ADR-003).
class RefRangeEditor extends StatefulWidget {
  const RefRangeEditor({
    super.key,
    required this.state,
    this.enabled = true,
    this.dense = true,
    this.onChanged,
  });

  final RefRangeEditState state;
  final bool enabled;
  final bool dense;
  final VoidCallback? onChanged;

  @override
  State<RefRangeEditor> createState() => _RefRangeEditorState();
}

class _RefRangeEditorState extends State<RefRangeEditor> {
  RefRangeEditState get s => widget.state;

  Future<void> _setMode(RefRangeMode next) async {
    if (next == s.mode) return;
    if (next != RefRangeMode.single) {
      if (s.bandRows.isEmpty) {
        final lo = s.low.text.trim();
        final hi = s.high.text.trim();
        s.bandRows = [
          RefBandRowControllers(label: '', low: lo, high: hi),
          RefBandRowControllers(),
        ];
      }
      s.mode = next;
      if (next == RefRangeMode.condition) {
        s.selectedConditionIndex ??= 0;
      } else if (next == RefRangeMode.stage) {
        s.selectedConditionIndex = null;
      }
      setState(() {});
      widget.onChanged?.call();
      return;
    }
    final bands = s.parsedBands;
    final hasBandData = bands != null && bands.isNotEmpty;
    if (hasBandData) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Switch to Single?'),
          content: const Text(
            'Band rows stay for this edit if you switch back. '
            'Low/High will use the outer min/max of your bands.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Use Single'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final env = envelopeFromBands(bands);
      s.low.text = env.low == null ? '' : formatRefNum(env.low!);
      s.high.text = env.high == null ? '' : formatRefNum(env.high!);
    }
    s.mode = RefRangeMode.single;
    setState(() {});
    widget.onChanged?.call();
  }

  void _addRow({String label = ''}) {
    setState(() => s.bandRows.add(RefBandRowControllers(label: label)));
    widget.onChanged?.call();
  }

  void _removeRow(int i) {
    if (s.bandRows.length <= 1) return;
    setState(() {
      s.bandRows[i].dispose();
      s.bandRows.removeAt(i);
      final sel = s.selectedConditionIndex;
      if (sel != null) {
        if (sel >= s.bandRows.length) {
          s.selectedConditionIndex = s.bandRows.length - 1;
        } else if (sel == i) {
          s.selectedConditionIndex = 0;
        } else if (sel > i) {
          s.selectedConditionIndex = sel - 1;
        }
      }
    });
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isCondition = s.mode == RefRangeMode.condition;
    final isMulti = s.mode != RefRangeMode.single;

    final modeDrop = SizedBox(
      width: 118,
      child: DropdownButtonFormField<RefRangeMode>(
        key: ValueKey(s.mode),
        initialValue: s.mode,
        isDense: true,
        decoration: const InputDecoration(
          labelText: 'Range',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        items: const [
          DropdownMenuItem(
            value: RefRangeMode.single,
            child: Text('Single', style: TextStyle(fontSize: 13)),
          ),
          DropdownMenuItem(
            value: RefRangeMode.stage,
            child: Text('Stage', style: TextStyle(fontSize: 13)),
          ),
          DropdownMenuItem(
            value: RefRangeMode.condition,
            child: Text('Condition', style: TextStyle(fontSize: 13)),
          ),
        ],
        onChanged: !widget.enabled
            ? null
            : (v) {
                if (v != null) _setMode(v);
              },
      ),
    );

    Widget lowHighRow({required bool expand}) {
      final lowField = TextField(
        controller: s.low,
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
        ],
        decoration: const InputDecoration(
          labelText: 'Low',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        onChanged: (_) => widget.onChanged?.call(),
      );
      final highField = TextField(
        controller: s.high,
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
        ],
        decoration: const InputDecoration(
          labelText: 'High',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        onChanged: (_) => widget.onChanged?.call(),
      );
      if (!expand) {
        return Row(
          children: [
            modeDrop,
            const SizedBox(width: 8),
            Expanded(child: lowField),
            const SizedBox(width: 8),
            Expanded(child: highField),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          modeDrop,
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: lowField),
              const SizedBox(width: 8),
              Expanded(child: highField),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isMulti) ...[
          lowHighRow(expand: false),
          if (s.rangeSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'History',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: BodylineColors.inkSubtle,
                      ),
                ),
                for (final sug in s.rangeSuggestions.take(3))
                  ActionChip(
                    label: Text(
                      sug.chipLabel,
                      style: const TextStyle(fontSize: 11),
                    ),
                    onPressed: widget.enabled
                        ? () {
                            s.low.text =
                                sug.low == null ? '' : formatRefNum(sug.low!);
                            s.high.text =
                                sug.high == null ? '' : formatRefNum(sug.high!);
                            widget.onChanged?.call();
                            setState(() {});
                          }
                        : null,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        ] else ...[
          modeDrop,
          const SizedBox(height: 10),
          Text(
            isCondition
                ? 'Add conditions from the report, then select which one applies.'
                : 'Stage limits as on the report.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: BodylineColors.inkSubtle,
                ),
          ),
          if (isCondition &&
              s.parsedBands != null &&
              s.parsedBands!.isNotEmpty &&
              s.selectedConditionIndex == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Select one condition for this reading.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: BodylineColors.danger,
                    ),
              ),
            ),
          const SizedBox(height: 10),
          for (var i = 0; i < s.bandRows.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _StageRow(
              controllers: s.bandRows[i],
              enabled: widget.enabled,
              dense: true,
              canRemove: s.bandRows.length > 1,
              labelHint:
                  isCondition ? 'e.g. Non-pregnant' : 'e.g. Adult',
              labelTitle: isCondition ? 'Condition' : 'Stage',
              selectable: isCondition,
              selected: s.selectedConditionIndex == i,
              onSelect: isCondition
                  ? () => setState(() {
                        s.selectedConditionIndex = i;
                        widget.onChanged?.call();
                      })
                  : null,
              onRemove: () => _removeRow(i),
              onChanged: widget.onChanged,
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.enabled ? () => _addRow() : null,
              icon: const Icon(Icons.add, size: 16),
              label: Text(isCondition ? 'Add condition' : 'Add stage'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
          if (s.bandSetSuggestions.isNotEmpty) ...[
            Text(
              'From your history (${s.bandSetSuggestions.first.count}×)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: BodylineColors.inkSubtle,
                  ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                for (final sug in s.bandSetSuggestions)
                  ActionChip(
                    label: Text(
                      sug == s.bandSetSuggestions.first
                          ? sug.chipLabel
                          : '${sug.chipLabel} (${sug.count}×)',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onPressed: widget.enabled
                        ? () {
                            setState(() => s.applyBandSet(sug.bands));
                            widget.onChanged?.call();
                          }
                        : null,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}


class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.controllers,
    required this.enabled,
    required this.dense,
    required this.canRemove,
    required this.onRemove,
    this.onChanged,
    this.labelTitle = 'Stage',
    this.labelHint = 'e.g. Adult',
    this.selectable = false,
    this.selected = false,
    this.onSelect,
  });

  final RefBandRowControllers controllers;
  final bool enabled;
  final bool dense;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback? onChanged;
  final String labelTitle;
  final String labelHint;
  final bool selectable;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    const pad = EdgeInsets.symmetric(horizontal: 10, vertical: 10);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (selectable)
          IconButton(
            tooltip: selected ? 'Selected condition' : 'Use this condition',
            onPressed: enabled && onSelect != null ? onSelect : null,
            icon: Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 20,
              color: selected ? BodylineColors.teal : BodylineColors.inkSubtle,
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        Expanded(
          flex: 3,
          child: TextField(
            controller: controllers.label,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: labelTitle,
              hintText: labelHint,
              isDense: true,
              contentPadding: pad,
            ),
            onChanged: (_) => onChanged?.call(),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: TextField(
            controller: controllers.low,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Low',
              isDense: true,
              contentPadding: pad,
            ),
            onChanged: (_) => onChanged?.call(),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: TextField(
            controller: controllers.high,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
            ],
            decoration: const InputDecoration(
              labelText: 'High',
              isDense: true,
              contentPadding: pad,
            ),
            onChanged: (_) => onChanged?.call(),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            initialValue: controllers.safe == null
                ? 'unset'
                : (controllers.safe! ? 'safe' : 'unsafe'),
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Band',
              isDense: true,
              contentPadding: pad,
            ),
            items: const [
              DropdownMenuItem(value: 'unset', child: Text('—')),
              DropdownMenuItem(value: 'safe', child: Text('Safe')),
              DropdownMenuItem(value: 'unsafe', child: Text('Unsafe')),
            ],
            onChanged: !enabled
                ? null
                : (v) {
                    controllers.safe = v == 'safe'
                        ? true
                        : v == 'unsafe'
                            ? false
                            : null;
                    onChanged?.call();
                  },
          ),
        ),
        if (canRemove)
          IconButton(
            onPressed: enabled ? onRemove : null,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
      ],
    );
  }
}
