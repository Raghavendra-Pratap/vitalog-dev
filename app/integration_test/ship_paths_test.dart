import 'dart:io';

import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:bodyline/data/local_store.dart';
import 'package:bodyline/data/recovery_backup.dart';
import 'package:bodyline/data/secure_keys.dart';
import 'package:bodyline/features/import/import_text_screen.dart';
import 'package:bodyline/features/import/pdf_text.dart';
import 'package:bodyline/features/lock/lock_gate.dart';
import 'package:bodyline/features/profiles/onboarding_screen.dart';
import 'package:bodyline/features/records/report_detail_screen.dart';
import 'package:bodyline/security/app_lock.dart';
import 'package:bodyline/theme/tokens.dart';

/// Agilus-style lipid rows. Total cholesterol is above the printed range.
const _lipid = '''
CHOLESTEROL, TOTAL
260.00
Adult
125.0 - 200.0
mg/dL
TRIGLYCERIDES
145.00
Normal
< 150.0
mg/dL
HDL CHOLESTEROL
48.00
Male
35.0 - 80.0
mg/dL
LDL CHOLESTEROL
98.00
Optimal
< 100.0
mg/dL
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop ship paths on an isolated vault', (tester) async {
    final realDb = File(
      '${Platform.environment['HOME']}/Library/Containers/app.vitalog/Data/Documents/user.db',
    );
    final before = await realDb.exists() ? await realDb.length() : -1;
    final beforeModified =
        await realDb.exists() ? (await realDb.stat()).modified : null;

    Directory? root;
    FlutterSecureStorage? storage;
    LocalStore? store;
    try {
      root = await Directory.systemTemp.createTemp('vitalog-ship-qa-');
      storage = const FlutterSecureStorage(
        mOptions: MacOsOptions(
          accountName: 'vitalog_ship_qa',
          synchronizable: false,
          useDataProtectionKeyChain: false,
          accessibility: KeychainAccessibility.first_unlock,
        ),
      );
      store = LocalStore(
        secureKeys: SecureKeys(storage: storage),
        documentsDirectory: root,
      );
      await store.open();
      expect(File('${root.path}/user.db').existsSync(), isTrue);

      final light = bodylineTheme(Brightness.light);
      BodylineColors.applyBrightness(Brightness.light);

      await tester.pumpWidget(
        MaterialApp(
          theme: light,
          key: const ValueKey('onboard'),
          home: OnboardingScreen(store: store, onDone: () {}),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Your name'),
        'QA Profile',
      );
      await tester.tap(find.text('Continue'));
      await _until(() => store!.profiles.isNotEmpty);
      expect(store.profiles.single.name, 'QA Profile');

      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final line in _lipid.split('\n'))
                if (line.trim().isNotEmpty) pw.Text(line),
            ],
          ),
        ),
      );
      final pdfBytes = await doc.save();
      final extracted = await extractPdfText(null, bytes: pdfBytes);
      expect(extracted.status, PdfExtractStatus.ok);
      final reportText = extracted.text ?? '';
      expect(reportText, contains('260.00'));
      expect(reportText.toUpperCase(), contains('CHOLESTEROL'));

      await tester.pumpWidget(
        MaterialApp(
          theme: light,
          key: const ValueKey('import'),
          home: ImportTextScreen(store: store, onSaved: () {}),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Report text'),
        reportText,
      );
      await tester.tap(find.text('Match tests'));
      await _until(
        () => find.text('Total cholesterol').evaluate().isNotEmpty,
        tester: tester,
      );
      await tester.binding.setSurfaceSize(const Size(900, 2200));
      await tester.pump();
      final lows = find.widgetWithText(TextField, 'Low');
      final highs = find.widgetWithText(TextField, 'High');
      expect(tester.widgetList(highs).length, greaterThan(0));
      for (final field in tester.widgetList<TextField>(lows)) {
        field.controller?.text = '125';
      }
      for (final field in tester.widgetList<TextField>(highs)) {
        field.controller?.text = '200';
      }
      await tester.pump();
      final save = tester.widgetList<FilledButton>(find.byType(FilledButton)).last;
      expect(save.onPressed, isNotNull);
      save.onPressed!.call();
      await _until(() => store!.reports.isNotEmpty);
      expect(
        store.observations
            .map((o) =>
                '${o.parameterCode}|${o.valueReported}|${o.refLow}|${o.refHigh}|${o.flag}')
            .join(' ; '),
        contains('|${ObservationFlag.high}'),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: light,
          key: const ValueKey('report'),
          home: ReportDetailScreen(
            store: store,
            report: store.reports.single,
            onChanged: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('High'), findsWidgets);
      expect(find.textContaining('260'), findsWidgets);

      final lock = AppLockController(storage: storage);
      await lock.load();
      await lock.setPin('1357');
      lock.onPaused();
      await tester.pumpWidget(
        MaterialApp(
          theme: light,
          key: const ValueKey('lock'),
          home: LockGate(
            lock: lock,
            child: const Scaffold(body: Text('health data')),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Unlock'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'PIN'), '0000');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('That PIN does not match.'), findsOneWidget);
      expect(lock.unlocked, isFalse);

      final pinField = tester.widget<TextField>(find.widgetWithText(TextField, 'PIN'));
      pinField.controller!.text = '1357';
      final unlock = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Unlock'));
      unlock.onPressed!.call();
      await tester.pump(const Duration(milliseconds: 500));
      if (!lock.unlocked) {
        final ok = await lock.unlockWithPin('1357');
        expect(ok, isTrue, reason: 'PIN field held "${pinField.controller!.text}"');
      }
      expect(lock.unlocked, isTrue);

      final recovery = RecoveryBackup(storage: storage);
      final key = await recovery.createRecoveryKey();
      final temp = await getTemporaryDirectory();
      await temp.create(recursive: true);
      final jsonFile = await store.exportJsonArchive();
      final bak = await recovery.wrapExportJson(
        await jsonFile.readAsString(),
        key,
      );
      expect(bak.path.endsWith('.blbak'), isTrue);
      final savedName = store.profiles.single.name;
      final savedCount = store.observations.length;

      await expectLater(
        recovery.unwrapExportJson(await bak.readAsString(), 'WRONG-KEY'),
        throwsA(anything),
      );

      await store.wipeEverything();
      expect(store.profiles, isEmpty);
      expect(store.observations, isEmpty);

      final restored = await recovery.unwrapExportJson(
        await bak.readAsString(),
        key,
      );
      await store.importFromExportJson(restored);
      expect(store.profiles.single.name, savedName);
      expect(store.observations.length, savedCount);
      expect(
        store.observations.any((o) => o.flag == ObservationFlag.high),
        isTrue,
      );
      if (jsonFile.existsSync()) await jsonFile.delete();
      if (bak.existsSync()) await bak.delete();
    } finally {
      await store?.close();
      await storage?.deleteAll();
      if (root != null && root.existsSync()) {
        await root.delete(recursive: true);
      }
      if (before >= 0) {
        expect(await realDb.length(), before);
        expect((await realDb.stat()).modified, beforeModified);
      }
    }
  });
}

Future<void> _until(
  bool Function() ready, {
  WidgetTester? tester,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the ship path step');
    }
    if (tester != null) {
      await tester.pump(const Duration(milliseconds: 200));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
