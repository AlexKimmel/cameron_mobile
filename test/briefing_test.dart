import 'package:flutter_test/flutter_test.dart';
import 'package:planner/planner.dart';

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
}

class _Store implements BriefingStore {
  final _summaries = <String, String>{};

  @override
  Future<String?> read(BriefingSlot slot) async => _summaries[slot.id];

  @override
  Future<void> save(BriefingSlot slot, String summary) async {
    _summaries[slot.id] = summary;
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
