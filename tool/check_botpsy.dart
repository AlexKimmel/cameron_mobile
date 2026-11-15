import 'dart:io';

import 'package:planner/planner.dart';
import 'package:planner_assistant/planner_assistant.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1 && !(args.length == 2 && args.first == '--download')) {
    stderr.writeln(
      'Usage: dart run tool/check_botpsy.dart <model directory | --download [Hugging Face GGUF URL]>',
    );
    exitCode = 64;
    return;
  }
  final temp = args.first == '--download'
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
      stdout.writeln('Downloading and verifying assistant model...');
      if (args.length == 2) {
        final library = model.models;
        if (library == null) {
          throw StateError('Model downloads are unavailable.');
        }
        await library.addModel(args.last);
        final path = Uri.parse(args.last).path
            .replaceFirst('/blob/', '/resolve/');
        final options = await library.listModels();
        final option = options.singleWhere(
          (entry) => entry.source.path == path,
        );
        await library.downloadModel(option.source, (_) {});
        await library.selectModel(option.source);
      } else {
        await model.install((_) {});
      }
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
      'What is my first scheduled task on Monday, 2026-11-16? Answer with the task title only.',
      tasks: tasks,
      now: now,
      readOnly: true,
    );
    if (summary.calls.isNotEmpty ||
        !summary.text.toLowerCase().contains('design tokens')) {
      throw StateError('Unexpected summary: ${summary.text}');
    }
    stdout.writeln('Answered a read-only schedule question.');

    final recurrence = await model.ask(
      'Create a daily repeating task titled Water the plants at 8:00, starting 2026-11-17 and ending 2026-11-19.',
      tasks: const [],
      now: now,
    );
    final recurring = await tools.apply(
      recurrence.calls,
      store: store,
      currentTasks: tasks,
      now: now,
    );
    final plantTask = recurring.tasks
        .where((task) => task.repeat != null)
        .singleOrNull;
    if (plantTask?.repeat?.frequency != RepeatFrequency.daily ||
        plantTask?.day != '2026-11-17' ||
        plantTask?.repeat?.until != '2026-11-19') {
      throw StateError(
        'Unexpected recurrence tool call: ${recurrence.calls.map((call) => call.arguments).toList()}',
      );
    }
    stdout.writeln('Created a recurring task with an end date.');
  } finally {
    await model.dispose();
    await temp?.delete(recursive: true);
  }
}
