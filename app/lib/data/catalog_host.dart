import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Result of [CatalogHost.updateFromHost].
class CatalogUpdateResult {
  const CatalogUpdateResult({
    required this.updated,
    required this.message,
    this.version,
    this.parameterCount,
    this.panelCount,
  });

  final bool updated;
  final String message;
  final String? version;
  final int? parameterCount;
  final int? panelCount;
}

/// Hosted replaceable test catalogue (ADR-001 — static files only).
class CatalogHost {
  CatalogHost._();
  static final CatalogHost instance = CatalogHost._();

  static const hostedManifestUrl =
      'https://vitalog.cc/catalog/catalog-manifest.json';
  static const hostedDbUrl = 'https://vitalog.cc/catalog/catalog.db';
  static const assetPath = 'assets/catalog/catalog.db';

  static const _cacheFileName = 'catalog.db';
  static const _metaFileName = 'catalog_host.json';
  static const _bundledPeekName = 'catalog.bundled.db';

  String? _version;
  String? _updated;
  String _source = 'bundled'; // bundled | downloaded
  int _parameterCount = 0;
  int _panelCount = 0;

  String get version => _version ?? '?';
  String? get updated => _updated;
  String get source => _source;
  int get parameterCount => _parameterCount;
  int get panelCount => _panelCount;

  Future<Directory> _docsDir() => getApplicationDocumentsDirectory();

  Future<File> cacheFile() async {
    final dir = await _docsDir();
    return File(p.join(dir.path, _cacheFileName));
  }

  Future<File> _metaFile() async {
    final dir = await _docsDir();
    return File(p.join(dir.path, _metaFileName));
  }

