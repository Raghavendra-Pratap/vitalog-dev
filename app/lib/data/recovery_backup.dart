import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// M4 local piece: recovery passphrase → encrypt/decrypt full export.
/// Cloud sync itself is still manual (save the .blbak to Drive yourself).
class RecoveryBackup {
  RecoveryBackup({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _hintKey = 'bodyline_recovery_hint_v1';
  static const _verifyKey = 'bodyline_recovery_verify_v1';

  final FlutterSecureStorage _storage;

  Future<bool> hasRecoveryKey() async {
    final v = await _storage.read(key: _verifyKey);
    return v != null && v.isNotEmpty;
  }

  Future<String?> recoveryHint() => _storage.read(key: _hintKey);

  /// Returns the plaintext recovery key once (caller must show / print).
  Future<String> createRecoveryKey({String? hint}) async {
    final key = _randomKey();
    final verify = await _encryptString('bodyline-ok', key);
    await _storage.write(key: _verifyKey, value: verify);
    if (hint != null && hint.trim().isNotEmpty) {
      await _storage.write(key: _hintKey, value: hint.trim());
    }
    return key;
  }

  Future<bool> verifyRecoveryKey(String key) async {
    final stored = await _storage.read(key: _verifyKey);
    if (stored == null) return false;
    try {
      final plain = await _decryptString(stored, key);
      return plain == 'bodyline-ok';
    } catch (_) {
      return false;
    }
  }

  Future<File> wrapExportJson(String json, String recoveryKey) async {
    final packed = await _encryptString(json, recoveryKey);
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(
        dir.path,
        'bodyline-backup-${DateTime.now().millisecondsSinceEpoch}.blbak',
      ),
    );
    final envelope = jsonEncode({
      'format': 'bodyline-blbak-v1',
      'created_at': DateTime.now().toIso8601String(),
      'payload': packed,
    });
    await file.writeAsString(envelope, flush: true);
    return file;
  }

  Future<String> unwrapExportJson(String envelopeJson, String recoveryKey) async {
    final map = jsonDecode(envelopeJson) as Map<String, dynamic>;
    if (map['format'] != 'bodyline-blbak-v1') {
      throw StateError('Unknown backup format');
    }
    return _decryptString(map['payload'] as String, recoveryKey);
  }

  String _randomKey() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final parts = List.generate(4, (_) {
      return List.generate(4, (_) => alphabet[rnd.nextInt(alphabet.length)])
          .join();
    });
    return parts.join('-'); // e.g. AB3K-… human-ish
  }

  Future<List<int>> _deriveKey(String recoveryKey) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    );
    final secret = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(recoveryKey.trim().toUpperCase())),
      nonce: utf8.encode('bodyline-recovery-v1'),
    );
    return secret.extractBytes();
  }

  Future<String> _encryptString(String plain, String recoveryKey) async {
    final keyBytes = await _deriveKey(recoveryKey);
    final algo = AesGcm.with256bits();
    final secretKey = await algo.newSecretKeyFromBytes(keyBytes);
    final box = await algo.encrypt(
      utf8.encode(plain),
      secretKey: secretKey,
    );
    final packed = [...box.nonce, ...box.mac.bytes, ...box.cipherText];
    return base64Encode(packed);
  }

  Future<String> _decryptString(String b64, String recoveryKey) async {
    final packed = base64Decode(b64);
    final keyBytes = await _deriveKey(recoveryKey);
    final algo = AesGcm.with256bits();
    final secretKey = await algo.newSecretKeyFromBytes(keyBytes);
    final nonce = packed.sublist(0, 12);
    final mac = Mac(packed.sublist(12, 28));
    final cipherText = packed.sublist(28);
    final clear = await algo.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: secretKey,
    );
    return utf8.decode(clear);
  }
}
