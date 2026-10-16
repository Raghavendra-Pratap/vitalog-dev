import 'dart:convert';
import 'dart:io';

import 'package:bodyline_core/bodyline_core.dart';

void main(List<String> args) {
  final corpus = args.isNotEmpty
      ? args[0]
      : '${Directory.current.path}/../extraction-corpus';
  final root = Directory(corpus);
  final snap =
      jsonDecode(File('${root.path}/catalog_snapshot.json').readAsStringSync())
          as Map<String, dynamic>;
  final catalog = _catalogFromSnap(snap);
  final wbDir = Directory('${root.path}/wordboxes');
  if (!wbDir.existsSync()) {
    stderr.writeln('missing wordboxes/');
    exit(1);
  }
  for (final f in wbDir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.wordboxes.json')) continue;
    final id = f.uri.pathSegments.last.split('.').first;
    final raw = jsonDecode(f.readAsStringSync()) as List<dynamic>;
    final boxes = [
      for (final e in raw)
        WordBox.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
    final result = runExtractionPipeline(boxes, catalog);
    final out = scoredToExtractionJson(result.scored);
    File('${root.path}/extracted/$id.extracted.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
    stdout.writeln(
      '$id scored=${result.scored.length} '
      'auto=${result.scored.where((s) => s.outcome == ExtractionOutcome.autoAccept).length}',
    );
  }
}

MatchCatalog _catalogFromSnap(Map<String, dynamic> snap) {
  final aliasRaw = Map<String, dynamic>.from(snap['aliasToCodes'] as Map);
  final aliasToCodes = <String, List<String>>{
    for (final e in aliasRaw.entries)
      e.key: [for (final c in (e.value as List)) c.toString()],
  };
  final names = Map<String, String>.from(
    (snap['paramNames'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
  );
  final units = Map<String, String>.from(
    (snap['paramUnits'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
  );
  final limits = <String, (double, double, String)>{};
  final limRaw = Map<String, dynamic>.from(snap['physicalLimits'] as Map);
  for (final e in limRaw.entries) {
    final list = e.value as List;
    limits[e.key] = (
      (list[0] as num).toDouble(),
      (list[1] as num).toDouble(),
      list[2].toString(),
    );
  }
  final unitAliases = Map<String, String>.from(
    (snap['unitAliases'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
  );
  return MatchCatalog(
    aliasToCodes: aliasToCodes,
    paramNames: names,
    paramUnits: units,
    physicalLimits: limits,
    unitAliases: unitAliases,
  );
}
