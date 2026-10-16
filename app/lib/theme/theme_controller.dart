import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../security/vitalog_secure_storage.dart';

/// Persists appearance: system / light / dark.
class ThemeController extends ChangeNotifier {
  ThemeController({FlutterSecureStorage? storage})
      : _storage = storage ?? vitalogSecureStorage;

  static const _key = 'vitalog_theme_mode_v1';
  final FlutterSecureStorage _storage;

  ThemeMode mode = ThemeMode.system;

  Future<void> load() async {
    final raw = await _storage.read(key: _key);
    mode = switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode next) async {
    mode = next;
    final value = switch (next) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    try {
      await _storage.write(key: _key, value: value);
    } catch (_) {}
    notifyListeners();
  }
}
