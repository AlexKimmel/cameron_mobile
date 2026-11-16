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

  test(
    'Task reminders deduplicate at quiet end and preserve the saved offset',
    () {
      const task = PlannerTask(
        id: 'early',
        title: 'Early session',
        day: '2026-11-16',
        startMinute: 6 * 60,
        reminderMinutes: 30,
      );
      final restored = PlannerTask.fromJson(task.toJson());
      expect(restored.reminderMinutes, 30);
      final quiet = QuietHours(startMinute: 22 * 60, endMinute: 7 * 60);
      final start = DateTime(2026, 11, 15, 20);
      final noQuiet = upcomingTaskNotices(
        [restored],
        start,
        includeReminders: true,
      );
      expect(noQuiet.map((notice) => notice.time), [
        DateTime(2026, 11, 16, 5, 30),
        DateTime(2026, 11, 16, 6),
      ]);

      final delayed = upcomingTaskNotices(
        [restored],
        start,
        includeReminders: true,
        quietHours: quiet,
      );
      expect(delayed.single.time, DateTime(2026, 11, 16, 7));
      expect(delayed.single.reminder, isTrue);
      expect(
        quiet.nextAllowed(DateTime(2026, 11, 15, 22, 5)),
        DateTime(2026, 11, 16, 7),
      );
      expect(
        quiet.nextAllowed(DateTime(2026, 11, 16, 7)),
        DateTime(2026, 11, 16, 7),
      );
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
    await tester.tap(find.bySemanticsLabel('Tool settings'));
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

    final quiet = find.widgetWithText(SwitchListTile, 'Quiet hours');
    await tester.ensureVisible(quiet);
    await tester.pumpAndSettle();
    await tester.tap(quiet);
    await tester.pumpAndSettle();
    expect(settings.quiet?.startMinute, 22 * 60);
    expect(settings.quiet?.endMinute, 7 * 60);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Task editor saves a reminder without changing the task date', (
    tester,
  ) async {
    final store = MemoryTaskStore();
    await tester.pumpWidget(
      PlannerApp(
        store: store,
        assistant: _OffAssistant(),
        notificationSettings: _Settings(),
        initialTab: 1,
        clock: () => DateTime(2026, 11, 15, 10),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Prepare notes');
    await tester.ensureVisible(find.text('No reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15m before').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save task'));
    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();
    final task = (await store.read()).single;
    expect(task.reminderMinutes, 15);
    expect(task.day, '2026-11-15');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Settings implements PlannerNotificationSettings {
  bool canGrant = false;
  bool permitted = false;
  int requests = 0;
  QuietHours? quiet;
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

  @override
  Future<QuietHours?> readQuietHours() async => quiet;

  @override
  Future<void> saveQuietHours(QuietHours? hours) async {
    quiet = hours;
  }
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
