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

      await tester.tap(find.bySemanticsLabel('Tasks & Tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Complete Design review'));
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
