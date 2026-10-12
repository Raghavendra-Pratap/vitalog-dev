import 'package:flutter/material.dart';

import '../features/shell/app_shell.dart';
import '../desktop.dart';
import '../theme/tokens.dart';

/// Branded modal — lockup optional, Fraunces title, soft paper surface.
Future<T?> showBodylineDialog<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required Widget content,
  List<Widget> Function(BuildContext dialogContext)? actionsBuilder,
  List<Widget>? actions,
  bool showLockup = true,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: BodylineColors.ink.withValues(alpha: 0.35),
    builder: (ctx) {
      final actionWidgets = actionsBuilder?.call(ctx) ?? actions ?? const <Widget>[];
      return Dialog(
        backgroundColor: BodylineColors.surface,
        elevation: 0,
        insetPadding: bodylineDialogInset(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BodylineRadii.sheet),
          side: BorderSide(color: BodylineColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showLockup) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: BodylineLockup(markSize: 26, wordSize: 18),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                title,
                style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 18),
              content,
              if (actionWidgets.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actionWidgets.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actionWidgets[i],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class BodylineSelectOption<T> {
  const BodylineSelectOption({required this.value, required this.label});
  final T value;
  final String label;
}

/// Branded bottom sheet picker — replaces bare Material dropdown menus.
Future<BodylineSelectOption<T>?> showBodylineSelectOption<T>({
  required BuildContext context,
  required String title,
  required List<BodylineSelectOption<T>> options,
  T? selected,
}) {
  return showModalBottomSheet<BodylineSelectOption<T>>(
    context: context,
    backgroundColor: BodylineColors.surface,
    barrierColor: BodylineColors.ink.withValues(alpha: 0.35),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(BodylineRadii.sheet)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
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
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  title,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontFamily: 'Fraunces',
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: BodylineColors.divider),
                  itemBuilder: (context, i) {
                    final o = options[i];
                    final isSelected = o.value == selected;
                    return ListTile(
                      onTap: () => Navigator.pop(ctx, o),
                      title: Text(
                        o.label,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isSelected
                              ? BodylineColors.tealDark
                              : BodylineColors.ink,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check, color: BodylineColors.teal)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Field that opens [showBodylineSelectSheet] — same footprint as a dropdown.
class BodylineSelectField<T> extends StatelessWidget {
  const BodylineSelectField({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.options,
    required this.onSelected,
    this.value,
  });

  final String label;
  final String valueLabel;
  final T? value;
  final List<BodylineSelectOption<T>> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showBodylineSelectOption<T>(
          context: context,
          title: label,
          options: options,
          selected: value,
        );
        if (picked != null) onSelected(picked.value);
      },
      borderRadius: BorderRadius.circular(BodylineRadii.input),
      child: InputDecorator(
        isFocused: false,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: Icon(Icons.expand_more, color: BodylineColors.inkMuted),
        ),
        child: Text(
          valueLabel,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: BodylineColors.ink,
          ),
        ),
      ),
    );
  }
}
