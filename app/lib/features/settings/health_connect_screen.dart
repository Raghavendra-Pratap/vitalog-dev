import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/health_connect_service.dart';
import '../../data/local_store.dart';
import '../../theme/tokens.dart';

/// Opt-in Health Connect / HealthKit bridge (ADR-011).
class HealthConnectScreen extends StatefulWidget {
  const HealthConnectScreen({
    super.key,
    required this.store,
    this.onChanged,
  });

  final LocalStore store;
  final VoidCallback? onChanged;

  @override
  State<HealthConnectScreen> createState() => _HealthConnectScreenState();
}

class _HealthConnectScreenState extends State<HealthConnectScreen> {
  final _hc = HealthConnectService();
  HealthBridgeStatus _status = HealthBridgeStatus.unsupported;
  bool _write = false;
  DateTime? _lastSync;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await _hc.status();
    final write = await _hc.isWriteEnabled();
    final last = await _hc.lastSyncAt();
    if (!mounted) return;
    setState(() {
      _status = status;
      _write = write;
      _lastSync = last;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      await _refresh();
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e is StateError
            ? e.message
            : 'Something went wrong. Try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _statusLine {
    switch (_status) {
      case HealthBridgeStatus.unsupported:
        return 'Available on Android (Health Connect) and iPhone (Apple Health).';
      case HealthBridgeStatus.missingApp:
        return 'Health Connect is not installed on this phone.';
      case HealthBridgeStatus.ready:
        return 'Not connected — vitals stay manual until you allow access.';
      case HealthBridgeStatus.needsAuth:
        return 'Permission expired or incomplete. Connect again.';
      case HealthBridgeStatus.connected:
        return 'Connected. Import pulls weight, glucose, blood pressure, steps, and sleep duration.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _lastSync == null
        ? 'Never'
        : DateFormat.yMMMd().add_jm().format(_lastSync!.toLocal());

    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(
        title: Text(_hc.platformLabel),
        backgroundColor: BodylineColors.paper,
        foregroundColor: BodylineColors.ink,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            _statusLine,
            style: TextStyle(
              fontSize: 15,
              height: 1.35,
              color: BodylineColors.ink.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Vitalog does not upload health data. Sync is only with the health '
            'app on this device, when you choose.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: BodylineColors.ink.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 20),
          if (_message != null) ...[
            Text(
              _message!,
              style: TextStyle(color: BodylineColors.danger, fontSize: 14),
            ),
            const SizedBox(height: 12),
          ],
          if (_status == HealthBridgeStatus.missingApp)
            FilledButton(
              onPressed: _busy ? null : () => _run(_hc.openInstallPage),
              child: const Text('Install Health Connect'),
            )
          else if (_status == HealthBridgeStatus.ready ||
              _status == HealthBridgeStatus.needsAuth)
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await _hc.connect();
                        setState(() => _message = 'Connected.');
                      }),
              child: Text('Connect ${_hc.platformLabel}'),
            )
          else if (_status == HealthBridgeStatus.connected) ...[
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        final pid = widget.store.activeProfileId;
                        if (pid == null) {
                          throw StateError('Choose a profile first.');
                        }
                        final result = await _hc.importRecent(
                          store: widget.store,
                          profileId: pid,
                        );
                        setState(() => _message = result.summary);
                      }),
              child: const Text('Import last 90 days'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Write new readings back'),
              subtitle: Text(
                'When you enter weight, glucose, steps, or sleep in Vitalog, also save to '
                '${_hc.platformLabel}.',
              ),
              value: _write,
              onChanged: _busy
                  ? null
                  : (v) => _run(() async {
                        await _hc.setWriteEnabled(v);
                      }),
            ),
            const SizedBox(height: 8),
            Text(
              'Last import: $last',
              style: TextStyle(
                fontSize: 13,
                color: BodylineColors.ink.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await _hc.disconnect();
                        setState(() => _message = 'Disconnected on this device.');
                      }),
              child: const Text('Disconnect'),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
