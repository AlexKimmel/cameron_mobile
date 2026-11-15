import 'recurrence.dart';
import 'task.dart';

enum PlannerNotificationKind { taskDue, briefingReady }

abstract interface class PlannerNotificationSettings {
  Future<bool> isEnabled(PlannerNotificationKind kind);
  Future<void> setEnabled(PlannerNotificationKind kind, bool enabled);
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<void> openSystemSettings();
}

class TaskDueNotice {
  const TaskDueNotice({required this.task, required this.time});

  final PlannerTask task;
  final DateTime time;
}

/// Date-only tasks use 09:00 local time on their scheduled day.
List<TaskDueNotice> upcomingTaskNotices(
  List<PlannerTask> records,
  DateTime now,
) {
  final notices = <TaskDueNotice>[];
  for (final task in expandTasks(records, now)) {
    if (task.done) continue;
    final day = DateTime.parse(task.day);
    final minute = task.startMinute ?? 9 * 60;
    final time = DateTime(
      day.year,
      day.month,
      day.day,
      minute ~/ 60,
      minute % 60,
    );
    if (time.isAfter(now)) notices.add(TaskDueNotice(task: task, time: time));
  }
  notices.sort((a, b) {
    final time = a.time.compareTo(b.time);
    return time == 0 ? a.task.id.compareTo(b.task.id) : time;
  });
  return notices;
}
