import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';
import 'package:planner_ui/planner_ui.dart';

import 'briefing_jobs.dart';
import 'health_briefing.dart';
import 'local_backup.dart';
import 'planner_notifications.dart';
import 'platform_services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final assistant = createAssistant();
  final notifications = LocalPlannerNotifications.supported
      ? LocalPlannerNotifications(PreferencesTaskStore())
      : null;
  notifications?.begin();
  final store = PreferencesTaskStore(onSaved: notifications?.refreshTasks);
  final catalog = assistant.models;
  final backup = LocalPlannerBackup(
    store,
    models: catalog is AssistantModelCatalog
        ? catalog as AssistantModelCatalog
        : null,
  );
  runApp(
    PlannerApp(
      store: store,
      backup: backup,
      onboarding: PreferencesOnboarding(),
      notificationSettings: notifications,
      assistant: assistant,
      promptStore: PreferencesAssistantPromptStore(),
      modelLibrary: assistant.models,
      briefingStore: PreferencesBriefingStore(notifications: notifications),
      healthBriefing: LocalHealthBriefing.supported
          ? LocalHealthBriefing()
          : null,
      scheduleBriefings: startBriefingJobs,
      toolStore: PreferencesDeviceToolStore(),
      openDeviceTool: mobileToolOpener,
      calendar: MobileCalendar.supported ? MobileCalendar() : null,
      dictation: MobileDictation.supported ? MobileDictation() : null,
    ),
  );
}
