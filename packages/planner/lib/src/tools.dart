import 'device_tools.dart';
import 'recurrence.dart';
import 'recurrence_rule.dart';
import 'scheduling.dart';
import 'task.dart';

class AssistantReply {
  const AssistantReply({this.text = '', this.calls = const []});

  final String text;
  final List<PlannerToolCall> calls;
}

class PlannerToolCall {
  const PlannerToolCall(this.name, this.arguments);

  final String name;
  final Map<String, Object?> arguments;
}

abstract interface class PlannerAssistant {
  bool get supported;
  Future<bool> isInstalled();
  Future<void> install(void Function(double? fraction) onProgress);
  Future<AssistantReply> ask(
    String prompt, {
    required List<PlannerTask> tasks,
    required DateTime now,
    bool readOnly = false,
    List<DeviceTool> deviceTools = const [],
  });
  Future<void> dispose();
}

class ToolResult {
  const ToolResult(
    this.tasks,
    this.activities,
    this.drafts, {
    this.cancelled = false,
  });

  final List<PlannerTask> tasks;

  final List<String> activities;
  final List<DeviceToolDraft> drafts;
  final bool cancelled;
}

class PlannerTools {
  static const createTask = 'create_task';
  static const completeTask = 'complete_task';
  static const rescheduleTask = 'reschedule_task';
  static const addStep = 'add_subtask';
  static const setRepeat = 'set_task_repeat';

  /// Applies planner changes as a single save. Device handoffs are returned
  /// as drafts for the UI to present to the user.
  Future<ToolResult> apply(
    List<PlannerToolCall> calls, {
    required TaskStore store,
    required List<PlannerTask> currentTasks,
    required DateTime now,
    List<DeviceTool> deviceTools = const [],
    bool approvedTaskCompletion = false,
    Future<int?> Function(ScheduleConflict)? reviewSchedule,
  }) async {
    final tasks = currentTasks.toList();
    final activities = <String>[];
    final drafts = <DeviceToolDraft>[];
    final scheduleChanges = <String>{};
    final available = {for (final tool in deviceTools) tool.name: tool};
    final today = dayKey(now);
    var changed = false;

    for (final call in calls) {
      final args = call.arguments;
      switch (call.name) {
        case createTask:
          final title = _text(args, 'title', 120);
          final day = _date(args['day'] ?? today);
          final repeat = _repeatRule(args, day);
          final duration = args['duration_minutes'] ?? 0;
          final priority = args['priority'] ?? 'normal';
          if (duration is! int || duration < 0 || duration > 1440) {
            throw const FormatException(
              'Choose a duration from 0 to 1440 minutes.',
            );
          }
          if (priority != 'high' && priority != 'normal') {
            throw const FormatException('Choose a normal or high priority.');
          }
          final task = PlannerTask(
            id: 'ai-${now.microsecondsSinceEpoch}-${tasks.length}',
            title: title,
            day: day,
            repeat: repeat,
            notes: _text(args, 'notes', 1000, optional: true),
            priority: TaskPriority.values.byName(priority as String),
            startMinute: args['time'] == null ? null : _time(args['time']),
            duration: duration,
            origin: TaskOrigin.assistant,
          );
          tasks.add(task);
          scheduleChanges.add(task.id);
          activities.add(
            repeat == null ? 'Added “$title”' : 'Added repeating task “$title”',
          );
          changed = true;
        case completeTask:
          final task = _task(tasks, args);
          if (task.repeat != null) {
            throw const FormatException('Choose one occurrence to complete.');
          }
          if (!approvedTaskCompletion) {
            final tool = available[call.name];
            if (tool == null) {
              throw const FormatException(
                'Enable Task completion in Tool settings.',
              );
            }
            drafts.add(tool.draft({'id': task.id}));
          } else if (!task.done) {
            saveTaskRecord(tasks, task.toggleDone(today));
            activities.add('Completed “${task.title}”');
            changed = true;
          } else {
            activities.add('“${task.title}” was already complete');
          }
        case rescheduleTask:
          final task = _task(tasks, args);
          final day = _date(args['day']);
          final time = args['time'];
          final scope = args['scope'] ?? 'occurrence';
          if (scope != 'occurrence' && scope != 'series') {
            throw const FormatException(
              'Choose one occurrence or the whole series.',
            );
          }
          final target = scope == 'series'
              ? taskSeries(tasks, task) ?? (task.repeat == null ? null : task)
              : task;
          if (target == null) {
            throw const FormatException('That task does not repeat.');
          }
          if (target.repeat != null && scope != 'series') {
            throw const FormatException(
              'Choose one occurrence or the whole series.',
            );
          }
          if (target.repeat?.until case final end?
              when end.compareTo(day) < 0) {
            throw const FormatException(
              'The repeat end date comes before the new start.',
            );
          }
          final moved = target.rescheduled(
            day,
            newStart: time == null ? null : _time(time),
            newOrigin: TaskOrigin.tool,
          );
          saveTaskRecord(tasks, moved);
          if (scheduleChanged(target, moved)) scheduleChanges.add(moved.id);
          activities.add(
            scope == 'series'
                ? 'Moved the start of “${task.title}” to $day'
                : 'Moved “${task.title}” to $day',
          );
          changed = true;
        case addStep:
          final task = _task(tasks, args);
          final title = _text(args, 'title', 140);
          saveTaskRecord(
            tasks,
            task.withSteps([...task.steps, TaskStep(title)]),
          );
          activities.add('Added a sub-step to “${task.title}”');
          changed = true;
        case setRepeat:
          final task = _task(tasks, args);
          final target = taskSeries(tasks, task) ?? task;
          if (target.done) {
            throw const FormatException(
              'Reopen the task before setting a repeat schedule.',
            );
          }
          final repeat = _repeatRule(args, target.day);
          if (repeat == null) {
            throw const FormatException('Choose a repeat schedule.');
          }
          final repeating = target.copyWith(repeat: repeat);
          saveTaskRecord(tasks, repeating);
          if (scheduleChanged(target, repeating)) {
            scheduleChanges.add(repeating.id);
          }
          activities.add('Set the repeat schedule for “${target.title}”');
          changed = true;
        default:
          final tool = available[call.name];
          if (tool == null) {
            throw const FormatException(
              'That tool is unavailable. Check Tool settings.',
            );
          }
          drafts.add(tool.draft(args));
      }
    }

    if (reviewSchedule != null) {
      for (final id in scheduleChanges) {
        final task = findTaskRecord(tasks, id);
        if (task == null) continue;
        final conflict = inspectSchedule(tasks, task, now);
        if (conflict == null) continue;
        final time = await reviewSchedule(conflict);
        if (time == null) {
          return ToolResult(currentTasks, const [], const [], cancelled: true);
        }
        saveTaskRecord(tasks, task.copyWith(startMinute: time));
      }
    }

    if (changed) await store.save(tasks);
    return ToolResult(
      List.unmodifiable(tasks),
      activities,
      List.unmodifiable(drafts),
    );
  }

