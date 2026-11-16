import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';
import 'package:planner_ui/planner_ui.dart';

void main() {
  test('Backup round-trips recurring records and validated preferences', () {
    final now = DateTime(2026, 11, 15, 9);
    final tasks = [
      PlannerTask(
        id: 'series',
        title: 'Water plants',
        day: '2026-11-15',
        repeat: RepeatRule(frequency: RepeatFrequency.daily),
        reminderMinutes: 15,
      ),
    ];
    final today = expandTasks(tasks, now).first;
    saveTaskRecord(tasks, today.toggleDone(dayKey(now)));
    final model = Uri.parse(
      'https://huggingface.co/example/model/resolve/main/model.gguf',
    );
    final snapshot = PlannerBackupSnapshot(
      createdAt: now,
      tasks: tasks,
      preferences: {
        PlannerPreferenceKeys.briefingFocus: 'Deadlines',
        PlannerPreferenceKeys.briefingTimes: jsonEncode(
          BriefingSchedule(morning: 480, midday: 750, evening: 1110).toJson(),
        ),
        '${PlannerPreferenceKeys.toolPrefix}draft_email': true,
        PlannerPreferenceKeys.quietHours: '[1320,420]',
      },
      models: ModelCatalogPreferences(active: model, sources: {model}),
    );
    final restored = PlannerBackupSnapshot.decode(snapshot.encode());

    expect(restored.preferences, snapshot.preferences);
    expect(restored.models?.active, model);
    expect(restored.tasks.first.reminderMinutes, 15);
    expect(expandTasks(restored.tasks, now).first.done, isTrue);

    final invalid = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
    (invalid['settings'] as Map)['planner.tasks.v1'] = 'invalid';
    expect(
      () => PlannerBackupSnapshot.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
    (invalid['settings'] as Map).remove('planner.tasks.v1');
    (invalid['tasks'] as List).add((invalid['tasks'] as List).first);
    expect(
      () => PlannerBackupSnapshot.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
  });

  testWidgets(
    'Import preview leaves tasks unchanged until restore is confirmed',
    (tester) async {
      final store = MemoryTaskStore([
        const PlannerTask(id: 'old', title: 'Current task', day: '2026-11-15'),
      ]);
      final backup = _Backup(store);
      await tester.pumpWidget(
        PlannerApp(
          store: store,
          assistant: _OffAssistant(),
          backup: backup,
          initialTab: 1,
          clock: () => DateTime(2026, 11, 15, 9),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tool settings'));
      await tester.pumpAndSettle();

      final import = find.text('Import backup');
      await tester.ensureVisible(import);
      await tester.pumpAndSettle();
      await tester.tap(import);
      await tester.pumpAndSettle();
      expect(find.text('Preview backup'), findsOneWidget);
      expect(find.text('Restored task'), findsOneWidget);
      expect(backup.restores, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await store.read()).single.title, 'Current task');

      await tester.tap(import);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();
      expect(backup.restores, 1);
      expect(find.text('Restored task'), findsOneWidget);
      expect(find.text('Current task'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _Backup implements PlannerBackup {
  _Backup(this._store);

  final TaskStore _store;
  int restores = 0;

  @override
  Future<bool> exportFile() async => true;

  @override
  Future<PlannerBackupSnapshot> pickFile() async => PlannerBackupSnapshot(
    createdAt: DateTime(2026, 11, 15),
    tasks: const [
      PlannerTask(id: 'new', title: 'Restored task', day: '2026-11-15'),
    ],
    preferences: const {},
  );

  @override
  Future<void> restore(PlannerBackupSnapshot snapshot) async {
    restores++;
    await _store.save(snapshot.tasks);
  }
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
