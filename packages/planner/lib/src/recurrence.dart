import 'recurrence_rule.dart';
import 'task.dart';

/// Stored tasks include series definitions and explicitly edited occurrences.
/// This view adds generated occurrences and keeps saved history visible.
List<PlannerTask> expandTasks(List<PlannerTask> records, DateTime now) {
  final visible = <PlannerTask>[];
  final series = {
    for (final task in records)
      if (task.repeat != null) task.id: task,
  };
  final exceptions = {
    for (final task in records)
      if (task.occurrence != null) task.id: task,
  };
  for (final task in records) {
    if (task.repeat == null && !task.skipped) visible.add(task);
  }
  final first = DateTime.utc(now.year, now.month, now.day - 14);
  final last = DateTime.utc(now.year, now.month, now.day + 30);
  for (final template in series.values) {
    final start = DateTime.parse(template.day);
    for (final date in template.repeat!.from(start, first)) {
      final day = dayKey(date);
      final id = _occurrenceId(template.id, day);
      if (exceptions.containsKey(id)) continue;
      visible.add(_occurrence(template, day));
      if (date.isAfter(last)) break;
    }
  }

  return visible;
}

PlannerTask? findTaskRecord(List<PlannerTask> records, String id) {
  for (final task in records) {
    if (task.id == id) return task.skipped ? null : task;
  }
  if (!id.startsWith('series:')) return null;
  final separator = id.lastIndexOf(':');
  if (separator <= 'series:'.length) return null;
  final seriesId = id.substring('series:'.length, separator);
  final day = id.substring(separator + 1);
  final date = DateTime.tryParse(day);
  if (date == null || dayKey(date) != day) return null;
  for (final task in records) {
    if (task.id != seriesId || task.repeat == null) continue;
    final first = task.repeat!.from(DateTime.parse(task.day), date).firstOrNull;
    return first != null && dayKey(first) == day
        ? _occurrence(task, day)
        : null;
  }
  return null;
}

PlannerTask? taskSeries(List<PlannerTask> records, PlannerTask occurrence) {
  final seriesId = occurrence.occurrence?.seriesId;
  if (seriesId == null) return null;
  for (final task in records) {
    if (task.id == seriesId && task.repeat != null) return task;
  }
  return null;
}

void saveTaskRecord(List<PlannerTask> records, PlannerTask task) {
  final index = records.indexWhere((entry) => entry.id == task.id);
  if (index < 0) {
    records.add(task);
  } else {
    records[index] = task;
  }
}

void detachTaskOccurrences(List<PlannerTask> records, PlannerTask template) {
  for (var i = records.length - 1; i >= 0; i--) {
    final task = records[i];
    if (task.occurrence?.seriesId != template.id) continue;
    if (task.skipped) {
      records.removeAt(i);
    } else {
      records[i] = task.copyWith(occurrence: null);
    }
  }
}

String _occurrenceId(String seriesId, String day) => 'series:$seriesId:$day';

PlannerTask _occurrence(PlannerTask template, String day) => template.copyWith(
  id: _occurrenceId(template.id, day),
  day: day,
  repeat: null,
  completedOn: null,
  occurrence: TaskOccurrence(seriesId: template.id, originalDay: day),
  steps: [for (final step in template.steps) TaskStep(step.title)],
);
