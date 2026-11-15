import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:planner/planner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'platform_services.dart';

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
  static const _taskDetails = NotificationDetails(
    android: AndroidNotificationDetails('scheduled_tasks', 'Scheduled tasks'),
    iOS: DarwinNotificationDetails(),
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
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
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
      'planner.notifications.${kind.name}';

  @override
  Future<bool> isEnabled(PlannerNotificationKind kind) async =>
      await _prefs.getBool(_key(kind)) ?? false;

  @override
  Future<void> setEnabled(PlannerNotificationKind kind, bool enabled) async {
    await _prefs.setBool(_key(kind), enabled);
    if (kind == PlannerNotificationKind.taskDue) await refreshTasks();
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

  Future<void> refreshTasks() {
    _taskWork = _taskWork.then((_) => _syncTaskNotices()).catchError((
      Object error,
    ) {
      debugPrint('Could not sync task notifications: $error');
    });
    return _taskWork;
  }

  Future<void> _syncTaskNotices() async {
    final active =
        await isEnabled(PlannerNotificationKind.taskDue) &&
        await hasPermission();
    await _initialize();
    final pending = {
      for (final request in await _plugin.pendingNotificationRequests())
        if (request.id >= _taskIdStart &&
            request.id < _taskIdStart + _taskLimit)
          request.id: request.payload,
    };
    final notices = active
        ? upcomingTaskNotices(
            await _tasks.read(),
            DateTime.now(),
          ).take(_taskLimit)
        : <TaskDueNotice>[];
    for (final (index, notice) in notices.indexed) {
      final id = _taskIdStart + index;
      final payload = jsonEncode([
        notice.task.id,
        notice.task.title,
        notice.time.millisecondsSinceEpoch,
      ]);
      if (pending.remove(id) == payload) continue;
      await _plugin.zonedSchedule(
        id: id,
        title: 'Scheduled task',
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
