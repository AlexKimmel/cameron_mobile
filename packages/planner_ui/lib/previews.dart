import 'dart:async';

import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';

import 'src/planner_app.dart';
import 'src/sheets.dart';

@Preview(name: 'Daily Briefing', group: 'Cameron', size: Size(390, 844))
Widget briefingPreview() => _preview(0);

@Preview(name: 'Tasks & Tools', group: 'Cameron', size: Size(390, 844))
Widget tasksPreview() => _preview(1);

PlannerApp _preview(int tab) => PlannerApp(
  store: MemoryTaskStore(_tasks),
  assistant: _PreviewAssistant(),
  dictation: _PreviewDictation(),
  initialTab: tab,
  clock: () => DateTime(2026, 11, 15, 9),
  previewSummary: 'Review the design tokens this morning. You have 2h 45m set aside for design, testing, and roadmap work.',
  previewActivities: const [
    'Moved “Finalize the on-device benchmark” to today',
    'Added three sub-steps to the design token review',
  ],
);

const _day = '2026-11-15';
const _tasks = [
  PlannerTask(
    id: 'design',
    title: 'Review design tokens with team',
    day: _day,
    notes: 'Align slate and terracotta semantic scales across Android and web.',
    priority: TaskPriority.high,
    startMinute: 600,
    duration: 45,
    steps: [
      TaskStep('Verify contrast for surface tint', done: true),
      TaskStep('Export token JSON to the on-device package'),
      TaskStep('Sync with the mobile design lead'),
    ],
  ),
  PlannerTask(
    id: 'benchmark',
    title: 'Finalize the on-device benchmark',
    day: _day,
    notes: 'Measure BotPsy token throughput under thermal throttling.',
    origin: TaskOrigin.tool,
    startMinute: 900,
    duration: 60,
  ),
  PlannerTask(
    id: 'roadmap',
    title: 'Synthesize the Q3 design roadmap',
    day: _day,
    notes: 'Group feature backlogs into on-device UX milestones.',
    origin: TaskOrigin.assistant,
    duration: 60,
    startMinute: 675,
  ),
  PlannerTask(
    id: 'weekly',
    title: 'Weekly sync with Core Engineering',
    day: _day,
    completedOn: _day,
  ),
  PlannerTask(
    id: 'audit',
    title: 'Audit model context-length parameters',
    day: _day,
    completedOn: _day,
  ),
];

class _PreviewAssistant implements PlannerAssistant {
  @override
  bool get supported => true;

  @override
  Future<bool> isInstalled() async => true;

  @override
  Future<void> install(void Function(double? fraction) onProgress) async {}

  @override
  Future<AssistantReply> ask(
    String prompt, {
    required List<PlannerTask> tasks,
    required DateTime now,
    bool readOnly = false,
    List<DeviceTool> deviceTools = const [],
  }) async {
    if (readOnly) {
      final count = tasks
          .where((task) => task.day == dayKey(now) && !task.done)
          .length;
      return AssistantReply(text: 'You have $count open tasks today.');
    }
    if (prompt.startsWith('Add a 15-minute break')) {
      return const AssistantReply(
        calls: [
          PlannerToolCall(PlannerTools.createTask, {
            'title': 'Take a break',
            'time': '10:45',
            'duration_minutes': 15,
          }),
        ],
      );
    }
    return const AssistantReply(text: 'This preview uses sample tasks.');
  }

  @override
  Future<void> dispose() async {}
}

class _PreviewDictation implements PlannerDictation {
  Timer? _sample;
  VoidCallback? _finish;

  @override
  Future<bool> start({
    required ValueChanged<String> onText,
    required ValueChanged<double> onLevel,
    required ValueChanged<String?> onDone,
  }) async {
    _finish = () {
      onText('Add a 15-minute break.');
      onDone(null);
    };
    _sample = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      onLevel((timer.tick % 5 + 2) / 7);
      if (timer.tick == 20) unawaited(stop());
    });
    return true;
  }

  @override
  Future<void> stop() async {
    final finish = _finish;
    await cancel();
    finish?.call();
  }

  @override
  Future<void> cancel() async {
    _sample?.cancel();
    _finish = null;
  }
}
