import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models.dart';

/// Local OS alerts for care reminders (no Vitalog servers).
class ReminderNotifications {
  ReminderNotifications._();
  static final ReminderNotifications instance = ReminderNotifications._();

  /// payload: dose|medId|HH:mm · actionId: taken | snooze15 | skip
  void Function(String actionId, String medicationId, String timeHm)? onDoseAction;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  var _ready = false;

  static const _channelId = 'vitalog_reminders';
  static const _channelName = 'Reminders';
  static const _channelDesc = 'Care reminders and medicine dose times you set.';

  static const _doseChannelId = 'vitalog_doses';
  static const _habitChannelId = 'vitalog_habits';
  static const _habitChannelName = 'Habits';
  static const _habitChannelDesc = 'Daily habit check-in reminders you set.';
  static const _doseChannelName = 'Medicine doses';
  static const _doseChannelDesc = 'Daily reminders to take medicines and remedies.';

  static const _waitChannelId = 'vitalog_dose_wait';
  static const _waitChannelName = 'Dose wait timers';
  static const _waitChannelDesc =
      'Countdown after a dose — when your wait ends (not medical advice).';
  static const doseWaitNotificationId = 710042;

  Future<void> init() async {
    if (kIsWeb) return;
    await _configureLocalTimezone();

    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );
    const androidInitWithActions = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(
        android: androidInitWithActions,
        iOS: darwinInit,
        macOS: darwinInit,
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _doseChannelId,
          _doseChannelName,
          description: _doseChannelDesc,
          importance: Importance.high,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _habitChannelId,
          _habitChannelName,
          description: _habitChannelDesc,
          importance: Importance.defaultImportance,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _waitChannelId,
          _waitChannelName,
          description: _waitChannelDesc,
          importance: Importance.high,
        ),
      );
    }
    _ready = true;
  }

  Future<void> _configureLocalTimezone() async {
    tzdata.initializeTimeZones();
    String? name;
    try {
      name = await FlutterTimezone.getLocalTimezone();
    } catch (e) {
      debugPrint('Vitalog: FlutterTimezone failed: $e');
    }
    if (name != null && name.isNotEmpty) {
      for (final candidate in <String>{
        name,
        name.replaceAll(' ', '_'),
        if (name == 'Asia/Calcutta') 'Asia/Kolkata',
        if (name == 'Asia/Katmandu') 'Asia/Kathmandu',
      }) {
        try {
          tz.setLocalLocation(tz.getLocation(candidate));
          return;
        } catch (_) {}
      }
      debugPrint('Vitalog: unknown timezone "$name", using device offset');
    }
    // Native schedulers need a real IANA name — map common offsets when lookup fails.
    final minutes = DateTime.now().timeZoneOffset.inMinutes;
    const byOffset = <int, String>{
      0: 'UTC',
      330: 'Asia/Kolkata',
      345: 'Asia/Kathmandu',
      360: 'Asia/Dhaka',
      480: 'Asia/Shanghai',
      540: 'Asia/Tokyo',
      -300: 'America/New_York',
      -360: 'America/Chicago',
      -420: 'America/Denver',
      -480: 'America/Los_Angeles',
      60: 'Europe/Berlin',
      120: 'Europe/Helsinki',
    };
    final mapped = byOffset[minutes];
    if (mapped != null) {
      try {
        tz.setLocalLocation(tz.getLocation(mapped));
        return;
      } catch (_) {}
    }
    try {
      final hours = minutes ~/ 60;
      if (minutes % 60 == 0 && hours != 0) {
        final etcSign = minutes >= 0 ? '-' : '+';
        tz.setLocalLocation(tz.getLocation('Etc/GMT$etcSign${hours.abs()}'));
        return;
      }
    } catch (_) {}
    debugPrint('Vitalog: no IANA match for offset ${minutes}m — UTC (dose times may drift)');
    tz.setLocalLocation(tz.UTC);
  }

  void _onResponse(NotificationResponse response) {
    final action = response.actionId;
    final payload = response.payload;
    if (action == null || payload == null || !payload.startsWith('dose|')) {
      return;
    }
    final parts = payload.split('|');
    if (parts.length < 3) return;
    onDoseAction?.call(action, parts[1], parts[2]);
  }

  /// Ask for notification permission when the user creates a reminder.
  Future<bool> ensurePermission() async {
    if (!_ready || kIsWeb) return false;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      try {
        await android?.requestExactAlarmsPermission();
      } catch (_) {}
      if (granted == true) return true;
      return await android?.areNotificationsEnabled() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (granted == true) return true;
      return await notificationsEnabled();
    }
    if (Platform.isMacOS) {
      final mac = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      final granted = await mac?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (granted == true) return true;
      // After Deny, macOS will not show the prompt again — Settings required.
      return await notificationsEnabled();
    }
    return true;
  }

  /// Whether OS alerts are currently allowed (does not prompt).
  Future<bool> notificationsEnabled() async {
    if (!_ready || kIsWeb) return false;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final opts = await ios?.checkPermissions();
      return (opts?.isEnabled ?? false) || (opts?.isProvisionalEnabled ?? false);
    }
    if (Platform.isMacOS) {
      final mac = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      final opts = await mac?.checkPermissions();
      return (opts?.isEnabled ?? false) || (opts?.isProvisionalEnabled ?? false);
    }
    return true;
  }

  /// Opens the OS screen where Vitalog notification permission can be turned on.
  Future<void> openSystemNotificationSettings() async {
    if (kIsWeb) return;
    try {
      if (Platform.isMacOS) {
        final r = await Process.run('open', [
          'x-apple.systempreferences:com.apple.Notifications-Settings.extension',
        ]);
        if (r.exitCode != 0) {
          await Process.run('open', [
            '/System/Library/PreferencePanes/Notifications.prefPane',
          ]);
        }
        return;
      }
      if (Platform.isIOS) {
        final uri = Uri.parse('app-settings:');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
        return;
      }
      if (Platform.isAndroid) {
        const channel = MethodChannel('vitalog/settings');
        await channel.invokeMethod<void>('openNotificationSettings');
      }
    } catch (e) {
      debugPrint('Vitalog: open notification settings failed: $e');
    }
  }

  int _id(String reminderId, String kind) =>
      Object.hash(reminderId, kind) & 0x7fffffff;

  /// Fire at 09:00 local on the due date when the stored time is midnight.
  tz.TZDateTime _fireAt(DateTime dueAt) {
    var local = DateTime(dueAt.year, dueAt.month, dueAt.day, dueAt.hour, dueAt.minute);
    if (dueAt.hour == 0 && dueAt.minute == 0) {
      local = DateTime(dueAt.year, dueAt.month, dueAt.day, 9, 0);
    }
    return tz.TZDateTime.from(local, tz.local);
  }

  Future<void> scheduleReminder(ReminderRecord r, {int leadMinutes = 1440}) async {
    if (!_ready || kIsWeb) return;
    await cancelReminder(r.id);
    final due = _fireAt(r.dueAt);
    final now = tz.TZDateTime.now(tz.local);
    final match = _matchForRrule(r.rrule);

    var when = due;
    if (!when.isAfter(now)) {
      if (match == DateTimeComponents.dayOfWeekAndTime) {
        when = when.add(const Duration(days: 7));
      } else if (match == DateTimeComponents.dayOfMonthAndTime) {
        when = when.add(const Duration(days: 32));
      } else {
        return;
      }
    }

    await _zoned(
      id: _id(r.id, 'due'),
      when: when,
      title: 'Vitalog reminder',
      body: r.title,
      payload: r.id,
      match: match,
    );

    // Lead alerts only for one-shot (repeating lead is noisy).
    if (leadMinutes > 0 && match == null) {
      final lead = due.subtract(Duration(minutes: leadMinutes));
      if (lead.isAfter(now)) {
        await _zoned(
          id: _id(r.id, 'lead'),
          when: lead,
          title: 'Coming up',
          body: r.title,
          payload: r.id,
        );
      }
    }
  }

  DateTimeComponents? _matchForRrule(String? rrule) {
    switch (rrule) {
      case 'FREQ=WEEKLY':
        return DateTimeComponents.dayOfWeekAndTime;
      case 'FREQ=MONTHLY':
        return DateTimeComponents.dayOfMonthAndTime;
      default:
        // INTERVAL 3/6 and YEARLY: one-shot next due; roll forward on Done / launch.
        return null;
    }
  }

  Future<AndroidScheduleMode> _scheduleMode() async {
    if (!Platform.isAndroid) return AndroidScheduleMode.exactAllowWhileIdle;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final allowed = await android?.canScheduleExactNotifications();
      if (allowed == true) return AndroidScheduleMode.exactAllowWhileIdle;
    } catch (_) {}
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  Future<void> _zoned({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
    required String payload,
    DateTimeComponents? match,
    String channelId = _channelId,
    String channelName = _channelName,
    String channelDesc = _channelDesc,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          macOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: await _scheduleMode(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: match,
        payload: payload,
      );
    } catch (e, st) {
      debugPrint('Vitalog: schedule failed id=$id when=$when: $e\n$st');
      rethrow;
    }
  }

  static const _testNotificationId = 710099;

  /// Immediate banner — verifies permission + channel wiring.
  Future<bool> showTestNow({
    String title = 'Vitalog test',
    String body = 'Alerts are working on this device.',
  }) async {
    if (!_ready || kIsWeb) return false;
    final ok = await ensurePermission();
    if (!ok && !(await notificationsEnabled())) return false;
    await _plugin.show(
      _testNotificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'test',
    );
    return true;
  }

  /// One-shot in [seconds] — verifies AlarmManager / UNCalendar trigger.
  Future<bool> scheduleTestIn({int seconds = 15}) async {
    if (!_ready || kIsWeb) return false;
    final ok = await ensurePermission();
    if (!ok && !(await notificationsEnabled())) return false;
    final when = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
    await _plugin.cancel(_testNotificationId);
    await _zoned(
      id: _testNotificationId,
      when: when,
      title: 'Vitalog test',
      body: 'Scheduled alert fired after $seconds seconds.',
      payload: 'test',
    );
    return true;
  }

  Future<int> pendingCount() async {
    if (!_ready || kIsWeb) return 0;
    final pending = await _plugin.pendingNotificationRequests();
    return pending.length;
  }

  Future<void> cancelReminder(String reminderId) async {
    if (!_ready || kIsWeb) return;
    await _plugin.cancel(_id(reminderId, 'due'));
    await _plugin.cancel(_id(reminderId, 'lead'));
  }

  Future<void> rescheduleAll(Iterable<ReminderRecord> reminders) async {
    if (!_ready || kIsWeb) return;
    for (final r in reminders) {
      await scheduleReminder(r);
    }
  }

  int _doseId(String medicationId, String timeHm) {
    return Object.hash('dose', medicationId, timeHm) & 0x7fffffff;
  }

  /// Daily repeating local alert at [timeHm] (HH:mm).
  Future<void> scheduleDailyDose({
    required String medicationId,
    required String timeHm,
    required String title,
    required String body,
  }) async {
    if (!_ready || kIsWeb) return;
    final parts = timeHm.split(':');
    if (parts.length < 2) return;
    final h = int.tryParse(parts[0]) ?? -1;
    final m = int.tryParse(parts[1]) ?? -1;
    if (h < 0 || m < 0) return;

    final id = _doseId(medicationId, timeHm);
    await _plugin.cancel(id);

    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }

    try {
      await _plugin.zonedSchedule(
            id,
            title,
            body,
            when,
            NotificationDetails(
              android: AndroidNotificationDetails(
                _doseChannelId,
                _doseChannelName,
                channelDescription: _doseChannelDesc,
                importance: Importance.high,
                priority: Priority.high,
                styleInformation: BigTextStyleInformation(body),
                actions: const <AndroidNotificationAction>[
                  AndroidNotificationAction('taken', 'Taken'),
                  AndroidNotificationAction('snooze15', 'In 15 min'),
                  AndroidNotificationAction('skip', 'Skip'),
                ],
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
              macOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            androidScheduleMode: await _scheduleMode(),
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.time,
            payload: 'dose|$medicationId|$timeHm',
          );
    } catch (e, st) {
      debugPrint('Vitalog: schedule failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> cancelDailyDose(String medicationId, String timeHm) async {
    if (!_ready || kIsWeb) return;
    await _plugin.cancel(_doseId(medicationId, timeHm));
  }

  Future<void> rescheduleAllDoses(
    Iterable<MedicationScheduleInfo> schedules,
  ) async {
    if (!_ready || kIsWeb) return;
    for (final s in schedules) {
      for (final hm in s.times) {
        final strength = (s.strength != null && s.strength!.isNotEmpty)
            ? ' · ${s.strength}'
            : '';
        await scheduleDailyDose(
          medicationId: s.medicationId,
          timeHm: hm,
          title: 'Time for ${s.medicationName}',
          body:
              '${medicationKindLabel(s.kind)}$strength · mark taken in Vitalog when done',
        );
      }
    }
  }


  /// One-shot local alert when a post-dose wait ends.
  Future<void> scheduleDoseWait({
    required DateTime endsAt,
    String title = 'Wait is over',
    String body = 'You can have your meal now — this is your timer, not medical advice.',
  }) async {
    if (!_ready || kIsWeb) return;
    await cancelDoseWait();
    final when = tz.TZDateTime.from(endsAt.toLocal(), tz.local);
    final now = tz.TZDateTime.now(tz.local);
    if (!when.isAfter(now)) return;

    try {
      await _plugin.zonedSchedule(
            doseWaitNotificationId,
            title,
            body,
            when,
            NotificationDetails(
              android: AndroidNotificationDetails(
                _waitChannelId,
                _waitChannelName,
                channelDescription: _waitChannelDesc,
                importance: Importance.high,
                priority: Priority.high,
                styleInformation: BigTextStyleInformation(body),
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
              macOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            androidScheduleMode: await _scheduleMode(),
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: 'dose_wait',
          );
    } catch (e, st) {
      debugPrint('Vitalog: schedule failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> cancelDoseWait() async {
    if (!_ready || kIsWeb) return;
    await _plugin.cancel(doseWaitNotificationId);
  }

  Future<void> snoozeDoseInMinutes({
    required String medicationId,
    required String timeHm,
    required String title,
    required String body,
    int minutes = 15,
  }) async {
    if (!_ready || kIsWeb) return;
    final id = (_doseId(medicationId, timeHm) ^ 0x4500) & 0x7fffffff;
    await _plugin.cancel(id);
    final when = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
    try {
      await _plugin.zonedSchedule(
            id,
            title,
            body,
            when,
            NotificationDetails(
              android: AndroidNotificationDetails(
                _doseChannelId,
                _doseChannelName,
                channelDescription: _doseChannelDesc,
                importance: Importance.high,
                priority: Priority.high,
                actions: const <AndroidNotificationAction>[
                  AndroidNotificationAction('taken', 'Taken'),
                  AndroidNotificationAction('snooze15', 'In 15 min'),
                  AndroidNotificationAction('skip', 'Skip'),
                ],
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            androidScheduleMode: await _scheduleMode(),
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: 'dose|$medicationId|$timeHm',
          );
    } catch (e, st) {
      debugPrint('Vitalog: schedule failed: $e\n$st');
      rethrow;
    }
  }

  int _habitId(String habitId) =>
      Object.hash('habit', habitId) & 0x7fffffff;

  Future<void> scheduleDailyHabit({
    required String habitId,
    required String timeHm,
    required String title,
  }) async {
    if (!_ready || kIsWeb) return;
    final parts = timeHm.split(':');
    if (parts.length < 2) return;
    final h = int.tryParse(parts[0]) ?? -1;
    final m = int.tryParse(parts[1]) ?? -1;
    if (h < 0 || m < 0) return;

    final id = _habitId(habitId);
    await _plugin.cancel(id);

    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }

    try {
      await _plugin.zonedSchedule(
            id,
            title,
            'Check in on Today when you can — not medical advice.',
            when,
            NotificationDetails(
              android: AndroidNotificationDetails(
                _habitChannelId,
                _habitChannelName,
                channelDescription: _habitChannelDesc,
                importance: Importance.defaultImportance,
                priority: Priority.defaultPriority,
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
              macOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            androidScheduleMode: await _scheduleMode(),
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.time,
            payload: 'habit|$habitId|$timeHm',
          );
    } catch (e, st) {
      debugPrint('Vitalog: schedule failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> cancelDailyHabit(String habitId) async {
    if (!_ready || kIsWeb) return;
    await _plugin.cancel(_habitId(habitId));
  }

  Future<void> rescheduleAllHabits(
    Iterable<Map<String, Object?>> habits,
  ) async {
    if (!_ready || kIsWeb) return;
    for (final h in habits) {
      final id = h['id'] as String?;
      if (id == null) continue;
      final enabled = ((h['reminder_enabled'] as int?) ?? 0) == 1;
      final hm = h['reminder_hm'] as String?;
      if (!enabled || hm == null || hm.trim().isEmpty) {
        await cancelDailyHabit(id);
        continue;
      }
      final title = h['title'] as String? ?? 'Habit';
      await scheduleDailyHabit(habitId: id, timeHm: hm.trim(), title: title);
    }
  }


}
