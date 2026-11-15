import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:planner/planner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'platform_services.dart';

const _snoozeAction = 'snooze_task';
const _taskCategory = 'planner_task';

@pragma('vm:entry-point')
void plannerNotificationAction(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(
    LocalPlannerNotifications(PreferencesTaskStore()).handleAction(response),
  );
}

class LocalPlannerNotifications
    with WidgetsBindingObserver
    implements PlannerNotificationSettings {
  LocalPlannerNotifications(this._tasks);

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static const _taskIdStart = 1000;
  static const _taskLimit = 48;
  static const _quietKey = PlannerPreferenceKeys.quietHours;
  static const _snoozePrefix = 'planner.notifications.snooze.';
  static const _taskDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'scheduled_tasks',
      'Scheduled tasks',
      actions: [AndroidNotificationAction(_snoozeAction, 'Snooze 10 minutes')],
    ),
    iOS: DarwinNotificationDetails(categoryIdentifier: _taskCategory),
  );
  static const _briefingDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_briefings',
      'Daily briefings',
      onlyAlertOnce: true,
    ),
    iOS: DarwinNotificationDetails(),
  );

  final TaskStore _tasks;
  final _prefs = SharedPreferencesAsync();
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void> _taskWork = Future<void>.value();
  Future<bool?>? _initializing;

  Future<bool?> _initialize() async {
    final pending = _initializing ??= _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _taskCategory,
              actions: [
                DarwinNotificationAction.plain(
                  _snoozeAction,
                  'Snooze 10 minutes',
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: handleAction,
      onDidReceiveBackgroundNotificationResponse: plannerNotificationAction,
    );
    try {
      return await pending;
    } catch (_) {
      if (identical(_initializing, pending)) _initializing = null;
      rethrow;
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  void begin() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(refreshTasks());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refreshTasks());
  }

  String _key(PlannerNotificationKind kind) =>
      PlannerPreferenceKeys.notification(kind);

  @override
  Future<bool> isEnabled(PlannerNotificationKind kind) async =>
      await _prefs.getBool(_key(kind)) ?? false;

  @override
  Future<void> setEnabled(PlannerNotificationKind kind, bool enabled) async {
    await _prefs.setBool(_key(kind), enabled);
    if (kind != PlannerNotificationKind.briefingReady) await refreshTasks();
  }

  @override
  Future<bool> hasPermission() async {
    await _initialize();
    return await _android?.areNotificationsEnabled() ??
        (await _ios?.checkPermissions())?.isEnabled ??
        false;
  }

  @override
  Future<bool> requestPermission() async {
    if (await hasPermission()) return true;
    return await _android?.requestNotificationsPermission() ??
        await _ios?.requestPermissions(alert: true, sound: true) ??
        false;
  }

  @override
  Future<void> openSystemSettings() => openMobileAppSettings();

  @override
  Future<QuietHours?> readQuietHours() async {
    final data = await _prefs.getString(_quietKey);
    if (data == null) return null;
    final hours = jsonDecode(data) as List;
    return QuietHours(startMinute: hours[0] as int, endMinute: hours[1] as int);
  }

  @override
  Future<void> saveQuietHours(QuietHours? hours) async {
    if (hours == null) {
      await _prefs.remove(_quietKey);
    } else {
      await _prefs.setString(
        _quietKey,
        jsonEncode([hours.startMinute, hours.endMinute]),
      );
    }
    await refreshTasks();
  }

  Future<void> handleAction(NotificationResponse response) async {
    if (response.actionId != _snoozeAction || response.payload == null) return;
    try {
      final payload = jsonDecode(response.payload!);
      if (payload is! List || payload.isEmpty || payload.first is! String) {
        return;
      }
      final id = payload.first as String;
      final task = findTaskRecord(await _tasks.read(), id);
      if (task == null || task.done) return;
      final until = DateTime.now().add(const Duration(minutes: 10));
      await _prefs.setInt('$_snoozePrefix$id', until.millisecondsSinceEpoch);
      await refreshTasks();
    } catch (error) {
      debugPrint('Could not snooze task notification: $error');
    }
  }

  Future<List<TaskDueNotice>> _readSnoozes(
    List<PlannerTask> tasks,
    DateTime now,
    QuietHours? quietHours,
  ) async {
    final notices = <TaskDueNotice>[];
    for (final key in await _prefs.getKeys()) {
      if (!key.startsWith(_snoozePrefix)) continue;
      final id = key.substring(_snoozePrefix.length);
      final timestamp = await _prefs.getInt(key);
      if (timestamp == null) continue;
      final task = findTaskRecord(tasks, id);
      final requested = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final time = quietHours?.nextAllowed(requested) ?? requested;
      if (task == null || task.done || !time.isAfter(now)) {
        await _prefs.remove(key);
      } else {
        notices.add(TaskDueNotice(task: task, time: time, reminder: true));
      }
    }
    notices.sort((a, b) => a.time.compareTo(b.time));
    return notices;
  }

  Future<void> refreshTasks() {
    _taskWork = _taskWork.then((_) => _syncTaskNotices()).catchError((
      Object error,
    ) {
      debugPrint('Could not sync task notifications: $error');
    });
    return _taskWork;
  }

  Future<void> _syncTaskNotices() async {
    final due = await isEnabled(PlannerNotificationKind.taskDue);
    final reminders = await isEnabled(PlannerNotificationKind.reminder);
    final active = (due || reminders) && await hasPermission();
    await _initialize();
    final pending = {
      for (final request in await _plugin.pendingNotificationRequests())
        if (request.id >= _taskIdStart &&
            request.id < _taskIdStart + _taskLimit)
          request.id: request.payload,
    };
    final notices = <TaskDueNotice>[];
    if (active) {
      final tasks = await _tasks.read();
      final now = DateTime.now();
      final quiet = await readQuietHours();
      final snoozes = await _readSnoozes(tasks, now, quiet);
      final scheduled = upcomingTaskNotices(
        tasks,
        now,
        includeDue: due,
        includeReminders: reminders,
        quietHours: quiet,
      );
      final seen = <(String, DateTime)>{};
      for (final notice in [...snoozes, ...scheduled]) {
        if (seen.add((notice.task.id, notice.time))) notices.add(notice);
        if (notices.length == _taskLimit) break;
      }
    }
    for (final (index, notice) in notices.indexed) {
      final id = _taskIdStart + index;
      if (!notice.time.isAfter(DateTime.now())) continue;
      final payload = jsonEncode([
        notice.task.id,
        notice.task.title,
        notice.time.millisecondsSinceEpoch,
        notice.reminder,
      ]);
      if (pending.remove(id) == payload) continue;
      await _plugin.zonedSchedule(
        id: id,
        title: notice.reminder ? 'Task reminder' : 'Scheduled task',
        body: notice.task.title,
        notificationDetails: _taskDetails,
        scheduledDate: tz.TZDateTime.from(notice.time, tz.UTC),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    }
    for (final id in pending.keys) {
      await _plugin.cancel(id: id);
    }
  }

  Future<void> briefingSaved(BriefingSlot slot) async {
    if (BriefingSlot.current(DateTime.now())?.id != slot.id ||
        !await isEnabled(PlannerNotificationKind.briefingReady) ||
        !await hasPermission()) {
      return;
    }
    final key = 'planner.notifications.last.${slot.period.name}';
    if (await _prefs.getString(key) == slot.id) return;
    await _plugin.show(
      id: slot.period.index + 1,
      title: 'Daily briefing',
      body: 'Your ${slot.period.name} briefing is ready.',
      notificationDetails: _briefingDetails,
    );
    await _prefs.setString(key, slot.id);
  }
}
