import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';
import 'package:planner_ui/planner_ui.dart';

void main() {
  final now = DateTime(2026, 11, 15, 8);

  testWidgets('The sample day uses today and does not install the assistant', (
    tester,
  ) async {
    final state = _Welcome();
    final tasks = MemoryTaskStore();
    final assistant = _Assistant();
    await tester.pumpWidget(
      PlannerApp(
        store: tasks,
        assistant: assistant,
        onboarding: state,
        clock: () => now,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Cameron'), findsOneWidget);
    await tester.tap(find.text('Try a sample day'));
    await tester.pumpAndSettle();
    expect(state.seen, isTrue);
    expect(assistant.installs, 0);
    final added = await tasks.read();
    expect(added, hasLength(3));
    expect(added.every((task) => task.day == dayKey(now)), isTrue);
    expect(find.text('Plan a focus session'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Setting up later keeps the welcome closed on a later launch', (
    tester,
  ) async {
    final state = _Welcome();
    final assistant = _Assistant();
    final tasks = MemoryTaskStore();

    Widget app() => PlannerApp(
      store: tasks,
      assistant: assistant,
      onboarding: state,
      clock: () => now,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up the assistant later'));
    await tester.pumpAndSettle();
    expect(state.seen, isTrue);
    expect(await tasks.read(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Cameron'), findsNothing);
    expect(assistant.installs, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Quick add opens the task editor during first launch', (
    tester,
  ) async {
    final state = _Welcome();
    final tasks = MemoryTaskStore();
    await tester.pumpWidget(
      PlannerApp(
        store: tasks,
        assistant: _Assistant(),
        onboarding: state,
        clock: () => now,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add my first task'));
    await tester.pumpAndSettle();
    expect(find.text('New task'), findsOneWidget);
    expect(state.seen, isTrue);
    await tester.enterText(find.byType(TextFormField).first, 'First task');
    final save = find.text('Save task');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await tasks.read()).single.title, 'First task');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Welcome implements PlannerOnboarding {
  bool seen = false;

  @override
  Future<bool> hasSeenWelcome() async => seen;

  @override
  Future<void> markWelcomeSeen() async {
    seen = true;
  }
}

class _Assistant implements PlannerAssistant {
  int installs = 0;

  @override
  bool get supported => true;

  @override
  Future<bool> isInstalled() async => false;

  @override
  Future<void> install(void Function(double? fraction) onProgress) async {
    installs++;
  }

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
