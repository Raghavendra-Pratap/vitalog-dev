import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../security/app_lock.dart';
import '../../theme/tokens.dart';
import '../shell/app_shell.dart';

/// Full-screen lock + privacy obscure overlay.
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.lock,
    required this.child,
  });

  final AppLockController lock;
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  final _pin = TextEditingController();
  String? _error;
  bool _bioPrompted = false;
  bool _bioBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.lock.addListener(_onLock);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoBio());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.lock.removeListener(_onLock);
    _pin.dispose();
    super.dispose();
  }

  void _onLock() {
    if (mounted) {
      setState(() {});
      if (widget.lock.enabled && !widget.lock.unlocked) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoBio());
      } else {
        _bioPrompted = false;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _bioPrompted = false;
      widget.lock.onPaused();
    } else if (state == AppLifecycleState.resumed) {
      widget.lock.onResumed();
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoBio());
    }
  }

  Future<void> _maybeAutoBio() async {
    final lock = widget.lock;
    if (!mounted ||
        !lock.enabled ||
        lock.unlocked ||
        !lock.biometricEnabled ||
        !lock.biometricAvailable ||
        _bioPrompted ||
        _bioBusy) {
      return;
    }
    _bioPrompted = true;
    await _tryBio(showError: false);
  }

  Future<void> _tryBio({required bool showError}) async {
    if (_bioBusy) return;
    setState(() {
      _bioBusy = true;
      if (showError) _error = null;
    });
    final ok = await widget.lock.unlockWithBiometric();
    if (!mounted) return;
    setState(() {
      _bioBusy = false;
      if (!ok && showError) {
        _error = 'Biometric unlock failed. Use your PIN.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = widget.lock;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (lock.obscured && lock.unlocked)
          ColoredBox(
            color: BodylineColors.paper,
            child: Center(child: _PrivacyBrand()),
          ),
        if (lock.enabled && !lock.unlocked) _lockScreen(context),
      ],
    );
  }

  Widget _lockScreen(BuildContext context) {
    final showBio =
        widget.lock.biometricEnabled && widget.lock.biometricAvailable;
    return Material(
      color: BodylineColors.paper,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Center(child: _PrivacyBrand()),
              const SizedBox(height: 28),
              Text(
                'Enter your PIN to open health data on this device.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 8,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  errorText: _error,
                  counterText: '',
                ),
                onSubmitted: (_) => _submitPin(),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submitPin,
                style: FilledButton.styleFrom(
                  backgroundColor: BodylineColors.teal,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Unlock'),
              ),
              if (showBio) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _bioBusy ? null : () => _tryBio(showError: true),
                  icon: const Icon(Icons.fingerprint),
                  label: Text(_bioBusy ? 'Waiting…' : 'Use biometrics'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: BodylineColors.tealDark,
                  ),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitPin() async {
    final ok = await widget.lock.unlockWithPin(_pin.text.trim());
    if (!mounted) return;
    if (ok) {
      _pin.clear();
      setState(() => _error = null);
    } else {
      setState(() => _error = 'That PIN does not match.');
    }
  }
}

/// Large brand block for privacy obscure + lock (ADR-007).
class _PrivacyBrand extends StatelessWidget {
  const _PrivacyBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BodylineLockup(markSize: 72, wordSize: 48),
        const SizedBox(height: 14),
        Text(
          'Your body, over time.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: BodylineColors.inkSubtle,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
                height: 1.3,
              ),
        ),
      ],
    );
  }
}
