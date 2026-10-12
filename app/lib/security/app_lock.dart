import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// PIN + optional biometric gate. Off until the user enables it.
///
/// Biometrics are a convenience unlock only — PIN remains the recovery path.
/// Devices without enrolled biometrics never expose the toggle (safe zone).
class AppLockController extends ChangeNotifier {
  AppLockController({FlutterSecureStorage? storage, LocalAuthentication? auth})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              // Unsigned macOS debug builds often fail with Data Protection keychain.
              mOptions: MacOsOptions(
                synchronizable: false,
                useDataProtectionKeyChain: false,
                accessibility: KeychainAccessibility.first_unlock,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ),
        _auth = auth ?? LocalAuthentication();

  static const _enabledKey = 'bodyline_lock_enabled_v1';
  static const _pinHashKey = 'bodyline_lock_pin_hash_v1';
  static const _bioKey = 'bodyline_lock_bio_v1';
  static const _privacyKey = 'bodyline_privacy_screen_v1';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;

  bool enabled = false;
  bool biometricEnabled = false;
  bool biometricAvailable = false;
  bool privacyScreen = true;
  bool unlocked = true;
  bool obscured = false;

  Future<void> load() async {
    enabled = (await _storage.read(key: _enabledKey)) == '1';
    biometricEnabled = (await _storage.read(key: _bioKey)) == '1';
    privacyScreen = (await _storage.read(key: _privacyKey)) != '0';
    unlocked = !enabled;
    await refreshBiometricAvailability();
    if (biometricEnabled && !biometricAvailable) {
      // Hardware/enrollment gone — keep PIN, clear stale bio preference.
      biometricEnabled = false;
      try {
        await _storage.write(key: _bioKey, value: '0');
      } catch (_) {}
    }
    notifyListeners();
  }

  /// True when this device can run a biometric prompt (fingerprint / face / etc.).
  Future<void> refreshBiometricAvailability() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) {
        biometricAvailable = false;
        return;
      }
      final canCheck = await _auth.canCheckBiometrics;
      final types = canCheck ? await _auth.getAvailableBiometrics() : <BiometricType>[];
      biometricAvailable = canCheck && types.isNotEmpty;
    } catch (_) {
      biometricAvailable = false;
    }
  }

  Future<bool> hasPin() async {
    final h = await _storage.read(key: _pinHashKey);
    return h != null && h.isNotEmpty;
  }

  String _hash(String pin) =>
      sha256.convert(utf8.encode('bodyline|$pin')).toString();

  Future<void> setPin(String pin) async {
    try {
      await _storage.write(key: _pinHashKey, value: _hash(pin));
      await _storage.write(key: _enabledKey, value: '1');
    } catch (e) {
      throw StateError('Could not save PIN on this device ($e)');
    }
    enabled = true;
    unlocked = true;
    notifyListeners();
  }

  Future<void> disable() async {
    try {
      await _storage.write(key: _enabledKey, value: '0');
      await _storage.delete(key: _pinHashKey);
      await _storage.write(key: _bioKey, value: '0');
    } catch (e) {
      throw StateError('Could not update lock settings ($e)');
    }
    enabled = false;
    biometricEnabled = false;
    unlocked = true;
    notifyListeners();
  }

  /// Enables biometrics only after a successful device prompt (proves enrollment).
  Future<void> setBiometric(bool on) async {
    if (on) {
      await refreshBiometricAvailability();
      if (!biometricAvailable) {
        throw StateError(
          'This device has no fingerprint or face unlock enrolled.',
        );
      }
      final ok = await _promptBiometric(
        reason: 'Confirm biometrics to unlock Vitalog',
      );
      if (!ok) {
        throw StateError('Biometric confirmation failed. PIN unlock still works.');
      }
    }
    try {
      await _storage.write(key: _bioKey, value: on ? '1' : '0');
    } catch (e) {
      throw StateError('Could not update biometric setting ($e)');
    }
    biometricEnabled = on;
    notifyListeners();
  }

  Future<void> setPrivacyScreen(bool on) async {
    try {
      await _storage.write(key: _privacyKey, value: on ? '1' : '0');
    } catch (e) {
      throw StateError('Could not update privacy screen ($e)');
    }
    privacyScreen = on;
    if (!on) obscured = false;
    notifyListeners();
  }

  Future<bool> unlockWithPin(String pin) async {
    final stored = await _storage.read(key: _pinHashKey);
    if (stored == null) return false;
    if (stored != _hash(pin)) return false;
    unlocked = true;
    obscured = false;
    notifyListeners();
    return true;
  }

  Future<bool> unlockWithBiometric() async {
    if (!biometricEnabled || !enabled) return false;
    final ok = await _promptBiometric(reason: 'Unlock Vitalog');
    if (ok) {
      unlocked = true;
      obscured = false;
      notifyListeners();
    }
    return ok;
  }

  /// Biometric-only — never falls back to the device lock screen PIN/pattern
  /// (that would bypass Vitalog's PIN gate).
  Future<bool> _promptBiometric({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  void lockNow() {
    if (!enabled) return;
    unlocked = false;
    notifyListeners();
  }

  void onPaused() {
    if (enabled) {
      unlocked = false;
    }
    if (privacyScreen) {
      obscured = true;
    }
    notifyListeners();
  }

  void onResumed() {
    // Stay locked until PIN/bio; clear obscure only after unlock
    if (!enabled) {
      obscured = false;
      unlocked = true;
    }
    notifyListeners();
  }
}
