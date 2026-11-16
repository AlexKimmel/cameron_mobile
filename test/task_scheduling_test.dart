import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';
import 'package:planner_ui/planner_ui.dart';

void main() {
  test('Conflict suggestions include off-grid gaps and crossing midnight', () {
    final today = DateTime(2026, 11, 15, 8);
    const task = PlannerTask(
      id: 'new',
      day: '2026-11-15',
      title: 'Short session',
      startMinute: 9 * 60 + 5,
      duration: 10,
    );
    const first = PlannerTask(
      id: 'short',
      day: '2026-11-15',
      title: 'Short meeting',
      startMinute: 9 * 60,
      duration: 7,
    );
    const later = PlannerTask(
      id: 'later',
      day: '2026-11-15',
      title: 'Later meeting',
      startMinute: 9 * 60 + 18,
      duration: 42,
    );
    final conflict = inspectSchedule([first, later], task, today)!;
    expect(conflict.sessions, [first]);
    expect(conflict.suggestedMinutes.first, 9 * 60 + 7);

    const late = PlannerTask(
      id: 'late',
      day: '2026-11-15',
      title: 'Late meeting',
      startMinute: 23 * 60 + 30,
      duration: 60,
    );
    final nextDay = task.copyWith(day: '2026-11-16', startMinute: 10);
    expect(inspectSchedule([late], nextDay, today)?.suggestedMinutes.first, 30);
  });

  test(
    'Cancelling an assistant conflict keeps the whole batch unsaved',
    () async {
      const old = PlannerTask(
        id: 'old',
        title: 'Booked',
        day: '2026-11-15',
        startMinute: 540,
        duration: 30,
      );
      final store = MemoryTaskStore([old]);
      final result = await PlannerTools().apply(
        const [
          PlannerToolCall(PlannerTools.createTask, {'title': 'Untimed task'}),
          PlannerToolCall(PlannerTools.createTask, {
            'title': 'Overlapping task',
            'time': '09:15',
            'duration_minutes': 30,
          }),
        ],
        store: store,
        currentTasks: [old],
        now: DateTime(2026, 11, 15, 8),
        reviewSchedule: (conflict) async {
          expect(conflict.sessions.single.id, old.id);
          return null;
        },
      );
      expect(result.cancelled, isTrue);
      expect(await store.read(), [old]);
    },
  );

  testWidgets('Groups tasks by date and moves an overdue task from its card', (
    tester,
  ) async {
    final store = MemoryTaskStore([
      const PlannerTask(
        id: 'past',
        title: 'Schedule the follow-up',
        day: '2026-11-13',
        startMinute: 660,
        duration: 30,
        steps: [TaskStep('Confirm agenda', done: true)],
      ),
      const PlannerTask(
        id: 'future',
        title: 'Plan the next review',
        day: '2026-11-17',
      ),
      const PlannerTask(id: 'second', title: 'Review notes', day: '2026-11-17'),
    ]);
    await tester.pumpWidget(
      PlannerApp(
        store: store,
        assistant: _OffAssistant(),
        initialTab: 1,
        clock: () => DateTime(2026, 11, 15, 9),
      ),
    );
    await tester.pumpAndSettle();

    final overdue = find.textContaining('Overdue', findRichText: true);
    expect(overdue, findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    final localizations = MaterialLocalizations.of(
      tester.element(find.text('Schedule the follow-up')),
    );
    final futureDay = localizations.formatFullDate(DateTime(2026, 11, 17));
    expect(find.text(futureDay), findsOneWidget);

    await tester.tap(
      find.bySemanticsLabel('Reschedule Schedule the follow-up'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('17'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(overdue, findsNothing);
    expect(find.text(futureDay), findsOneWidget);

    final moved = (await store.read()).singleWhere((task) => task.id == 'past');
    expect(moved.day, '2026-11-17');
    expect(moved.startMinute, 660);
    expect(moved.duration, 30);
    expect(moved.steps.single.done, isTrue);
    expect(moved.origin, TaskOrigin.manual);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Creates a repeating task and edits one occurrence or the series',
    (tester) async {
      final store = MemoryTaskStore();
      final now = DateTime(2026, 11, 15, 9);
      await tester.pumpWidget(
        PlannerApp(
          store: store,
          assistant: _OffAssistant(),
          initialTab: 1,
          clock: () => now,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Add task'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Pay rent');
      final frequency = find.text('Does not repeat');
      await tester.ensureVisible(frequency);
      await tester.tap(frequency);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monthly').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save task'));
      await tester.tap(find.text('Save task'));
      await tester.pumpAndSettle();
      expect(
        (await store.read()).single.repeat?.frequency,
        RepeatFrequency.monthly,
      );

      final first = find.text('Pay rent').first;
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('This occurrence'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Pay partial rent',
      );
      await tester.ensureVisible(find.text('Save occurrence'));
      await tester.tap(find.text('Save occurrence'));
      await tester.pumpAndSettle();
      expect(find.text('Pay partial rent'), findsOneWidget);

      await tester.tap(find.text('Pay partial rent'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Whole series'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Send rent payment',
      );
      await tester.ensureVisible(find.text('Save series'));
      await tester.tap(find.text('Save series'));
      await tester.pumpAndSettle();

      final tasks = expandTasks(await store.read(), now);
      expect(tasks.first.title, 'Pay partial rent');
      expect(
        tasks.skip(1).every((task) => task.title == 'Send rent payment'),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Can cancel an overlap or pick a free time before saving a session',
    (tester) async {
      final now = DateTime(2026, 11, 15, 9);
      final store = MemoryTaskStore([
        const PlannerTask(
          id: 'booked',
          title: 'Booked',
          day: '2026-11-15',
          startMinute: 540,
          duration: 30,
        ),
      ]);
      await tester.pumpWidget(
        PlannerApp(store: store, assistant: _OffAssistant(), clock: () => now),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Add session'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Planning session',
      );
      final save = find.text('Save task');

      Future<void> checkOverlap() async {
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('Scheduling conflict'), findsOneWidget);
        expect(await store.read(), hasLength(1));
      }

      await checkOverlap();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Planning session'), findsOneWidget);
      await checkOverlap();

      final label = MaterialLocalizations.of(
        tester.element(find.byType(AlertDialog)),
      ).formatTimeOfDay(const TimeOfDay(hour: 9, minute: 30));
      await tester.tap(find.text('Use $label'));
      await tester.pumpAndSettle();
      final saved = (await store.read()).singleWhere(
        (task) => task.title == 'Planning session',
      );
      expect(saved.startMinute, 570);
      expect(saved.duration, 30);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
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
