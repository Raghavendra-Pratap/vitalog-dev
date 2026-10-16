import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Offline name suggestions for medicines / remedies.
/// Not advice, not interactions, not a formulary claim.
class DrugSuggestion {
  const DrugSuggestion({
    required this.name,
    required this.kind,
    required this.aliases,
    this.saltName,
  });

  /// Text filled into the name field (salt in Salt mode, brand in Brand mode).
  final String name;
  final String kind;
  final List<String> aliases;
  /// When [name] is a brand alias, the salt/generic it belongs to.
  final String? saltName;
}

/// Result of [DrugIndex.updateFromHost].
class MedicineLibraryUpdateResult {
  const MedicineLibraryUpdateResult({
    required this.updated,
    required this.message,
    this.version,
    this.itemCount,
  });

  final bool updated;
  final String message;
  final int? version;
  final int? itemCount;
}

class DrugIndex {
  DrugIndex._();
  static final DrugIndex instance = DrugIndex._();

  /// Hosted replaceable library (ADR-001 catalogue hosting).
  static const hostedUrl =
      'https://vitalog.cc/catalog/medicine-library.json';

  static const _assetPath = 'assets/catalog/drugs.json';
  static const _cacheFileName = 'medicine_library.json';

  List<DrugSuggestion>? _all;
  int _version = 0;
  String? _updated;
  String _source = 'bundled'; // bundled | downloaded
  int _bundledVersion = 0;

  int get version => _version;
  String? get updated => _updated;
  String get source => _source;
  int get itemCount => _all?.length ?? 0;