  static PlannerTask _task(List<PlannerTask> tasks, Map<String, Object?> args) {
    final id = _text(args, 'id', 100);
    return findTaskRecord(tasks, id) ??
        (throw const FormatException(
          'The assistant could not identify that task.',
        ));
  }

  static RepeatRule? _repeatRule(Map<String, Object?> args, String day) {
    if (args['repeat_frequency'] == null) return null;
    final frequency = RepeatFrequency.values
        .where((item) => item.name == args['repeat_frequency'])
        .firstOrNull;
    final interval = args['repeat_interval'] ?? 1;
    final weekdays = args['repeat_weekdays'] ?? const <int>[];
    if (frequency == null ||
        interval is! int ||
        weekdays is! List ||
        weekdays.any((item) => item is! int)) {
      throw const FormatException(
        'Choose a frequency, whole interval, and optional weekdays.',
      );
    }
    final until = args['repeat_until'] == null
        ? null
        : _date(args['repeat_until']);
    if (until != null && until.compareTo(day) < 0) {
      throw const FormatException(
        'The repeat end date comes before the start.',
      );
    }
    return RepeatRule(
      frequency: frequency,
      interval: interval,
      weekdays: weekdays.cast<int>().toSet(),
      until: until,
    );
  }

  static String _text(
    Map<String, Object?> args,
    String key,
    int limit, {
    bool optional = false,
  }) {
    final value = args[key];
    if (optional && value == null) return '';
    if (value is! String ||
        (!optional && value.trim().isEmpty) ||
        value.trim().length > limit) {
      throw FormatException('The assistant returned an invalid $key.');
    }
    return value.trim();
  }

  static String _date(Object? value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null && dayKey(parsed) == value) return value;
    }
    throw const FormatException('The assistant returned an invalid date.');
  }

  static int _time(Object? value) {
    if (value is String &&
        RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
      return int.parse(value.substring(0, 2)) * 60 +
          int.parse(value.substring(3));
    }
    throw const FormatException('The assistant returned an invalid time.');
  }
}
