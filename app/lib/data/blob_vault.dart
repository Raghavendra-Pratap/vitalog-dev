import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'secure_keys.dart';

/// Encrypted, content-addressed attachments under blobs/<sha256>.enc
mixin BlobVaultMixin {
  Database get userDb;
  Uuid get uuid;
  SecureKeys get secureKeys;

  Future<Directory> _blobsDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'blobs'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<int>> _encrypt(List<int> plain) async {
    final keyBytes = await secureKeys.blobKeyBytes();
    final algo = AesGcm.with256bits();
    final secretKey = await algo.newSecretKeyFromBytes(keyBytes);
    final box = await algo.encrypt(plain, secretKey: secretKey);
    // nonce || mac || ciphertext
    return [...box.nonce, ...box.mac.bytes, ...box.cipherText];
  }

  Future<List<int>> _decrypt(List<int> packed) async {
    final keyBytes = await secureKeys.blobKeyBytes();
    final algo = AesGcm.with256bits();
    final secretKey = await algo.newSecretKeyFromBytes(keyBytes);
    final nonce = packed.sublist(0, 12);
    final mac = Mac(packed.sublist(12, 28));
    final cipherText = packed.sublist(28);
    return algo.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: secretKey,
    );
  }

  Future<AttachmentRecord> addAttachment({
    required String ownerType,
    required String ownerId,
    required String filePath,
    required String mime,
    String? fileName,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    return addAttachmentBytes(
      ownerType: ownerType,
      ownerId: ownerId,
      bytes: bytes,
      mime: mime,
      fileName: fileName ?? p.basename(filePath),
    );
  }

  Future<AttachmentRecord> addAttachmentBytes({
    required String ownerType,
    required String ownerId,
    required List<int> bytes,
    required String mime,
    required String fileName,
  }) async {
    final digest = sha256.convert(bytes).toString();
    final enc = await _encrypt(bytes);
    final dir = await _blobsDir();
    final out = File(p.join(dir.path, '$digest.enc'));
    if (!await out.exists()) {
      await out.writeAsBytes(enc, flush: true);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = uuid.v4();
    await userDb.insert('attachment', {
      'id': id,
      'owner_type': ownerType,
      'owner_id': ownerId,
      'sha256': digest,
      'mime': mime,
      'byte_size': bytes.length,
      'page_count': null,
      'file_name': fileName,
      'created_at': now,
      'updated_at': now,
      'hlc': '$now-0-local',
      'deleted': 0,
    });

    return AttachmentRecord(
      id: id,
      ownerType: ownerType,
      ownerId: ownerId,
      sha256: digest,
      mime: mime,
      byteSize: bytes.length,
      fileName: fileName,
    );
  }

  Future<List<AttachmentRecord>> listAttachments({
    required String ownerType,
    required String ownerId,
  }) async {
    final rows = await userDb.query(
      'attachment',
      where: 'owner_type = ? AND owner_id = ? AND deleted = 0',
      whereArgs: [ownerType, ownerId],
      orderBy: 'created_at DESC',
    );
    return [
      for (final r in rows)
        AttachmentRecord(
          id: r['id']! as String,
          ownerType: r['owner_type']! as String,
          ownerId: r['owner_id']! as String,
          sha256: r['sha256']! as String,
          mime: r['mime']! as String,
          byteSize: r['byte_size']! as int,
          fileName: r['file_name'] as String?,
        ),
    ];
  }



  Future<List<AttachmentRecord>> listAllAttachmentsForProfile(
    String profileId,
  ) async {
    final rows = await userDb.rawQuery(
      "SELECT a.* FROM attachment a "
      "WHERE a.deleted = 0 AND ("
      "(a.owner_type = 'report' AND a.owner_id IN ("
      "SELECT id FROM report WHERE profile_id = ? AND deleted = 0)) OR "
      "(a.owner_type = 'visit' AND a.owner_id IN ("
      "SELECT id FROM visit WHERE profile_id = ? AND deleted = 0)) OR "
      "(a.owner_type = 'procedure' AND a.owner_id IN ("
      "SELECT id FROM procedure_record WHERE profile_id = ? AND deleted = 0))"
      ") ORDER BY a.created_at DESC",
      [profileId, profileId, profileId],
    );
    return [
      for (final r in rows)
        AttachmentRecord(
          id: r['id']! as String,
          ownerType: r['owner_type']! as String,
          ownerId: r['owner_id']! as String,
          sha256: r['sha256']! as String,
          mime: r['mime']! as String,
          byteSize: r['byte_size']! as int,
          fileName: r['file_name'] as String?,
        ),
    ];
  }

  Future<int> attachmentCountForReport(String reportId) async {
    final rows = await userDb.rawQuery(
      'SELECT COUNT(*) AS c FROM attachment WHERE owner_type = ? AND owner_id = ? AND deleted = 0',
      ['report', reportId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Decrypt to a temp file for viewing/sharing. Caller should delete after.
  Future<File> materializeAttachment(AttachmentRecord att) async {
    final dir = await _blobsDir();
    final encFile = File(p.join(dir.path, '${att.sha256}.enc'));
    if (!await encFile.exists()) {
      throw StateError('Missing blob ${att.sha256}');
    }
    final packed = await encFile.readAsBytes();
    final plain = await _decrypt(packed);
    final tmp = await getTemporaryDirectory();
    final name = att.fileName ?? 'attachment';
    final out = File(p.join(tmp.path, 'bodyline_${att.id}_$name'));
    await out.writeAsBytes(Uint8List.fromList(plain), flush: true);
    return out;
  }


  /// Write encrypted blob bytes for a known sha256 (LAN sync ingest).
  Future<void> ingestPlainBlob({
    required String sha256,
    required List<int> bytes,
  }) async {
    final enc = await _encrypt(bytes);
    final dir = await _blobsDir();
    final out = File(p.join(dir.path, '$sha256.enc'));
    if (!await out.exists()) {
      await out.writeAsBytes(enc, flush: true);
    }
  }

  Future<void> softDeleteAttachment(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await userDb.update(
      'attachment',
      {'deleted': 1, 'updated_at': now, 'hlc': '$now-0-local'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> wipeBlobs() async {
    final dir = await _blobsDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