  /// One-line status for Settings.
  Future<String> statusLine() async {
    await ensureLoaded();
    final date = (_updated != null && _updated!.isNotEmpty)
        ? ' · $_updated'
        : '';
    final src = _source == 'downloaded' ? 'hosted' : 'in app';
    return 'v$_version · $itemCount names$date · $src';
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _cacheFileName));
  }

  ({int version, String? updated, List<DrugSuggestion> items}) _parse(
    String raw,
  ) {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return (
        version: 1,
        updated: null,
        items: _parseItems(decoded),
      );
    }
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final itemsRaw = map['items'] ?? map['drugs'];
      if (itemsRaw is! List) {
        throw const FormatException('Medicine library missing items');
      }
      return (
        version: (map['version'] as num?)?.toInt() ?? 1,
        updated: map['updated'] as String?,
        items: _parseItems(itemsRaw),
      );
    }
    throw const FormatException('Invalid medicine library');
  }

  List<DrugSuggestion> _parseItems(List<dynamic> list) {
    return [
      for (final e in list)
        if (e is Map)
          DrugSuggestion(
            name: e['name'] as String,
            kind: e['kind'] as String? ?? 'other',
            aliases: ((e['aliases'] as String?) ?? '')
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
          ),
    ];
  }

  void _apply({
    required int version,
    required String? updated,
    required List<DrugSuggestion> items,
    required String source,
  }) {
    _version = version;
    _updated = updated;
    _all = items;
    _source = source;
  }

  Future<List<DrugSuggestion>> ensureLoaded() async {
    if (_all != null) return _all!;

    // Always read bundled seed (ships in the binary).
    try {
      final bundledRaw = await rootBundle.loadString(_assetPath);
      final bundled = _parse(bundledRaw);
      _bundledVersion = bundled.version;
      _apply(
        version: bundled.version,
        updated: bundled.updated,
        items: bundled.items,
        source: 'bundled',
      );
    } catch (_) {
      _bundledVersion = 0;
      _apply(version: 0, updated: null, items: const [], source: 'bundled');
    }

    // Prefer a newer cached download when present.
    try {
      final file = await _cacheFile();
      if (await file.exists()) {
        final cached = _parse(await file.readAsString());
        if (cached.items.isNotEmpty &&
            cached.version >= _bundledVersion) {
          _apply(
            version: cached.version,
            updated: cached.updated,
            items: cached.items,
            source: 'downloaded',
          );
        }
      }
    } catch (_) {
      // Keep bundled.
    }

    return _all!;
  }

  /// Clear in-memory cache so the next [ensureLoaded] re-reads disk/asset.
  void invalidate() {
    _all = null;
  }

  /// Fetch hosted library, replace local cache if newer.
  Future<MedicineLibraryUpdateResult> updateFromHost({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await ensureLoaded();
    late final http.Response res;
    try {
      res = await http.get(Uri.parse(hostedUrl)).timeout(timeout);
    } on SocketException {
      return const MedicineLibraryUpdateResult(
        updated: false,
        message: 'No network. Try again when you are online.',
      );
    } on http.ClientException {
      return const MedicineLibraryUpdateResult(
        updated: false,
        message: 'Could not reach vitalog.cc. Try again later.',
      );
    } catch (_) {
      return const MedicineLibraryUpdateResult(
        updated: false,
        message: 'Update timed out. Try again.',
      );
    }

    if (res.statusCode != 200) {
      return MedicineLibraryUpdateResult(
        updated: false,
        message: 'Host returned ${res.statusCode}. Try again later.',
      );
    }

    late final ({int version, String? updated, List<DrugSuggestion> items})
        remote;
    try {
      remote = _parse(res.body);
    } catch (_) {
      return const MedicineLibraryUpdateResult(
        updated: false,
        message: 'Hosted library looked invalid. Nothing changed.',
      );
    }

    if (remote.items.isEmpty) {
      return const MedicineLibraryUpdateResult(
        updated: false,
        message: 'Hosted library was empty. Nothing changed.',
      );
    }

    if (remote.version < _version) {
      return MedicineLibraryUpdateResult(
        updated: false,
        message:
            'Already on a newer library (v$_version). Host has v${remote.version}.',
        version: _version,
        itemCount: itemCount,
      );
    }

    if (remote.version == _version &&
        remote.items.length == itemCount &&
        _source == 'downloaded') {
      return MedicineLibraryUpdateResult(
        updated: false,
        message: 'Already up to date (v$_version · $itemCount names).',
        version: _version,
        itemCount: itemCount,
      );
    }

    try {
      final file = await _cacheFile();
      await file.writeAsString(res.body);
    } catch (_) {
      return const MedicineLibraryUpdateResult(
        updated: false,
        message: 'Could not save the library on this device.',
      );
    }

    _apply(
      version: remote.version,
      updated: remote.updated,
      items: remote.items,
      source: 'downloaded',
    );

    return MedicineLibraryUpdateResult(
      updated: true,
      message:
          'Medicine library updated to v${remote.version} · ${remote.items.length} names.',
      version: remote.version,
      itemCount: remote.items.length,
    );
  }

  Future<List<DrugSuggestion>> search(
    String query, {
    int limit = 12,
    bool preferBrand = false,
    String? preferredKind,
  }) async {
    final all = await ensureLoaded();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final kind = preferredKind?.trim();
    final scored = <(int, DrugSuggestion)>[];

    int kindBoost(String k) {
      if (kind == null || kind.isEmpty || kind == 'other') return 0;
      return k == kind ? 40 : -25;
    }

    if (preferBrand) {
      // Brand mode: only alias / brand hits. Fill the brand name.
      for (final d in all) {
        for (final a in d.aliases) {
          final al = a.toLowerCase();
          var score = 0;
          if (al == q) {
            score = 110;
          } else if (al.startsWith(q)) {
            score = 90;
          } else if (al.contains(q)) {
            score = 70;
          }
          if (score > 0) {
            score += kindBoost(d.kind);
            if (score > 0) {
              scored.add((
                score,
                DrugSuggestion(
                  name: a,
                  kind: d.kind,
                  aliases: d.aliases,
                  saltName: d.name,
                ),
              ));
            }
          }
        }
      }
    } else {
      // Salt / remedy name mode.
      for (final d in all) {
        final name = d.name.toLowerCase();
        var score = 0;
        if (name == q) {
          score = 100;
        } else if (name.startsWith(q)) {
          score = 80;
        } else if (name.contains(q)) {
          score = 50;
        }
        if (score > 0) {
          score += kindBoost(d.kind);
          if (score > 0) scored.add((score, d));
        }
      }
    }

    scored.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      if (c != 0) return c;
      return a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
    });
    return [for (final s in scored.take(limit)) s.$2];
  }
}
