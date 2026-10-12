import 'package:flutter/material.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'dose_wait_controller.dart';

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
    DoseWaitController.instance.addListener(_onWait);
    _load();
  }

  @override
  void didUpdateWidget(covariant TodaysDosesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  @override
  void dispose() {
    DoseWaitController.instance.removeListener(_onWait);
    super.dispose();
  }

  void _onWait() {
    if (mounted) setState(() {});
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

    final showHeader = widget.mode != TodaysDosesMode.detailList;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          Text(
            "Today's doses",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Mark taken or skipped on this device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ] else ...[
          Text(
            "Today's doses",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Mark taken or skipped on this device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
        ],
        _waitBanner(),
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

  Widget _waitBanner() {
    final wait = DoseWaitController.instance;
    if (!wait.isRunning) return const SizedBox.shrink();
    final title = wait.mode == DoseWaitMode.countdown
        ? DoseWaitController.formatDuration(wait.remaining ?? Duration.zero)
        : DoseWaitController.formatDuration(wait.elapsed ?? Duration.zero);
    final subtitle = wait.mode == DoseWaitMode.countdown
        ? 'Wait remaining${wait.label != null ? ' · ${wait.label}' : ''}'
        : 'Stopwatch${wait.label != null ? ' · ${wait.label}' : ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _card(
        child: Row(
          children: [
            Icon(Icons.timer, color: BodylineColors.teal),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: BodylineColors.inkSubtle,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => DoseWaitController.instance.stop(),
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _doseTile(MedicationDoseSlot d) {
    final status = d.logStatus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  d.timeHm,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!d.isDone) ...[
                  OutlinedButton(
                    onPressed: () => _mark(d, 'skipped'),
                    child: const Text('Skip'),
                  ),
                  FilledButton(
                    onPressed: () => _mark(d, 'taken'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BodylineColors.teal,
                    ),
                    child: const Text('Taken'),
                  ),
                ],

              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        border: Border.all(color: BodylineColors.border),
      ),
      child: child,
    );
  }
}
