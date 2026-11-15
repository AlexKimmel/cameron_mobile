import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';
import 'package:planner_ui/planner_ui.dart';

void main() {
  test(
    'Task alerts use scheduled time and skip completed or elapsed tasks',
    () {
      final now = DateTime(2026, 11, 15, 10);
      final notices = upcomingTaskNotices([
        const PlannerTask(id: 'past', title: 'Past date', day: '2026-11-15'),
        const PlannerTask(
          id: 'done',
          title: 'Done',
          day: '2026-11-16',
          completedOn: '2026-11-15',
        ),
        const PlannerTask(id: 'dated', title: 'Dated', day: '2026-11-17'),
        PlannerTask(
          id: 'repeat',
          title: 'Timed repeat',
          day: '2026-11-15',
          startMinute: 11 * 60 + 15,
          repeat: RepeatRule(
            frequency: RepeatFrequency.daily,
            until: '2026-11-16',
          ),
        ),
      ], now);

      expect(notices.map((notice) => notice.task.title), [
        'Timed repeat',
        'Timed repeat',
        'Dated',
      ]);
      expect(notices.map((notice) => notice.time), [
        DateTime(2026, 11, 15, 11, 15),
        DateTime(2026, 11, 16, 11, 15),
        DateTime(2026, 11, 17, 9),
      ]);
    },
  );

  testWidgets('Notification switches require explicit OS permission', (
    tester,
  ) async {
    final settings = _Settings();
    await tester.pumpWidget(
      PlannerApp(
        store: MemoryTaskStore(),
        assistant: _OffAssistant(),
        notificationSettings: settings,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tool settings'));
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(SwitchListTile, 'Scheduled tasks');
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(settings.requests, 0);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(settings.requests, 1);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(
      find.text('Allow notifications in device settings, then try again.'),
      findsOneWidget,
    );

    settings.canGrant = true;
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(settings.enabled, {PlannerNotificationKind.taskDue});

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(settings.requests, 2);
    expect(settings.enabled, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Settings implements PlannerNotificationSettings {
  bool canGrant = false;
  bool permitted = false;
  int requests = 0;
  final enabled = <PlannerNotificationKind>{};

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<bool> requestPermission() async {
    requests++;
    return permitted = canGrant;
  }

  @override
  Future<bool> isEnabled(PlannerNotificationKind kind) async =>
      enabled.contains(kind);

  @override
  Future<void> setEnabled(PlannerNotificationKind kind, bool value) async {
    if (value) {
      enabled.add(kind);
    } else {
      enabled.remove(kind);
    }
  }

  @override
  Future<void> openSystemSettings() async {}
}

class _OffAssistant implements PlannerAssistant {
  @override
  bool get supported => false;

  @override
  Future<bool> isInstalled() async => false;

  @override
  Future<void> install(void Function(double? fraction) onProgress) async {}

  @override
  Future<AssistantReply> ask(
    String prompt, {
    required List<PlannerTask> tasks,
    required DateTime now,
    bool readOnly = false,
    List<DeviceTool> deviceTools = const [],
  }) async => const AssistantReply();

  @override
  Future<void> dispose() async {}
}
