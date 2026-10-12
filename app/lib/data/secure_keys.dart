import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Device-bound secrets for SQLCipher + blob encryption.
class SecureKeys {
  SecureKeys({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _dbKeyName = 'bodyline_user_db_key_v1';
  static const _blobKeyName = 'bodyline_blob_key_v1';

  final FlutterSecureStorage _storage;

  Future<String> databasePassword() async {
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
    try {
      final existing = await _storage.read(key: key);
      if (existing != null && existing.isNotEmpty) return existing;
      final generated = generate();
      await _storage.write(key: key, value: generated);
      return generated;
    } catch (_) {
      // macOS without Keychain Sharing / signing — file fallback (still local-only).
      return _fileFallback(key, generate);
    }
  }

  Future<String> _fileFallback(String key, String Function() generate) async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, '.$key'));
    if (await file.exists()) {
      final v = (await file.readAsString()).trim();
      if (v.isNotEmpty) return v;
    }
    final generated = generate();
    await file.writeAsString(generated, flush: true);
    return generated;
  }

  String _randomBase64(int byteLen) {
    final bytes =
        List<int>.generate(byteLen, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes);
  }
}
