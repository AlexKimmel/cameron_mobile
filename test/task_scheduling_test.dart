import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';
import 'package:planner_ui/planner_ui.dart';

void main() {
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

    await tester.tap(find.byTooltip('Reschedule Schedule the follow-up'));
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
