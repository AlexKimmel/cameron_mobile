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
    await _prefs.setString(
      _key(slot),
      jsonEncode({'slot': slot.id, 'input': input, 'summary': summary}),
    );
    try {
      await notifications?.briefingSaved(slot);
    } catch (error) {
      debugPrint('Could not post briefing notification: $error');
    }
  }

  @override
  Future<String> readFocus() async => await _prefs.getString(_focus) ?? '';

  @override
  Future<void> saveFocus(String focus) => _prefs.setString(_focus, focus);
}

Future<void> startBriefingJobs() async {
  if (kIsWeb || (!_isIos && defaultTargetPlatform != TargetPlatform.android)) {
    return;
  }
  try {
    await Workmanager().initialize(briefingDispatcher);
    await _scheduleNext(DateTime.now());
  } catch (error) {
    debugPrint('Could not schedule briefings: $error');
  }
}

Future<void> _scheduleNext(DateTime now) {
  final next = BriefingSlot.next(now);
  // The plugin accepts whole seconds. Round up so an early callback
  // cannot encounter and keep its own still-running Android request.
  final delay = Duration(seconds: next.start.difference(now).inSeconds + 1);
  if (_isIos) {
    return Workmanager().registerProcessingTask(
      _taskName,
      _taskName,
      initialDelay: delay,
    );
  }
  return Workmanager().registerOneOffTask(
    '$_taskName.${next.start.millisecondsSinceEpoch}',
    _taskName,
    initialDelay: delay,
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}

@pragma('vm:entry-point')
void briefingDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((taskName, _) async {
    if (taskName != _taskName) return true;
    final assistant = createAssistant(background: true);
    try {
      if (!await assistant.isInstalled()) return true;
      final now = DateTime.now();
      await _scheduleNext(now);
      final store = PreferencesTaskStore();
      final notifications = LocalPlannerNotifications.supported
          ? LocalPlannerNotifications(store)
          : null;
      final tasks = await store.read();
      await BriefingService(
        store: PreferencesBriefingStore(notifications: notifications),
        assistant: assistant,
      ).refresh(now, tasks);
      return true;
    } catch (error) {
      debugPrint('Background briefing failed: $error');
      return false;
    } finally {
      await assistant.dispose();
    }
  });
}
