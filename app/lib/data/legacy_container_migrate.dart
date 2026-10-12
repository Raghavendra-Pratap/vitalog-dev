import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One-time copy from the pre-rename macOS sandbox (`app.bodyline.bodyline`)
/// into the current `app.vitalog` container.
///
/// Never overwrites a non-empty `user.db`. Never deletes the old container.
Future<void> migrateLegacyMacContainerIfNeeded() async {
  if (!Platform.isMacOS) return;

  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return;

  const oldId = 'app.bodyline.bodyline';
  final oldRoot = p.join(home, 'Library', 'Containers', oldId, 'Data');
  final oldDocs = Directory(p.join(oldRoot, 'Documents'));
  if (!await oldDocs.exists()) return;

  final docs = await getApplicationDocumentsDirectory();
  final support = await getApplicationSupportDirectory();

  var copiedVault = false;

  final newUserDb = File(p.join(docs.path, 'user.db'));
  final newEmpty = !await newUserDb.exists() || await newUserDb.length() == 0;
  final oldUserDb = File(p.join(oldDocs.path, 'user.db'));
  final oldHasDb =
      await oldUserDb.exists() && await oldUserDb.length() > 0;

  if (newEmpty && oldHasDb) {
    await docs.create(recursive: true);
    await oldUserDb.copy(newUserDb.path);
    copiedVault = true;

    final oldMarker = File(p.join(oldDocs.path, 'user.db.plain_migrated'));
    if (await oldMarker.exists()) {
      await oldMarker.copy(p.join(docs.path, 'user.db.plain_migrated'));
    }

    final oldBlobs = Directory(p.join(oldDocs.path, 'blobs'));
    if (await oldBlobs.exists()) {
      await _copyDirectoryRecursive(
        oldBlobs,
        Directory(p.join(docs.path, 'blobs')),
      );
    }
  }

  final oldSupportRoot =
      Directory(p.join(oldRoot, 'Library', 'Application Support'));
  if (await oldSupportRoot.exists()) {
    final keyFiles = await _legacyKeyFiles(oldSupportRoot);
    if (keyFiles.isNotEmpty) {
      await support.create(recursive: true);
      for (final src in keyFiles) {
        final dest = File(p.join(support.path, p.basename(src.path)));
        if (await dest.exists() && await dest.length() > 0) continue;
        await src.copy(dest.path);
        copiedVault = true;
      }
    }
  }

  if (copiedVault) {
    debugPrint('Vitalog: migrated local vault from app.bodyline.bodyline');
  }
}

Future<List<File>> _legacyKeyFiles(Directory supportRoot) async {
  final out = <File>[];
  await for (final entity in supportRoot.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    // secure_keys.dart file fallback: `.$key` (e.g. `.bodyline_user_db_key_v1`)
    if (name.startsWith('.') && name.toLowerCase().contains('key')) {
      if (await entity.length() > 0) out.add(entity);
    }
  }
  return out;
}

Future<void> _copyDirectoryRecursive(Directory src, Directory dest) async {
  await dest.create(recursive: true);
  await for (final entity in src.list(recursive: false, followLinks: false)) {
    final name = p.basename(entity.path);
    if (entity is Directory) {
      await _copyDirectoryRecursive(entity, Directory(p.join(dest.path, name)));
    } else if (entity is File) {
      await entity.copy(p.join(dest.path, name));
    }
  }
}
