import 'package:material_ui/material_ui.dart';
import 'package:planner_ui/planner_ui.dart';

import 'briefing_jobs.dart';
import 'planner_notifications.dart';
import 'platform_services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final assistant = createAssistant();
  final notifications = LocalPlannerNotifications.supported
      ? LocalPlannerNotifications(PreferencesTaskStore())
      : null;
  notifications?.begin();
  runApp(
    PlannerApp(
      store: PreferencesTaskStore(onSaved: notifications?.refreshTasks),
      notificationSettings: notifications,
      assistant: assistant,
      modelLibrary: assistant.models,
      briefingStore: PreferencesBriefingStore(notifications: notifications),
      scheduleBriefings: startBriefingJobs,
      toolStore: PreferencesDeviceToolStore(),
      openDeviceTool: mobileToolOpener,
      calendar: MobileCalendar.supported ? MobileCalendar() : null,
      dictation: MobileDictation.supported ? MobileDictation() : null,
    ),
  );
}
