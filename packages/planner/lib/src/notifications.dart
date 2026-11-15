import 'recurrence.dart';
import 'task.dart';

enum PlannerNotificationKind { taskDue, briefingReady, reminder }

abstract interface class PlannerNotificationSettings {
  Future<bool> isEnabled(PlannerNotificationKind kind);
  Future<void> setEnabled(PlannerNotificationKind kind, bool enabled);
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<void> openSystemSettings();
  Future<QuietHours?> readQuietHours();
  Future<void> saveQuietHours(QuietHours? hours);
}

class QuietHours {
  QuietHours({required this.startMinute, required this.endMinute}) {
    if (startMinute < 0 ||
        startMinute >= 1440 ||
        endMinute < 0 ||
        endMinute >= 1440 ||
        startMinute == endMinute) {
      throw const FormatException('Choose different, valid quiet-hour times.');
    }
  }

  final int startMinute;
  final int endMinute;

  DateTime nextAllowed(DateTime time) {
    final minute = time.hour * 60 + time.minute;
    final overnight = endMinute < startMinute;
    final quiet = overnight
        ? minute >= startMinute || minute < endMinute
        : minute >= startMinute && minute < endMinute;
    if (!quiet) return time;
    return DateTime(
      time.year,
      time.month,
      time.day + (overnight && minute >= startMinute ? 1 : 0),
      endMinute ~/ 60,
      endMinute % 60,
    );
  }
}

class TaskDueNotice {
  const TaskDueNotice({
    required this.task,
    required this.time,
    this.reminder = false,
  });

  final PlannerTask task;
  final DateTime time;
  final bool reminder;
}

/// Date-only tasks use 09:00 local time on their scheduled day.
List<TaskDueNotice> upcomingTaskNotices(
  List<PlannerTask> records,
  DateTime now, {
  bool includeDue = true,
  bool includeReminders = false,
  QuietHours? quietHours,
}) {
  final notices = <(String, DateTime), TaskDueNotice>{};
  for (final task in expandTasks(records, now)) {
    if (task.done) continue;
    final day = DateTime.parse(task.day);
    final start = task.startMinute ?? 9 * 60;
    void add(int minute, {required bool reminder}) {
      final requested = DateTime(day.year, day.month, day.day, 0, minute);
      final time = quietHours?.nextAllowed(requested) ?? requested;
      if (time.isAfter(now)) {
        notices[(task.id, time)] = TaskDueNotice(
          task: task,
          time: time,
          reminder: reminder,
        );
      }
    }

    if (includeDue) add(start, reminder: false);
    final offset = task.reminderMinutes;
    if (includeReminders && offset != null) {
      add(start - offset, reminder: true);
    }
  }
  return notices.values.toList()..sort((a, b) {
    final time = a.time.compareTo(b.time);
    return time == 0 ? a.task.id.compareTo(b.task.id) : time;
  });
}
