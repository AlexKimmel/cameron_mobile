import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:planner/planner.dart';
import 'package:planner_assistant/planner_assistant.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'platform_services.dart';

const _taskName = 'com.example.cameronMobile.briefing';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

BotPsyAssistant createAssistant({bool background = false}) => BotPsyAssistant(
  background: background,
  modelDirectory: () async => (await getApplicationSupportDirectory()).path,
);

class PreferencesBriefingStore implements BriefingStore {
  final _prefs = SharedPreferencesAsync();

  String _key(BriefingSlot slot) => 'planner.briefing.v1.${slot.period.name}';

  @override
  Future<String?> read(BriefingSlot slot) async {
    final value = await _prefs.getString(_key(slot));
    if (value == null) return null;
    final record = jsonDecode(value) as Map<String, dynamic>;
    return record['slot'] == slot.id ? record['summary'] as String : null;
  }

  @override
  Future<void> save(BriefingSlot slot, String summary) => _prefs.setString(
    _key(slot),
    jsonEncode({'slot': slot.id, 'summary': summary}),
  );
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
      final tasks = await PreferencesTaskStore().read();
      await BriefingService(
        store: PreferencesBriefingStore(),
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
