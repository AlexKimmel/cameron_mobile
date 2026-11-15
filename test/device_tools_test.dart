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
      await tester.tap(find.byTooltip('Type a request'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Draft an email');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
    }

    Future<void> openSettings() async {
      await tester.tap(find.byTooltip('Tool settings'));
      await tester.pumpAndSettle();
    }

    final emailSwitch = find.widgetWithText(SwitchListTile, 'Email');

    await requestDraft();
    expect(assistant.offeredTools, isEmpty);
    expect(find.text('Review actions'), findsNothing);
    expect(opened, isEmpty);

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

class _DraftAssistant implements PlannerAssistant {
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
