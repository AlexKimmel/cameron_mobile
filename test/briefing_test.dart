import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';
import 'package:planner_ui/planner_ui.dart';

void main() {
  test('Briefing windows use local calendar boundaries', () {
    expect(BriefingSlot.current(DateTime(2026, 11, 15, 6, 59)), isNull);
    for (final period in BriefingPeriod.values) {
      final now = DateTime(2026, 11, 15, period.hour);
      expect(BriefingSlot.current(now)?.period, period);
      expect(BriefingSlot.next(now).start.isAfter(now), isTrue);
    }
    expect(
      BriefingSlot.next(DateTime(2026, 11, 15, 18)).start,
      DateTime(2026, 11, 16, 7),
    );
  });

  test(
    'Saved briefing times control generation and roll over locally',
    () async {
      final store = _Store();
      final assistant = _Assistant();
      final service = BriefingService(store: store, assistant: assistant);
      final schedule = BriefingSchedule(
        morning: 570,
        midday: 750,
        evening: 1110,
      );
      await store.saveSchedule(schedule);
      const tasks = [
        PlannerTask(id: 'today', title: 'Design review', day: '2026-11-15'),
      ];
      expect(
        await service.refresh(DateTime(2026, 11, 15, 9, 29), tasks),
        isNull,
      );
      expect(
        await service.refresh(DateTime(2026, 11, 15, 9, 30), tasks),
        'Briefing 1.',
      );
      expect(assistant.prompts.single, contains('morning briefing'));
      expect(
        BriefingSlot.next(DateTime(2026, 11, 15, 23), schedule: schedule).start,
        DateTime(2026, 11, 16, 9, 30),
      );
    },
  );

  testWidgets('Saving briefing times refreshes the current briefing', (
    tester,
  ) async {
    final briefing = _Store();
    final assistant = _Assistant();
    var schedules = 0;
    final now = DateTime(2026, 11, 15, 9);
    await briefing.saveSchedule(
      BriefingSchedule(morning: 570, midday: 750, evening: 1110),
    );
    await tester.pumpWidget(
      PlannerApp(
        store: MemoryTaskStore([
          const PlannerTask(
            id: 'design',
            title: 'Design review',
            day: '2026-11-15',
          ),
        ]),
        assistant: assistant,
        briefingStore: briefing,
        scheduleBriefings: () async {
          schedules++;
        },
        clock: () => now,
      ),
    );
    await tester.pumpAndSettle();
    expect(assistant.prompts, isEmpty);
    final initialSchedules = schedules;
    await tester.tap(find.bySemanticsLabel('Tool settings'));
    await tester.pumpAndSettle();
    final edit = find.text('Edit briefing times');
    await tester.scrollUntilVisible(edit.hitTestable(), 200);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use default times'));
    await tester.tap(find.text('Save times'));
    await tester.pumpAndSettle();
    expect((await briefing.readSchedule()).key, BriefingSchedule.defaults.key);
    expect(schedules, initialSchedules + 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Briefing 1.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'Each briefing uses its own read-only prompt and reuses its saved result',
    () async {
      final assistant = _Assistant();
      final service = BriefingService(store: _Store(), assistant: assistant);
      final today = DateTime(2026, 11, 15);
      const tasks = [
        PlannerTask(id: 'today', title: 'Design review', day: '2026-11-15'),
        PlannerTask(id: 'tomorrow', title: 'Team sync', day: '2026-11-16'),
      ];
      for (final period in BriefingPeriod.values) {
        final now = DateTime(today.year, today.month, today.day, period.hour);
        final summary = await service.refresh(now, tasks);
        expect(await service.refresh(now, tasks), summary);
      }
      expect(assistant.prompts.length, 3);
      expect(assistant.prompts[0], contains('morning briefing'));
      expect(assistant.prompts[1], contains('midday briefing'));
      expect(assistant.prompts[2], contains('evening briefing'));
      expect(assistant.taskIds, [
        ['today'],
        ['today'],
        ['today', 'tomorrow'],
      ]);
    },
  );

  test(
    'Only changes to relevant tasks or focus invalidate a briefing',
    () async {
      final assistant = _Assistant();
      final store = _Store();
      final service = BriefingService(store: store, assistant: assistant);
      final now = DateTime(2026, 11, 15, 9);
      const task = PlannerTask(
        id: 'today',
        title: 'Design review',
        day: '2026-11-15',
      );

      expect(await service.refresh(now, [task]), 'Briefing 1.');
      expect(
        await service.refresh(now, [
          task,
          const PlannerTask(
            id: 'tomorrow',
            title: 'Team sync',
            day: '2026-11-16',
          ),
        ]),
        'Briefing 1.',
      );

      final completed = task.toggleDone(dayKey(now));
      expect(await service.refresh(now, [completed]), 'Briefing 2.');
      await store.saveFocus('Emphasize completed tasks');
      expect(await service.refresh(now, [completed]), 'Briefing 3.');
      expect(assistant.prompts.last, contains('Emphasize completed tasks'));
      expect(await service.refresh(now, []), isNull);
    },
  );

  test('Opted-in health context informs and invalidates briefings', () async {
    final assistant = _Assistant();
    final health = _FakeBriefingHealth('4200 steps today')..enabled = true;
    final service = BriefingService(
      store: _Store(),
      assistant: assistant,
      health: health,
    );
    final now = DateTime(2026, 11, 15, 9);

    expect(await service.refresh(now, []), 'Briefing 1.');
    expect(assistant.prompts.single, contains('4200 steps today'));
    expect(assistant.taskIds.single, isEmpty);

    health.context = '6000 steps today';
    expect(await service.refresh(now, []), 'Briefing 2.');
    expect(assistant.prompts.last, contains('6000 steps today'));
  });

  testWidgets('Health context can be enabled from Tool settings', (
    tester,
  ) async {
    final health = _FakeBriefingHealth('4200 steps today');
    await tester.pumpWidget(
      PlannerApp(
        store: MemoryTaskStore(),
        assistant: _Assistant(),
        healthBriefing: health,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Tool settings'));
    await tester.pumpAndSettle();

    final healthSwitch = find.widgetWithText(
      SwitchListTile,
      'Health context for briefings',
    );
    await tester.ensureVisible(healthSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(healthSwitch).value, isFalse);
    await tester.tap(healthSwitch);
    await tester.pumpAndSettle();
    expect(health.accessRequests, 1);
    expect(tester.widget<SwitchListTile>(healthSwitch).value, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Saving a briefing focus and completing tasks refresh the summary',
    (tester) async {
      final assistant = _Assistant();
      final briefing = _Store();
      final tasks = MemoryTaskStore([
        const PlannerTask(
          id: 'design',
          title: 'Design review',
          day: '2026-11-15',
        ),
      ]);
      await tester.pumpWidget(
        PlannerApp(
          store: tasks,
          assistant: assistant,
          briefingStore: briefing,
          clock: () => DateTime(2026, 11, 15, 9),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Briefing 1.'), findsOneWidget);

      await tester.tap(find.text('Briefing focus'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Highlight completed work',
      );
      await tester.tap(find.text('Save focus'));
      await tester.pumpAndSettle();
      expect(await briefing.readFocus(), 'Highlight completed work');
      expect(find.text('Briefing 2.'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Tasks'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Complete Design review'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Briefing'));
      await tester.pumpAndSettle();
      expect(find.text('Briefing 3.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _Store implements BriefingStore {
  final _summaries = <(String, String), String>{};
  String _focus = '';
  BriefingSchedule _schedule = BriefingSchedule.defaults;

  @override
  Future<String?> read(BriefingSlot slot, String input) async =>
      _summaries[(slot.id, input)];

  @override
  Future<void> save(BriefingSlot slot, String input, String summary) async {
    _summaries[(slot.id, input)] = summary;
  }

  @override
  Future<String> readFocus() async => _focus;

  @override
  Future<void> saveFocus(String focus) async {
    _focus = focus;
  }

  @override
  Future<BriefingSchedule> readSchedule() async => _schedule;

  @override
  Future<void> saveSchedule(BriefingSchedule schedule) async {
    _schedule = schedule;
  }
}

class _FakeBriefingHealth implements BriefingHealth {
  _FakeBriefingHealth(this.context);

  String context;
  bool enabled = false;
  int accessRequests = 0;

  @override
  Future<void> disable() async => enabled = false;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<String?> readContext(DateTime now) async => enabled ? context : null;

  @override
  Future<bool> requestAccess() async {
    accessRequests++;
    enabled = true;
    return true;
  }
}

class _Assistant implements PlannerAssistant {
  final prompts = <String>[];
  final taskIds = <List<String>>[];

  @override
  Future<AssistantReply> ask(
    String prompt, {
    required List<PlannerTask> tasks,
    required DateTime now,
    bool readOnly = false,
    List<DeviceTool> deviceTools = const [],
  }) async {
    expect(readOnly, isTrue);
    prompts.add(prompt);
    taskIds.add(tasks.map((task) => task.id).toList());
    return AssistantReply(text: 'Briefing ${prompts.length}.');
  }

  @override
  bool get supported => true;

  @override
  Future<bool> isInstalled() async => true;

  @override
  Future<void> install(void Function(double? fraction) onProgress) async {}

  @override
  Future<void> dispose() async {}
}
