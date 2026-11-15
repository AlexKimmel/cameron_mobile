import 'package:material_ui/material_ui.dart';
import 'package:planner_ui/planner_ui.dart';

import 'briefing_jobs.dart';
import 'platform_services.dart';

void main() {
  runApp(
    PlannerApp(
      store: PreferencesTaskStore(),
      assistant: createAssistant(),
      briefingStore: PreferencesBriefingStore(),
      scheduleBriefings: startBriefingJobs,
      toolStore: PreferencesDeviceToolStore(),
      openDeviceTool: mobileToolOpener,
      dictation: MobileDictation.supported ? MobileDictation() : null,
    ),
  );
}
