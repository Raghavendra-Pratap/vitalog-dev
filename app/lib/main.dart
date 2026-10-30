import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'data/local_store.dart';
import 'data/models.dart';
import 'desktop.dart';
import 'features/lock/lock_gate.dart';
import 'features/profiles/onboarding_screen.dart';
import 'features/shell/app_shell.dart';
import 'security/app_lock.dart';
import 'sync/lan_sync_service.dart';
import 'sync/pair_link.dart';
import 'features/sync/sync_screen.dart';
import 'features/medicines/dose_wait_controller.dart';
import 'notifications/reminder_notifications.dart';
import 'theme/theme_controller.dart';
import 'theme/tokens.dart';
import 'theme/scroll_behavior.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDesktopWindow();

  final store = LocalStore();
  await store.open();
  final lock = AppLockController();
  await lock.load();
  final theme = ThemeController();
  await theme.load();
  final sync = LanSyncService(store);
  await sync.init();
  await ReminderNotifications.instance.init();
  ReminderNotifications.instance.onDoseAction =
      (action, medicationId, timeHm) async {
    try {
      final parts = timeHm.split(':');
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      final now = DateTime.now();
      final scheduled = DateTime(now.year, now.month, now.day, h, m);
      final actor = store.activeProfileId;
      if (action == 'taken') {
        await store.logMedicationTaken(
          medicationId: medicationId,
          scheduledFor: scheduled,
          actedByProfileId: actor,
        );
      } else if (action == 'skip') {
        await store.logMedicationSkipped(
          medicationId: medicationId,
          scheduledFor: scheduled,
          actedByProfileId: actor,
        );
      } else if (action == 'snooze15') {
        String title = 'Time for medicine';
        for (final s in await store.listAllMedicationSchedules()) {
          if (s.medicationId == medicationId) {
            title = 'Time for ${s.medicationName}';
            break;
          }
        }
        await ReminderNotifications.instance.snoozeDoseInMinutes(
          medicationId: medicationId,
          timeHm: timeHm,
          title: title,
          body: 'Snoozed 15 minutes · mark taken in Vitalog when done',
        );
      }
    } catch (_) {}
  };
  await DoseWaitController.instance.load();
  try {
    final all = <ReminderRecord>[];
    for (final profile in store.profiles) {
      all.addAll(await store.rollForwardRecurring(profile.id));
    }
    final doses = await store.listAllMedicationSchedules();
    final habits = await store.listAllHabits();
    final needsAlerts = all.isNotEmpty || doses.isNotEmpty || habits.any((h) {
      return ((h['reminder_enabled'] as int?) ?? 0) == 1;
    });
    if (needsAlerts) {
      await ReminderNotifications.instance.ensurePermission();
    }
    await ReminderNotifications.instance.rescheduleAll(all);
    await ReminderNotifications.instance.rescheduleAllDoses(doses);
    await ReminderNotifications.instance.rescheduleAllHabits(habits);
  } catch (e, st) {
    debugPrint('Vitalog: failed to reschedule alerts: $e\n$st');
  }
  runApp(BodylineApp(store: store, lock: lock, theme: theme, sync: sync));
}

class BodylineApp extends StatefulWidget {
  const BodylineApp({
    super.key,
    required this.store,
    required this.lock,
    required this.theme,
    required this.sync,
  });

  final LocalStore store;
  final AppLockController lock;
  final ThemeController theme;
  final LanSyncService sync;

  @override
  State<BodylineApp> createState() => _BodylineAppState();
}

class _BodylineAppState extends State<BodylineApp> with WidgetsBindingObserver {
  final _navKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _linkSub;

  void _refresh() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.theme.addListener(_refresh);
    WidgetsBinding.instance.addObserver(this);
    widget.sync.startAutoSync();
    _listenPairLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(nudgeWindowsSurface());
    });
  }

  Future<void> _listenPairLinks() async {
    final links = AppLinks();
    try {
      final initial = await links.getInitialLink();
      if (initial != null) _onPairUri(initial);
    } catch (_) {}
    _linkSub = links.uriLinkStream.listen(_onPairUri, onError: (_) {});
  }

  void _onPairUri(Uri uri) {
    final host = PairDeepLinks.parseHost(uri.toString());
    if (host == null) return;
    PairDeepLinks.pendingHost.value = host;
    // Open Devices & sync with host filled (after frame so navigator is ready).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = _navKey.currentState;
      if (nav == null) return;
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => SyncScreen(
            sync: widget.sync,
            initialHost: host,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.theme.removeListener(_refresh);
    widget.sync.stopAutoSync();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.sync.syncQuietly();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    // Bake both ThemeData objects, then re-sync BodylineColors to the mode we
    // will actually show (bodylineTheme mutates static tokens as a side effect).
    final lightTheme = bodylineTheme(Brightness.light);
    final darkTheme = bodylineTheme(Brightness.dark);
    final mode = widget.theme.mode;
    final platform =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final active = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platform,
    };
    BodylineColors.applyBrightness(active);

    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Vitalog',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const BodylineScrollBehavior(),
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: mode,
      builder: (context, child) {
        BodylineColors.applyBrightness(Theme.of(context).brightness);
        return LockGate(
          lock: widget.lock,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: store.profiles.isEmpty
          ? OnboardingScreen(store: store, onDone: _refresh)
          : AppShell(
              store: store,
              lock: widget.lock,
              theme: widget.theme,
              sync: widget.sync,
            ),
    );
  }
}
