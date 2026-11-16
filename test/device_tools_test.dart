import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';
import 'package:planner_ui/planner_ui.dart';

void main() {
  testWidgets('Only enabled tools can reach the handoff after review', (
    tester,
  ) async {
    final settings = _ToolStore();
    final assistant = _DraftAssistant();
    final opened = <DeviceToolDraft>[];
    await tester.pumpWidget(
      PlannerApp(
        store: MemoryTaskStore(),
        assistant: assistant,
        toolStore: settings,
        openDeviceTool: (draft) async {
          opened.add(draft);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    Future<void> requestDraft() async {
      await tester.tap(find.bySemanticsLabel('Type a request'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Draft an email');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
    }

    Future<void> openSettings() async {
      await tester.tap(find.bySemanticsLabel('Tool settings'));
      await tester.pumpAndSettle();
    }

    final emailSwitch = find.widgetWithText(SwitchListTile, 'Email');

    await requestDraft();
    expect(find.text('Draft an email'), findsOneWidget);
    expect(find.text('Proposed actions'), findsOneWidget);
    expect(assistant.offeredTools, isEmpty);
    expect(find.text('Review actions'), findsNothing);
    expect(opened, isEmpty);
    if (find.text('Dismiss').evaluate().isNotEmpty) {
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
    }

    await openSettings();
    expect(tester.widget<SwitchListTile>(emailSwitch).value, isFalse);
    await tester.tap(emailSwitch);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await requestDraft();
    expect(assistant.offeredTools, [emailTool]);
    expect(find.text('person+work@example.com'), findsOneWidget);
    expect(find.text('Meeting update'), findsOneWidget);
    expect(find.text('I’ll be there at 11.'), findsOneWidget);
    expect(opened, isEmpty);

    await tester.tap(find.text('Open email app'));
    await tester.pumpAndSettle();
    expect(opened.single.tool, emailTool);
    expect(opened.single.arguments['email'], 'person+work@example.com');

    await openSettings();
    expect(tester.widget<SwitchListTile>(emailSwitch).value, isTrue);
    await tester.tap(emailSwitch);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await requestDraft();
    expect(assistant.offeredTools, isEmpty);
    expect(find.text('Review actions'), findsNothing);
    expect(opened, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Assistant completion uses the actual task title and asks for review',
    (tester) async {
      final settings = _ToolStore();
      await settings.setEnabled(taskCompletionTool.name, true);
      final store = MemoryTaskStore([
        const PlannerTask(
          id: 'task-1',
          title: 'Book a checkup',
          day: '2026-11-15',
        ),
      ]);
      await tester.pumpWidget(
        PlannerApp(
          clock: () => DateTime(2026, 11, 15, 9),
          store: store,
          assistant: _DraftAssistant(
            PlannerToolCall(taskCompletionTool.name, {'id': 'task-1'}),
          ),
          toolStore: settings,
        ),
      );
      await tester.pumpAndSettle();

      await _askWithoutAccept(tester, 'Mark my checkup task complete');
      expect(find.text('Proposed actions'), findsOneWidget);
      expect(find.text('complete task'), findsOneWidget);
      expect(find.text('Mark complete'), findsNothing);
      expect((await store.read()).single.done, isFalse);
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();

      await _ask(tester, 'Mark my checkup task complete');
      expect(find.text('Review actions'), findsOneWidget);
      expect(find.text('Book a checkup'), findsWidgets);
      expect(find.text('task-1'), findsNothing);
      expect((await store.read()).single.done, isFalse);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect((await store.read()).single.done, isFalse);

      await _ask(tester, 'Mark my checkup task complete');
      await tester.tap(find.text('Mark complete'));
      await tester.pumpAndSettle();
      expect((await store.read()).single.completedOn, '2026-11-15');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect((await store.read()).single.done, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('An assistant-created task can be undone from its confirmation', (
    tester,
  ) async {
    final store = MemoryTaskStore();
    await tester.pumpWidget(
      PlannerApp(
        store: store,
        assistant: _DraftAssistant(
          const PlannerToolCall(PlannerTools.createTask, {
            'title': 'Make a plan',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _ask(tester, 'Add a plan');
    expect((await store.read()).single.title, 'Make a plan');

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await store.read(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Calendar access and reading wait for the approved date', (
    tester,
  ) async {
    final settings = _ToolStore();
    await settings.setEnabled(calendarReadTool.name, true);
    final calendar = _Calendar();
    await tester.pumpWidget(
      PlannerApp(
        store: MemoryTaskStore(),
        assistant: _DraftAssistant(
          PlannerToolCall(calendarReadTool.name, {'day': '2026-11-17'}),
        ),
        toolStore: settings,
        calendar: calendar,
      ),
    );
    await tester.pumpAndSettle();

    await _ask(tester, 'Read my calendar for Nov 17');
    expect(find.text('2026-11-17'), findsOneWidget);
    expect(calendar.requests, 0);
    expect(calendar.daysRead, isEmpty);

    await tester.tap(find.text('Read calendar'));
    await tester.pumpAndSettle();
    expect(calendar.requests, 1);
    expect(calendar.daysRead, isEmpty);
    expect(find.textContaining('Calendar access is off'), findsOneWidget);

    calendar.canGrant = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calendar.requests, 2);
    expect(calendar.daysRead, [DateTime(2026, 11, 17)]);
    expect(find.text('Calendar event title'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Review actions'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Shows inference progress and retries the same prompt after failure',
    (tester) async {
      final assistant = _RetryAssistant();
      await tester.pumpWidget(
        PlannerApp(store: MemoryTaskStore(), assistant: assistant),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Type a request'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Review my plan');
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Generating response'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ai-loading-indicator')),
        findsOneWidget,
      );

      assistant.first.completeError(StateError('Model failed'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not generate an assistant response.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(assistant.prompts, ['Review my plan', 'Review my plan']);
      expect(find.text('Your plan is clear.'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Dismissing inference ignores its late response', (tester) async {
    final assistant = _RetryAssistant();
    await tester.pumpWidget(
      PlannerApp(store: MemoryTaskStore(), assistant: assistant),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Type a request'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Review my plan');
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Thinking…'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-loading-indicator')),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('Dismiss response'));
    await tester.pumpAndSettle();
    assistant.first.complete(const AssistantReply(text: 'A late response'));
    await tester.pumpAndSettle();

    expect(find.text('Review assistant response'), findsNothing);
    expect(find.text('A late response'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Retry selects a model only after the download succeeds', (
    tester,
  ) async {
    final library = _RetryModelLibrary();
    await tester.pumpWidget(
      PlannerApp(
        store: MemoryTaskStore(),
        assistant: _DraftAssistant(),
        modelLibrary: library,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Assistant models'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(find.text('Downloading Test model'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .4,
    );
    library.first.completeError(
      const FormatException('Download was interrupted.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Download was interrupted.'), findsOneWidget);
    expect(library.selected, isFalse);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(library.downloads, 2);
    expect(library.selected, isTrue);
    expect(find.text('In use'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('Prepares validated phone and SMS drafts from the tool definitions', () {
    expect(phoneCallTool.draft({'phone': '+1 (202) 555-0123'}).arguments, {
      'phone': '+12025550123',
    });
    expect(
      smsTool.draft({'phone': '2025550123', 'body': 'On my way'}).arguments,
      {'phone': '2025550123', 'body': 'On my way'},
    );
    expect(
      () => emailTool.draft({
        'email': 'a@example.com,b@example.com',
        'body': 'Hi',
      }),
      throwsFormatException,
    );
  });
}

class _ToolStore implements DeviceToolStore {
  final _enabled = <String>{};

  @override
  Future<bool> isEnabled(String name) async => _enabled.contains(name);

  @override
  Future<void> setEnabled(String name, bool enabled) async {
    if (enabled) {
      _enabled.add(name);
    } else {
      _enabled.remove(name);
    }
  }
}

Future<void> _ask(WidgetTester tester, String prompt) async {
  await _askWithoutAccept(tester, prompt);
  await tester.tap(find.text('Accept'));
  await tester.pumpAndSettle();
}

Future<void> _askWithoutAccept(WidgetTester tester, String prompt) async {
  await tester.tap(find.bySemanticsLabel('Type a request'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField), prompt);
  await tester.tap(find.text('Send'));
  await tester.pumpAndSettle();
}

class _Calendar implements DeviceCalendar {
  int requests = 0;
  bool canGrant = false;
  bool _granted = false;
  final daysRead = <DateTime>[];

  @override
  Future<bool> hasAccess() async => _granted;

  @override
  Future<bool> requestAccess() async {
    requests++;
    _granted = canGrant;
    return _granted;
  }

  @override
  Future<void> openSettings() async {}

  @override
  Future<List<CalendarEvent>> eventsOn(DateTime day) async {
    daysRead.add(day);
    return [
      CalendarEvent(
        title: 'Calendar event title',
        start: day.add(const Duration(hours: 9)),
        end: day.add(const Duration(hours: 10)),
        allDay: false,
      ),
    ];
  }
}

class _DraftAssistant implements PlannerAssistant {
  _DraftAssistant([this.call]);

  final PlannerToolCall? call;
  List<DeviceTool> offeredTools = const [];

  @override
  bool get supported => true;

  @override
  Future<bool> isInstalled() async => true;

  @override
  Future<void> install(void Function(double?) onProgress) async {}

  @override
  Future<AssistantReply> ask(
    String prompt, {
    required List<PlannerTask> tasks,
    required DateTime now,
    bool readOnly = false,
    List<DeviceTool> deviceTools = const [],
  }) async {
    offeredTools = deviceTools;
    if (call case final requested?) return AssistantReply(calls: [requested]);
    // Return a call even when the tool is off to exercise the execution gate.
    return AssistantReply(
      calls: [
        PlannerToolCall(emailTool.name, {
          'email': 'person+work@example.com',
          'subject': 'Meeting update',
          'body': 'I’ll be there at 11.',
        }),
      ],
    );
  }

  @override
  Future<void> dispose() async {}
}

class _RetryAssistant extends _DraftAssistant {
  final first = Completer<AssistantReply>();
  final prompts = <String>[];

  @override
  Future<AssistantReply> ask(
    String prompt, {
    required List<PlannerTask> tasks,
    required DateTime now,
    bool readOnly = false,
    List<DeviceTool> deviceTools = const [],
  }) async {
    prompts.add(prompt);
    if (prompts.length == 1) return first.future;
    return const AssistantReply(text: 'Your plan is clear.');
  }
}

class _RetryModelLibrary implements AssistantModelLibrary {
  final source = Uri.parse(
    'https://huggingface.co/example/tool/resolve/main/model.gguf',
  );
  final first = Completer<void>();
  int downloads = 0;
  bool downloaded = false;
  bool selected = false;

  @override
  Future<List<AssistantModel>> listModels() async => [
    AssistantModel(
      source: source,
      name: 'Test model',
      active: selected,
      downloaded: downloaded,
    ),
  ];

  @override
  Future<void> downloadModel(
    Uri source,
    void Function(double?) onProgress,
  ) async {
    downloads++;
    onProgress(.4);
    if (downloads == 1) await first.future;
    downloaded = true;
  }

  @override
  Future<void> selectModel(Uri source) async => selected = true;

  @override
  Future<void> addModel(String url) async {}

  @override
  Future<void> deleteDownload(Uri source) async {}
}
