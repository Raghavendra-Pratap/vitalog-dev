import 'package:flutter/material.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

enum TodaysDosesMode { full, masterCard, detailList }

/// Today's scheduled doses with Taken / Skip.
/// Lives on Reminders (not Medicines).
class TodaysDosesPanel extends StatefulWidget {
  const TodaysDosesPanel({
    super.key,
    required this.store,
    required this.onChanged,
    this.compact = false,
    this.mode = TodaysDosesMode.full,
    this.selected = false,
    this.onSelect,
  });

  final LocalStore store;
  final VoidCallback onChanged;
  final bool compact;
  final TodaysDosesMode mode;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  State<TodaysDosesPanel> createState() => TodaysDosesPanelState();
}

class TodaysDosesPanelState extends State<TodaysDosesPanel> {
  List<MedicationDoseSlot> _doses = [];
  var _loading = true;
  var _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TodaysDosesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    final gen = ++_loadGen;
    final pid = widget.store.activeProfileId;
    if (pid == null) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _doses = [];
        _loading = false;
      });
      return;
    }
    final doses = await widget.store.listTodaysDoses(pid);
    if (!mounted || gen != _loadGen) return;
    setState(() {
      _doses = doses;
      _loading = false;
    });
  }

  Future<void> _mark(MedicationDoseSlot slot, String status) async {
    if (status == 'taken') {
      await widget.store.logMedicationTaken(
        actedByProfileId: widget.store.activeProfileId,
        medicationId: slot.medicationId,
        scheduledFor: slot.scheduledFor,
      );
    } else {
      await widget.store.logMedicationSkipped(
        actedByProfileId: widget.store.activeProfileId,
        medicationId: slot.medicationId,
        scheduledFor: slot.scheduledFor,
      );
    }
    widget.onChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (widget.mode == TodaysDosesMode.masterCard) {
      final pending = _doses.where((d) => !d.isDone).length;
      final subtitle = _doses.isEmpty
          ? 'No dose times for today'
          : pending == 0
              ? '${_doses.length} logged · all marked'
              : '$pending to take · ${_doses.length} today';
      return Material(
        color: widget.selected
            ? BodylineColors.selectedWash
            : BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(BodylineRadii.card),
          onTap: widget.onSelect,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BodylineRadii.card),
              border: Border.all(
                color: widget.selected
                    ? BodylineColors.teal
                    : BodylineColors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's doses",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: widget.selected
                        ? BodylineColors.tealDark
                        : BodylineColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_doses.isEmpty)
          _card(
            child: Text(
              'No dose times for today. Add times on a medicine to see them here.',
              style: TextStyle(color: BodylineColors.inkSubtle),
            ),
          )
        else
          for (final d in _doses) _doseTile(d),

      ],
    );
  }

  Widget _doseTile(MedicationDoseSlot d) {
    final status = d.logStatus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _card(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              d.timeHm,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: BodylineColors.ink,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: BodylineColors.ink,
                    ),
                  ),
                  Text(
                    [
                      medicationKindLabel(d.kind),
                      if (d.strength != null && d.strength!.isNotEmpty)
                        d.strength!,
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                ],
              ),
            ),
            if (status == 'taken')
              Text(
                'Taken',
                style: TextStyle(
                  color: BodylineColors.teal,
                  fontWeight: FontWeight.w700,
                ),
              )
            else if (status == 'skipped')
              Text(
                'Skipped',
                style: TextStyle(
                  color: BodylineColors.inkSubtle,
                  fontWeight: FontWeight.w600,
                ),
              )
            else ...[
              OutlinedButton(
                onPressed: () => _mark(d, 'skipped'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('Skip'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _mark(d, 'taken'),
                style: FilledButton.styleFrom(
                  backgroundColor: BodylineColors.teal,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('Taken'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    final dense = widget.compact || widget.mode == TodaysDosesMode.detailList;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: dense ? 2 : 4),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 14,
        vertical: dense ? 8 : 14,
      ),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        border: Border.all(color: BodylineColors.border),
      ),
      child: child,
    );
  }
}
