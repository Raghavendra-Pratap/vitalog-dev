import 'dart:io';

import 'package:bodyline/updates/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release version matches pubspec', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((row) => row.startsWith('version:'));
    final version = line.split(RegExp(r'\s+')).last.split('+').first;
    expect(version, vitalogReleaseVersion);
  });

  test('a newer release points at the installer for this system', () {
    const body = '{'
        '"tag_name":"v0.2.9",'
        '"assets":['
        '{"name":"Vitalog-0.2.9.dmg","browser_download_url":"https://example.test/Vitalog.dmg"},'
        '{"name":"Vitalog-0.2.7-setup.exe","browser_download_url":"https://example.test/setup.exe"},'
        '{"name":"Vitalog-0.2.9.deb","browser_download_url":"https://example.test/vitalog.deb"}'
        ']}';
    final mac = interpretRelease(
      current: '0.2.6',
      platform: 'macos',
      statusCode: 200,
      body: body,
    );
    expect(mac.hasUpdate, isTrue);
    expect(mac.download.toString(), 'https://example.test/Vitalog.dmg');
    expect(mac.message, contains('unsigned'));

    final win = interpretRelease(
      current: '0.2.6',
      platform: 'windows',
      statusCode: 200,
      body: body,
    );
    expect(win.download.toString(), endsWith('setup.exe'));

    final linux = interpretRelease(
      current: '0.2.6',
      platform: 'linux',
      statusCode: 200,
      body: body,
    );
    expect(linux.download.toString(), endsWith('.deb'));
  });

  test('the same version is not an update', () {
    const body = '{"tag_name":"v0.2.6","assets":[]}';
    final status = interpretRelease(
      current: '0.2.6',
      platform: 'macos',
      statusCode: 200,
      body: body,
    );
    expect(status.hasUpdate, isFalse);
    expect(status.message, contains('No newer release'));
  });

  test('a missing installer is named', () {
    const body = '{"tag_name":"v0.3.0","assets":[]}';
    final status = interpretRelease(
      current: '0.2.6',
      platform: 'windows',
      statusCode: 200,
      body: body,
    );
    expect(status.hasUpdate, isFalse);
    expect(status.newer, '0.3.0');
    expect(status.message, contains('not on that release'));
  });

  test('no release yet stays on this copy', () {
    final status = interpretRelease(
      current: '0.2.6',
      platform: 'linux',
      statusCode: 404,
      body: '',
    );
    expect(status.hasUpdate, isFalse);
    expect(status.message, contains('0.2.6'));
  });
}
