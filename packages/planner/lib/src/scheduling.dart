import 'recurrence.dart';
import 'task.dart';

class ScheduleConflict {
  const ScheduleConflict({
    required this.task,
    required this.sessions,
    required this.suggestedMinutes,
  });

  final PlannerTask task;
  final List<PlannerTask> sessions;
  final List<int> suggestedMinutes;
}

bool scheduleChanged(PlannerTask? original, PlannerTask proposed) {
  if (original == null) return true;
  final before = original.repeat;
  final after = proposed.repeat;
  return original.day != proposed.day ||
      original.startMinute != proposed.startMinute ||
      original.duration != proposed.duration ||
      before?.frequency != after?.frequency ||
      before?.interval != after?.interval ||
      before?.until != after?.until ||
      (before != null &&
          after != null &&
          (before.weekdays.length != after.weekdays.length ||
              !before.weekdays.containsAll(after.weekdays)));
}

ScheduleConflict? inspectSchedule(
  List<PlannerTask> records,
  PlannerTask task,
  DateTime now,
) {
  final proposed = task.startMinute;
  if (proposed == null || task.duration <= 0 || task.done) return null;

  final others = records.where((entry) => entry.id != task.id).toList();
  final occurrences = task.repeat == null
      ? [task]
      : [
          for (final occurrence in expandTasks([...others, task], now))
            if (occurrence.occurrence?.seriesId == task.id &&
                occurrence.day.compareTo(dayKey(now)) >= 0 &&
                !others.any((saved) => saved.id == occurrence.id))
              occurrence,
        ];
  final windows = [
    for (final candidate in occurrences)
      (
        day: _dayStart(candidate.day),
        others: [
          for (final other in expandTasks(
            others,
            DateTime.parse(candidate.day),
          ))
            if (other.id != candidate.id &&
                !other.done &&
                other.startMinute != null &&
                other.duration > 0 &&
                (_dayStart(other.day) - _dayStart(candidate.day)).abs() <= 1440)
              other,
        ],
      ),
  ];

  List<PlannerTask> overlapping(int startMinute) {
    final result = <String, PlannerTask>{};
    for (final window in windows) {
      final start = window.day + startMinute;
      final end = start + task.duration;
      for (final other in window.others) {
        final otherStart = _dayStart(other.day) + other.startMinute!;
        if (start < otherStart + other.duration && otherStart < end) {
          result[other.id] = other;
        }
      }
    }
    return result.values.toList();
  }

  final conflicts = overlapping(proposed);
  if (conflicts.isEmpty) return null;

  final suggested = <int>[];
  final minStart = occurrences.any((entry) => entry.day == dayKey(now))
      ? now.hour * 60 + now.minute + 1
      : 0;
  final latest = 1440 - task.duration;
  final first = (minStart + 14) ~/ 15 * 15;
  final slots = <int>{
    for (var minute = first; minute <= latest; minute += 15) minute,
    for (final window in windows)
      for (final other in window.others)
        _dayStart(other.day) + other.startMinute! + other.duration - window.day,
  }.where((minute) => minute >= minStart && minute <= latest).toList()..sort();
  final order = [
    ...slots.where((minute) => minute >= proposed),
    ...slots.where((minute) => minute < proposed).toList().reversed,
  ];
  for (final minute in order) {
    if (overlapping(minute).isEmpty) suggested.add(minute);
    if (suggested.length == 3) break;
  }

  return ScheduleConflict(
    task: task,
    sessions: conflicts,
    suggestedMinutes: suggested,
  );
}

int _dayStart(String key) {
  final date = DateTime.parse(key);
  return DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
      60000;
}
