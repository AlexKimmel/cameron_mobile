import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:planner/planner.dart';
import 'package:planner_assistant/planner_assistant.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'planner_notifications.dart';
import 'platform_services.dart';

const _taskName = 'com.example.cameronMobile.briefing';
const _scheduledConfigurationKey = 'planner.briefing.schedulerConfiguration';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

BotPsyAssistant createAssistant({bool background = false}) => BotPsyAssistant(
  background: background,
  modelDirectory: () async => (await getApplicationSupportDirectory()).path,
);

class PreferencesBriefingStore implements BriefingStore {
  PreferencesBriefingStore({this.notifications});

  final LocalPlannerNotifications? notifications;
  final _prefs = SharedPreferencesAsync();

  static const _focus = PlannerPreferenceKeys.briefingFocus;

  String _key(BriefingSlot slot) => 'planner.briefing.v2.${slot.period.name}';

  @override
  Future<String?> read(BriefingSlot slot, String input) async {
    final value = await _prefs.getString(_key(slot));
    if (value == null) return null;
    final record = jsonDecode(value) as Map<String, dynamic>;
    return record['slot'] == slot.id && record['input'] == input
        ? record['summary'] as String
        : null;
  }

  @override
  Future<void> save(BriefingSlot slot, String input, String summary) async {
    final schedule = await readSchedule();
    if (BriefingSlot.current(slot.start, schedule: schedule)?.id != slot.id) {
      return;
    }
    await _prefs.setString(
      _key(slot),
      jsonEncode({'slot': slot.id, 'input': input, 'summary': summary}),
    );
    try {
      final service = notifications;
      if (service != null) {
        await service.briefingSaved(slot, await readSchedule());
      }
    } catch (error) {
      debugPrint('Could not post briefing notification: $error');
    }
  }

  @override
  Future<String> readFocus() async => await _prefs.getString(_focus) ?? '';

  @override
  Future<void> saveFocus(String focus) => _prefs.setString(_focus, focus);

  @override
  Future<BriefingSchedule> readSchedule() async {
    final value = await _prefs.getString(PlannerPreferenceKeys.briefingTimes);
    return value == null
        ? BriefingSchedule.defaults
        : BriefingSchedule.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  @override
  Future<void> saveSchedule(BriefingSchedule schedule) => _prefs.setString(
    PlannerPreferenceKeys.briefingTimes,
    jsonEncode(schedule.toJson()),
  );
}

Future<void> startBriefingJobs() async {
  if (kIsWeb || (!_isIos && defaultTargetPlatform != TargetPlatform.android)) {
    return;
  }
  try {
    final schedule = await PreferencesBriefingStore().readSchedule();
    final workmanager = Workmanager();
    await workmanager.initialize(briefingDispatcher);
    if (_isIos) {
      await workmanager.cancelByUniqueName(_taskName);
    } else {
      final prefs = SharedPreferencesAsync();
      final previous = await prefs.getString(_scheduledConfigurationKey);
      if (previous != null && previous != schedule.key) {
        await workmanager.cancelByTag('$_taskName.$previous');
      }
      await prefs.setString(_scheduledConfigurationKey, schedule.key);
    }
    await _scheduleNext(DateTime.now(), schedule);
  } catch (error) {
    debugPrint('Could not schedule briefings: $error');
  }
}

Future<void> _scheduleNext(DateTime now, BriefingSchedule schedule) {
  final next = BriefingSlot.next(now, schedule: schedule);
  final input = {'schedule': schedule.key};
  // The plugin accepts whole seconds. Round up so an early callback
  // cannot encounter and keep its own still-running Android request.
  final delay = Duration(seconds: next.start.difference(now).inSeconds + 1);
  if (_isIos) {
    return Workmanager().registerProcessingTask(
      _taskName,
      _taskName,
      initialDelay: delay,
      inputData: input,
    );
  }
  return Workmanager().registerOneOffTask(
    '$_taskName.${schedule.key}.${next.start.millisecondsSinceEpoch}',
    _taskName,
    initialDelay: delay,
    tag: '$_taskName.${schedule.key}',
    inputData: input,
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}

@pragma('vm:entry-point')
void briefingDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((taskName, input) async {
    if (taskName != _taskName) return true;
    final assistant = createAssistant(background: true);
    try {
      if (!await assistant.isInstalled()) return true;
      final now = DateTime.now();
      final schedule = await PreferencesBriefingStore().readSchedule();
      await _scheduleNext(now, schedule);
      final planned = input?['schedule'] ?? BriefingSchedule.defaults.key;
      if (!_isIos && planned != schedule.key) return true;
      final store = PreferencesTaskStore();
      final notifications = LocalPlannerNotifications.supported
          ? LocalPlannerNotifications(store)
          : null;
      final tasks = await store.read();
      await BriefingService(
        store: PreferencesBriefingStore(notifications: notifications),
        assistant: assistant,
      ).refresh(now, tasks, schedule: schedule);
      return true;
    } catch (error) {
      debugPrint('Background briefing failed: $error');
      return false;
    } finally {
      await assistant.dispose();
    }
  });
}
