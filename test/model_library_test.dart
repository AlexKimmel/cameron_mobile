import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planner/planner.dart';
import 'package:planner_assistant/planner_assistant.dart';

void main() {
  test('A tool-capable model may include blank optional task notes', () async {
    final result = await PlannerTools().apply(
      const [
        PlannerToolCall(PlannerTools.createTask, {
          'title': 'Read',
          'notes': '',
        }),
      ],
      store: MemoryTaskStore(),
      currentTasks: [],
      now: DateTime(2026, 11, 15),
    );
    expect(result.tasks.single.notes, isEmpty);
  });

  test('Normalizes and persists public GGUF sources without duplicates', () async {
    final directory = await Directory.systemTemp.createTemp('cameron-models-');
    addTearDown(() => directory.delete(recursive: true));

    BotPsyAssistant assistant() =>
        BotPsyAssistant(modelDirectory: () async => directory.path);

    final library = assistant().models!;
    await library.addModel(
      'https://huggingface.co/example/tools/blob/main/tools.gguf?download=true',
    );
    await library.addModel(
      'https://huggingface.co/example/tools/resolve/main/tools.gguf',
    );

    final reopened = assistant().models!;
    final options = await reopened.listModels();
    final custom = options.singleWhere((model) => model.name == 'tools.gguf');
    expect(custom.source.path, '/example/tools/resolve/main/tools.gguf');
    expect(custom.source.hasQuery, isFalse);
    expect(custom.downloaded, isFalse);
    expect(options.singleWhere((model) => model.active).name, 'BotPsy-0.8B');
    await expectLater(
      reopened.selectModel(custom.source),
      throwsFormatException,
    );
    await expectLater(
      reopened.addModel(
        'https://example.org/example/tools/resolve/main/tools.gguf',
      ),
      throwsFormatException,
    );
    await expectLater(
      reopened.addModel(
        'https://huggingface.co/example/tools/resolve/main/tools-00001-of-00002.gguf',
      ),
      throwsFormatException,
    );
  });

  test('Recognizes and can delete a legacy BotPsy download', () async {
    final directory = await Directory.systemTemp.createTemp('cameron-models-');
    addTearDown(() => directory.delete(recursive: true));
    final original = File('${directory.path}/botpsy-0.8b-q4_k_m-imat.gguf');
    final download = await original.open(mode: FileMode.write);
    await download.truncate(529296960);
    await download.close();

    final assistant = BotPsyAssistant(
      modelDirectory: () async => directory.path,
    );
    final library = assistant.models!;
    expect(await assistant.isInstalled(), isTrue);
    final active = (await library.listModels()).singleWhere(
      (option) => option.active,
    );
    expect(active.downloaded, isTrue);
    await library.deleteDownload(active.source);
    expect(await original.exists(), isFalse);
    expect(await assistant.isInstalled(), isFalse);
  });
}
