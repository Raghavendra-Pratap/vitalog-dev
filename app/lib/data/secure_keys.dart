import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../security/vitalog_secure_storage.dart';

/// Device-bound secrets for SQLCipher + blob encryption.
class SecureKeys {
  SecureKeys({FlutterSecureStorage? storage})
      : _storage = storage ?? vitalogSecureStorage;

  static const _dbKeyName = 'bodyline_user_db_key_v1';
  static const _blobKeyName = 'bodyline_blob_key_v1';

  final FlutterSecureStorage _storage;

  Future<String> databasePassword() async {
    await _migratePlaintextFiles();
    return _readOrCreate(_dbKeyName, () => _randomBase64(48));
  }

  /// 32-byte AES key for attachment blobs.
  Future<List<int>> blobKeyBytes() async {
    final b64 = await _readOrCreate(
      _blobKeyName,
      () => base64Encode(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      ),
    );
    return base64Decode(b64);
  }

  Future<String> _readOrCreate(String key, String Function() generate) async {
    final existing = await _readKeychain(key);
    if (existing != null) {
      await _deleteFallbackFile(key);
      return existing;
    }

    final fromFile = await _readFallbackFile(key);
    if (fromFile != null) {
      await _storage.write(key: key, value: fromFile);
      final stored = await _storage.read(key: key);
      if (stored != fromFile) {
        throw StateError('Could not move the local encryption key into Keychain.');
      }
      await _deleteFallbackFile(key);
      return fromFile;
    }

    final generated = generate();
    await _storage.write(key: key, value: generated);
    return generated;
  }

  Future<void> _migratePlaintextFiles() async {
    for (final key in [_dbKeyName, _blobKeyName]) {
      final fromFile = await _readFallbackFile(key);
      if (fromFile == null) continue;
      final existing = await _readKeychain(key);
      if (existing != null) {
        if (existing == fromFile) await _deleteFallbackFile(key);
        continue;
      }
      await _storage.write(key: key, value: fromFile);
      final stored = await _storage.read(key: key);
      if (stored == fromFile) await _deleteFallbackFile(key);
    }
  }

  Future<String?> _readKeychain(String key) async {
    final existing = await _storage.read(key: key);
    if (existing == null || existing.isEmpty) return null;
    return existing;
  }

  Future<File> _fallbackFile(String key) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, '.$key'));
  }

  Future<String?> _readFallbackFile(String key) async {
    final file = await _fallbackFile(key);
    if (!await file.exists()) return null;
    final value = (await file.readAsString()).trim();
    if (value.isEmpty) return null;
    return value;
  }

  Future<void> _deleteFallbackFile(String key) async {
    final file = await _fallbackFile(key);
    if (!await file.exists()) return;
    final length = await file.length();
    await file.writeAsBytes(List<int>.filled(length, 0), flush: true);
    await file.delete();
  }

  String _randomBase64(int byteLen) {
    final bytes =
        List<int>.generate(byteLen, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes);
  }
}
