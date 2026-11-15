import 'dart:io';

import 'package:planner/planner.dart';
import 'package:planner_assistant/planner_assistant.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/check_botpsy.dart <model directory | --download>',
    );
    exitCode = 64;
    return;
  }
  final temp = args.single == '--download'
      ? await Directory.systemTemp.createTemp('cameron-botpsy-')
      : null;
  final model = BotPsyAssistant(
    modelDirectory: () async => temp?.path ?? args.single,
  );
  final now = DateTime(2026, 11, 15, 9);
  final store = MemoryTaskStore();
  final tools = PlannerTools();

  try {
    if (temp != null) {
      stdout.writeln('Downloading and verifying BotPsy...');
      await model.install((_) {});
    }

    final reply = await model.ask(
      'Add a high priority task to review design tokens tomorrow at 10:30 for 45 minutes.',
      tasks: const [],
      now: now,
    );
    await tools.apply(reply.calls, store: store, currentTasks: [], now: now);
    final tasks = await store.read();
    if (tasks.length != 1 ||
        tasks.single.day != '2026-11-16' ||
        tasks.single.startMinute != 630 ||
        tasks.single.duration != 45 ||
        tasks.single.priority != TaskPriority.high) {
      throw StateError(
        'Unexpected task: ${tasks.map((task) => task.toJson()).toList()}',
      );
    }
    stdout.writeln('Created ${tasks.single.toJson()}');

    final message = await model.ask(
      'Draft an SMS to +12025550123 saying I am running 10 minutes late.',
      tasks: tasks,
      now: now,
      deviceTools: [smsTool],
    );
    final result = await tools.apply(
      message.calls,
      store: store,
      currentTasks: tasks,
      now: now,
      deviceTools: [smsTool],
    );
    if (result.drafts.length != 1 ||
        result.drafts.single.tool != smsTool ||
        result.drafts.single.arguments['phone'] != '+12025550123' ||
        result.drafts.single.arguments['body']?.contains('10 minutes') !=
            true) {
      throw StateError('Unexpected message response: ${message.text}');
    }
    stdout.writeln('Prepared an SMS draft.');

    final summary = await model.ask(
      'What is my first scheduled task on Monday?',
      tasks: tasks,
      now: now,
      readOnly: true,
    );
    if (summary.calls.isNotEmpty ||
        !summary.text.toLowerCase().contains('design tokens')) {
      throw StateError('Unexpected summary: ${summary.text}');
    }
    stdout.writeln('Answered a read-only schedule question.');
  } finally {
    await model.dispose();
    await temp?.delete(recursive: true);
  }
}
