import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// This build, without the +number. Keep this equal to `pubspec.yaml`.
const vitalogReleaseVersion = '0.2.8';

const vitalogReleasesUrl =
    'https://api.github.com/repos/Raghavendra-Pratap/vitalog-pub/releases/latest';

class AppUpdateStatus {
  const AppUpdateStatus({
    required this.current,
    required this.message,
    this.newer,
    this.download,
  });

  final String current;
  final String? newer;
  final Uri? download;
  final String message;

  bool get hasUpdate => download != null;
}

/// What Settings should show for one GitHub release response.
AppUpdateStatus interpretRelease({
  required String current,
  required String platform,
  required int statusCode,
  required String body,
}) {
  if (statusCode == 404) {
    return AppUpdateStatus(
      current: current,
      message: 'This copy is $current. No newer release is published.',
    );
  }
  if (statusCode != 200) {
    return AppUpdateStatus(
      current: current,
      message: 'Could not read the release list. Try again.',
    );
  }
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    return const AppUpdateStatus(
      current: vitalogReleaseVersion,
      message: 'Could not read the release list. Try again.',
    );
  }
  final tag = decoded['tag_name'];
  final latest = tag is String ? tag.replaceFirst(RegExp(r'^v'), '') : '';
  if (!_isNewer(latest, current)) {
    return AppUpdateStatus(
      current: current,
      message: 'This copy is $current. No newer release is published.',
    );
  }
  final assets = decoded['assets'];
  final href = assets is List ? assetUrlFor(assets, platform) : null;
  if (href == null) {
    return AppUpdateStatus(
      current: current,
      newer: latest,
      message:
          '$latest is published. The installer for this system is not on that release.',
    );
  }
  return AppUpdateStatus(
    current: current,
    newer: latest,
    download: Uri.parse(href),
    message:
        '$latest is available. The download is unsigned, so the system will ask before it installs.',
  );
}

String? assetUrlFor(List<dynamic> assets, String platform) {
  for (final asset in assets) {
    if (asset is! Map) continue;
    final name = asset['name'];
    final href = asset['browser_download_url'];
    if (name is! String || href is! String) continue;
    final lower = name.toLowerCase();
    final match = switch (platform) {
      'macos' => lower.endsWith('.dmg'),
      'windows' => lower.endsWith('-setup.exe'),
      'linux' => lower.endsWith('.deb'),
      _ => false,
    };
    if (match) return href;
  }
  return null;
}

bool _isNewer(String latest, String current) {
  final next = versionParts(latest);
  final here = versionParts(current);
  if (next == null || here == null) return false;
  for (var i = 0; i < 3; i++) {
    if (next[i] > here[i]) return true;
    if (next[i] < here[i]) return false;
  }
  return false;
}

List<int>? versionParts(String version) {
  final core = version.split('+').first.split('-').first;
  final bits = core.split('.');
  if (bits.length < 2) return null;
  final nums = <int>[];
  for (final bit in bits.take(3)) {
    final n = int.tryParse(bit);
    if (n == null) return null;
    nums.add(n);
  }
  while (nums.length < 3) {
    nums.add(0);
  }
  return nums;
}

String desktopPlatform() {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return 'other';
}

Future<AppUpdateStatus> checkAppUpdate({http.Client? client}) async {
  final httpClient = client ?? http.Client();
  final close = client == null;
  try {
    final response = await httpClient.get(
      Uri.parse(vitalogReleasesUrl),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Vitalog',
      },
    ).timeout(const Duration(seconds: 20));
    return interpretRelease(
      current: vitalogReleaseVersion,
      platform: desktopPlatform(),
      statusCode: response.statusCode,
      body: response.body,
    );
  } catch (_) {
    return const AppUpdateStatus(
      current: vitalogReleaseVersion,
      message: 'Could not reach GitHub. Try again.',
    );
  } finally {
    if (close) httpClient.close();
  }
}