  /// Compare dotted catalogue versions (`2.1` vs `2.10`).
  static int compareVersion(String a, String b) {
    List<int> parts(String v) => v
        .split('.')
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static Future<String?> versionFromDb(Database db) async {
    try {
      final rows = await db.query(
        'catalog_meta',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: const ['version'],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<({int parameters, int panels})> countsFromDb(
    Database db,
  ) async {
    try {
      final pRows = await db.rawQuery('SELECT COUNT(*) AS c FROM parameter');
      final panRows = await db.rawQuery('SELECT COUNT(*) AS c FROM panel');
      return (
        parameters: (pRows.first['c'] as int?) ?? 0,
        panels: (panRows.first['c'] as int?) ?? 0,
      );
    } catch (_) {
      return (parameters: 0, panels: 0);
    }
  }

  Future<void> _loadMeta() async {
    try {
      final file = await _metaFile();
      if (!await file.exists()) return;
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _source = map['source'] as String? ?? _source;
      _updated = map['updated'] as String?;
    } catch (_) {
      // ignore corrupt sidecar
    }
  }

  Future<void> _writeMeta({
    required String source,
    required String version,
    String? updated,
  }) async {
    _source = source;
    _version = version;
    _updated = updated;
    final file = await _metaFile();
    await file.writeAsString(
      jsonEncode({
        'source': source,
        'version': version,
        if (updated != null) 'updated': updated,
      }),
    );
  }

  Future<void> _refreshStats(Database db) async {
    _version = await versionFromDb(db) ?? _version;
    final counts = await countsFromDb(db);
    _parameterCount = counts.parameters;
    _panelCount = counts.panels;
  }

  /// Ensure cache holds the newest of bundled vs prior download.
  /// Returns the absolute path for [openDatabase].
  Future<String> ensureLocalCatalog() async {
    await _loadMeta();
    final cache = await cacheFile();
    final dir = await _docsDir();
    final bundledPeek = File(p.join(dir.path, _bundledPeekName));

    final bundledData = await rootBundle.load(assetPath);
    final bundledBytes = bundledData.buffer.asUint8List(
      bundledData.offsetInBytes,
      bundledData.lengthInBytes,
    );
    await bundledPeek.writeAsBytes(bundledBytes, flush: true);
    final bundledDb = await openDatabase(bundledPeek.path, readOnly: true);
    final bundledVersion = await versionFromDb(bundledDb) ?? '0';
    await bundledDb.close();

    var useBundled = true;
    if (await cache.exists()) {
      try {
        final cachedDb = await openDatabase(cache.path, readOnly: true);
        final cachedVersion = await versionFromDb(cachedDb);
        await cachedDb.close();
        if (cachedVersion != null &&
            compareVersion(cachedVersion, bundledVersion) >= 0) {
          useBundled = false;
        }
      } catch (_) {
        useBundled = true;
      }
    }

    if (useBundled) {
      await cache.writeAsBytes(bundledBytes, flush: true);
      await _writeMeta(source: 'bundled', version: bundledVersion);
    }

    final db = await openDatabase(cache.path, readOnly: true);
    await _refreshStats(db);
    await db.close();
    if (_version == null) _version = bundledVersion;
    return cache.path;
  }

  /// One-line status for Settings.
  Future<String> statusLine() async {
    if (_version == null) {
      try {
        final cache = await cacheFile();
        if (await cache.exists()) {
          final db = await openDatabase(cache.path, readOnly: true);
          await _loadMeta();
          await _refreshStats(db);
          await db.close();
        }
      } catch (_) {
        // keep defaults
      }
    }
    final date =
        (_updated != null && _updated!.isNotEmpty) ? ' · $_updated' : '';
    final src = _source == 'downloaded' ? 'hosted' : 'in app';
    return 'v$version · $parameterCount parameters · $panelCount panels$date · $src';
  }

  /// Fetch hosted catalogue, replace local cache if newer and hash matches.
  Future<CatalogUpdateResult> updateFromHost({
    Duration timeout = const Duration(seconds: 45),
    Future<void> Function()? beforeSwap,
    Future<void> Function()? afterSwap,
  }) async {
    await ensureLocalCatalog();
    final currentVersion = _version ?? '0';

    late final http.Response manifestRes;
    try {
      manifestRes =
          await http.get(Uri.parse(hostedManifestUrl)).timeout(timeout);
    } on SocketException {
      return const CatalogUpdateResult(
        updated: false,
        message: 'No network. Try again when you are online.',
      );
    } on http.ClientException {
      return const CatalogUpdateResult(
        updated: false,
        message: 'Could not reach vitalog.cc. Try again later.',
      );
    } catch (_) {
      return const CatalogUpdateResult(
        updated: false,
        message: 'Update timed out. Try again.',
      );
    }

    if (manifestRes.statusCode != 200) {
      return CatalogUpdateResult(
        updated: false,
        message: 'Host returned ${manifestRes.statusCode}. Try again later.',
      );
    }

    late final Map<String, dynamic> manifest;
    try {
      final decoded = jsonDecode(manifestRes.body);
      if (decoded is! Map) {
        throw const FormatException('manifest not an object');
      }
      manifest = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return const CatalogUpdateResult(
        updated: false,
        message: 'Hosted catalogue looked invalid. Nothing changed.',
      );
    }

    final remoteVersion = manifest['version']?.toString();
    final remoteSha = (manifest['sha256'] as String?)?.toLowerCase();
    final remoteUpdated = manifest['updated'] as String?;
    if (remoteVersion == null ||
        remoteVersion.isEmpty ||
        remoteSha == null ||
        remoteSha.length < 32) {
      return const CatalogUpdateResult(
        updated: false,
        message: 'Hosted catalogue looked invalid. Nothing changed.',
      );
    }

    if (compareVersion(remoteVersion, currentVersion) < 0) {
      return CatalogUpdateResult(
        updated: false,
        message:
            'Already on a newer catalogue (v$currentVersion). Host has v$remoteVersion.',
        version: currentVersion,
        parameterCount: parameterCount,
        panelCount: panelCount,
      );
    }

    if (compareVersion(remoteVersion, currentVersion) == 0 &&
        _source == 'downloaded') {
      return CatalogUpdateResult(
        updated: false,
        message:
            'Already up to date (v$currentVersion · $parameterCount parameters).',
        version: currentVersion,
        parameterCount: parameterCount,
        panelCount: panelCount,
      );
    }

    late final http.Response dbRes;
    try {
      dbRes = await http.get(Uri.parse(hostedDbUrl)).timeout(timeout);
    } on SocketException {
      return const CatalogUpdateResult(
        updated: false,
        message: 'No network. Try again when you are online.',
      );
    } on http.ClientException {
      return const CatalogUpdateResult(
        updated: false,
        message: 'Could not reach vitalog.cc. Try again later.',
      );
    } catch (_) {
      return const CatalogUpdateResult(
        updated: false,
        message: 'Update timed out. Try again.',
      );
    }

    if (dbRes.statusCode != 200) {
      return CatalogUpdateResult(
        updated: false,
        message: 'Host returned ${dbRes.statusCode}. Try again later.',
      );
    }

    final bytes = dbRes.bodyBytes;
    if (bytes.length < 100) {
      return const CatalogUpdateResult(
        updated: false,
        message: 'Hosted catalogue looked invalid. Nothing changed.',
      );
    }

    final digest = sha256.convert(bytes).toString();
    if (digest != remoteSha) {
      return const CatalogUpdateResult(
        updated: false,
        message: 'Hosted catalogue failed integrity check. Nothing changed.',
      );
    }

    final dir = await _docsDir();
    final temp = File(p.join(dir.path, 'catalog.download.db'));
    try {
      await temp.writeAsBytes(bytes, flush: true);
      final probe = await openDatabase(temp.path, readOnly: true);
      final probeVersion = await versionFromDb(probe);
      final counts = await countsFromDb(probe);
      await probe.close();
      if (probeVersion == null ||
          compareVersion(probeVersion, remoteVersion) != 0) {
        await temp.delete();
        return const CatalogUpdateResult(
          updated: false,
          message: 'Hosted catalogue looked invalid. Nothing changed.',
        );
      }
      if (counts.parameters == 0) {
        await temp.delete();
        return const CatalogUpdateResult(
          updated: false,
          message: 'Hosted catalogue was empty. Nothing changed.',
        );
      }

      if (beforeSwap != null) await beforeSwap();
      final cache = await cacheFile();
      await temp.copy(cache.path);
      await temp.delete();
      await _writeMeta(
        source: 'downloaded',
        version: probeVersion,
        updated: remoteUpdated,
      );
      _parameterCount = counts.parameters;
      _panelCount = counts.panels;
      if (afterSwap != null) await afterSwap();

      return CatalogUpdateResult(
        updated: true,
        message:
            'Catalogue updated to v$probeVersion · ${counts.parameters} parameters · ${counts.panels} panels.',
        version: probeVersion,
        parameterCount: counts.parameters,
        panelCount: counts.panels,
      );
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      return const CatalogUpdateResult(
        updated: false,
        message: 'Could not save the catalogue on this device.',
      );
    }
  }
}
