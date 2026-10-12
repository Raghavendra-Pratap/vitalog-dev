import 'package:flutter/material.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/trend_panel.dart';
import '../entry/manual_panel_screen.dart';

class TrendScreen extends StatefulWidget {
  const TrendScreen({
    super.key,
    required this.store,
    required this.parameterCode,
    required this.title,
    this.onChanged,
  });

  final LocalStore store;
  final String parameterCode;
  final String title;
  final VoidCallback? onChanged;

  @override
  State<TrendScreen> createState() => _TrendScreenState();
}

class _TrendScreenState extends State<TrendScreen> {
  var _tick = 0;

  void _refresh() {
    widget.onChanged?.call();
    if (mounted) setState(() => _tick++);
  }

  Future<void> _addReading() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualPanelScreen(
          store: widget.store,
          onSaved: _refresh,
          seedParameterCode: widget.parameterCode,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _editReading(ObservationRecord o) async {
    ReportRecord? report;
    for (final r in widget.store.reports) {
      if (r.id == o.reportId) {
        report = r;
        break;
      }
    }
    if (report == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualPanelScreen(
          store: widget.store,
          onSaved: _refresh,
          editReport: report,
        ),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(), // Title lives in TrendPanel body — avoid duplicate.
      body: TrendPanel(
        key: ValueKey('${widget.parameterCode}-$_tick'),
        store: widget.store,
        parameterCode: widget.parameterCode,
        title: widget.title,
        showHistory: true,
        showRangeSelector: true,
        onAddReading: _addReading,
        onEditReading: _editReading,
      ),
    );
  }
}
