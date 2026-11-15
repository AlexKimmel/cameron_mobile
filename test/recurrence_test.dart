import 'package:flutter_test/flutter_test.dart';
import 'package:planner/planner.dart';

void main() {
  test('Weekly repeat intervals honor weekdays and an inclusive end', () {
    final schedule = RepeatRule(
      frequency: RepeatFrequency.weekly,
      interval: 2,
      weekdays: {1, 4},
      until: '2026-11-19',
    );
    final dates = schedule
        .from(DateTime(2026, 11, 3), DateTime(2026, 11, 3))
        .map(dayKey);
    expect(dates, ['2026-11-05', '2026-11-16', '2026-11-19']);
  });

  test('Monthly tasks return to the original day after a shorter month', () {
    final dates = RepeatRule(frequency: RepeatFrequency.monthly)
        .from(DateTime(2026, 1, 31), DateTime(2026, 2, 1))
        .take(3)
        .map(dayKey);
    expect(dates, ['2026-02-28', '2026-03-31', '2026-04-30']);
  });

  test(
    'Occurrence edits and skips survive storage and do not change siblings',
    () {
      final now = DateTime(2026, 11, 15);
      final master = PlannerTask(
        id: 'daily',
        title: 'Water the plants',
        day: '2026-11-15',
        repeat: RepeatRule(
          frequency: RepeatFrequency.daily,
          until: '2026-11-17',
        ),
      );
      final records = [master];
      final dates = expandTasks(records, now);
      final first = dates.first.copyWith(
        title: 'Water the courtyard',
        day: '2026-11-16',
        completedOn: '2026-11-15',
      );
      saveTaskRecord(records, first);
      saveTaskRecord(records, dates.last.copyWith(skipped: true));
      final restored = [
        for (final task in records) PlannerTask.fromJson(task.toJson()),
      ];
      final visible = expandTasks(restored, now);

      expect(visible.map((task) => task.day), ['2026-11-16', '2026-11-16']);
      expect(visible.first.id, dates.first.id);
      expect(visible.first.done, isTrue);
      expect(visible.last.done, isFalse);
      expect(visible.last.title, master.title);
      expect(findTaskRecord(restored, dates.last.id), isNull);
    },
  );

  test(
    'Assistant tools create repeats and reschedule one or the whole series',
    () async {
      final now = DateTime(2026, 11, 15);
      final store = MemoryTaskStore();
      final tools = PlannerTools();
      Future<ToolResult> apply(PlannerToolCall call) async => tools.apply(
        [call],
        currentTasks: await store.read(),
        store: store,
        now: now,
      );

      final created = await apply(
        const PlannerToolCall(PlannerTools.createTask, {
          'title': 'Water the plants',
          'day': '2026-11-15',
          'repeat_frequency': 'daily',
          'repeat_interval': 2,
          'repeat_until': '2026-11-21',
        }),
      );
      final instances = expandTasks(created.tasks, now);
      expect(instances.map((task) => task.day), [
        '2026-11-15',
        '2026-11-17',
        '2026-11-19',
        '2026-11-21',
      ]);

      final one = await apply(
        PlannerToolCall(PlannerTools.rescheduleTask, {
          'id': instances.first.id,
          'day': '2026-11-16',
        }),
      );
      expect(findTaskRecord(one.tasks, instances.first.id)?.day, '2026-11-16');
      expect(one.tasks.first.day, '2026-11-15');

      final series = await apply(
        PlannerToolCall(PlannerTools.rescheduleTask, {
          'id': instances[1].id,
          'day': '2026-11-18',
          'scope': 'series',
        }),
      );
      expect(series.tasks.first.day, '2026-11-18');
      expect(expandTasks(series.tasks, now).map((task) => task.day), [
        '2026-11-16',
        '2026-11-18',
        '2026-11-20',
      ]);

      final changed = await apply(
        PlannerToolCall(PlannerTools.setRepeat, {
          'id': expandTasks(series.tasks, now).last.id,
          'repeat_frequency': 'weekly',
          'repeat_weekdays': [3],
        }),
      );
      expect(changed.tasks.first.repeat?.frequency, RepeatFrequency.weekly);
      expect(changed.tasks.first.repeat?.weekdays, {DateTime.wednesday});
    },
  );
}
