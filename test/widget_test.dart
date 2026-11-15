import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:planner_ui/previews.dart';

void main() {
  testWidgets('Navigates between the briefing and the task list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(briefingPreview());
    await tester.pumpAndSettle();
    expect(find.text('Daily Briefing'), findsOneWidget);

    expect(find.text('Tasks & Tools'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Tasks & Tools'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Tasks & Tools').hitTestable(), findsOneWidget);
    expect(find.text('Briefing'), findsNothing);
    expect(find.text('Review design tokens with team'), findsOneWidget);

    await tester.tap(find.text('3 sub-steps'));
    await tester.pumpAndSettle();
    expect(find.text('Verify contrast for surface tint'), findsOneWidget);

    await tester.tap(find.byTooltip('Complete Review design tokens with team'));
    await tester.pumpAndSettle();
    expect(find.text('Review design tokens with team'), findsNothing);
    expect(find.text('Completed · 3'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Creates and deletes a task from the editor', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(tasksPreview());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Task name'),
      'Pick up groceries',
    );
    await tester.ensureVisible(find.text('Save task'));
    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();

    final title = find.text('Pick up groceries');
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete task'));
    await tester.tap(find.text('Delete task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(title, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Task filters distinguish origin and persist across tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(tasksPreview());
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI suggested'));
    await tester.pumpAndSettle();
    expect(find.text('Review design tokens with team'), findsNothing);

    await tester.tap(find.text('Tool actions'));
    await tester.pumpAndSettle();
    expect(find.text('Finalize the on-device benchmark'), findsOneWidget);
    expect(find.text('Review design tokens with team'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Briefing'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Tasks & Tools'));
    await tester.pumpAndSettle();
    final filter = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Tool actions'),
    );
    expect(filter.selected, isTrue);
    expect(find.text('Finalize the on-device benchmark'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Completed tasks can be edited, canceled, and reopened', (
    tester,
  ) async {
    await tester.pumpWidget(tasksPreview());
    await tester.pumpAndSettle();
    final completed = find.text('Completed · 2');
    await tester.ensureVisible(completed);
    await tester.tap(completed);
    await tester.pumpAndSettle();

    final original = find.text('Weekly sync with Core Engineering');
    await tester.ensureVisible(original);
    await tester.tap(original);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Renamed weekly sync',
    );
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(original, findsOneWidget);
    expect(find.text('Renamed weekly sync'), findsNothing);

    final reopen = find.byTooltip('Reopen Weekly sync with Core Engineering');
    await tester.ensureVisible(reopen);
    await tester.tap(reopen);
    await tester.pumpAndSettle();
    expect(find.text('Completed · 1'), findsOneWidget);
    expect(
      find.byTooltip('Complete Weekly sync with Core Engineering'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Voice expands the dock and lets users retry and edit before submitting',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(tasksPreview());
      await tester.pumpAndSettle();

      final bubble = find.byKey(const ValueKey('voice-bubble'));
      final resting = tester.getRect(bubble);
      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('listening-wave')), findsOneWidget);
      final expanded = tester.getRect(bubble);
      expect(expanded.right, resting.right);
      expect(expanded.width, greaterThan(resting.width + 80));
      expect(
        find.bySemanticsLabel('Planner sections').hitTestable(),
        findsNothing,
      );
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byKey(const ValueKey('listening-wave')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('listening-wave')), findsNothing);
      expect(tester.getSize(bubble).width, resting.width);
      expect(find.text('Review transcript'), findsOneWidget);
      expect(find.text('Add a 15-minute break.'), findsOneWidget);
      expect(find.text('Take a break'), findsNothing);

      await tester.tap(find.text('Record again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('listening-wave')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('listening-wave')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'Add a 15-minute break before lunch.',
      );
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(find.text('Review transcript'), findsNothing);
      expect(find.text('Take a break'), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text('Completed · 2')).dy,
        lessThan(tester.getTopLeft(find.byIcon(Icons.mic_none_rounded)).dy),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
