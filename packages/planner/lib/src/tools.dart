import 'device_tools.dart';
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
  const ToolResult(this.tasks, this.activities, this.drafts);

  final List<PlannerTask> tasks;

  final List<String> activities;
  final List<DeviceToolDraft> drafts;
}

class PlannerTools {
  static const createTask = 'create_task';
  static const completeTask = 'complete_task';
  static const rescheduleTask = 'reschedule_task';
  static const addStep = 'add_subtask';

  /// Applies planner changes as a single save. Device handoffs are returned
  /// as drafts for the UI to present to the user.
  Future<ToolResult> apply(
    List<PlannerToolCall> calls, {
    required TaskStore store,
    required List<PlannerTask> currentTasks,
    required DateTime now,
    List<DeviceTool> deviceTools = const [],
    bool approvedTaskCompletion = false,
  }) async {
    final tasks = currentTasks.toList();
    final activities = <String>[];
    final drafts = <DeviceToolDraft>[];
    final available = {for (final tool in deviceTools) tool.name: tool};
    final today = dayKey(now);
    var changed = false;

    for (final call in calls) {
      final args = call.arguments;
      switch (call.name) {
        case createTask:
          final title = _text(args, 'title', 120);
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
          tasks.add(
            PlannerTask(
              id: 'ai-${now.microsecondsSinceEpoch}-${tasks.length}',
              title: title,
              day: _date(args['day'] ?? today),
              notes: _text(args, 'notes', 1000, optional: true),
              priority: TaskPriority.values.byName(priority as String),
              startMinute: args['time'] == null ? null : _time(args['time']),
              duration: duration,
              origin: TaskOrigin.assistant,
            ),
          );
          activities.add('Added “$title”');
          changed = true;
        case completeTask:
          final index = _taskIndex(tasks, args);
          final task = tasks[index];
          if (!approvedTaskCompletion) {
            final tool = available[call.name];
            if (tool == null) {
              throw const FormatException(
                'Enable Task completion in Tool settings.',
              );
            }
            drafts.add(tool.draft({'id': task.id}));
          } else if (!task.done) {
            tasks[index] = task.toggleDone(today);
            activities.add('Completed “${task.title}”');
            changed = true;
          } else {
            activities.add('“${task.title}” was already complete');
          }
        case rescheduleTask:
          final index = _taskIndex(tasks, args);
          final task = tasks[index];
          final day = _date(args['day']);
          final time = args['time'];
          tasks[index] = task.rescheduled(
            day,
            newStart: time == null ? null : _time(time),
            newOrigin: TaskOrigin.tool,
          );
          activities.add('Moved “${task.title}” to $day');
          changed = true;
        case addStep:
          final index = _taskIndex(tasks, args);
          final task = tasks[index];
          final title = _text(args, 'title', 140);
          tasks[index] = task.withSteps([...task.steps, TaskStep(title)]);
          activities.add('Added a sub-step to “${task.title}”');
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

    if (changed) await store.save(tasks);
    return ToolResult(
      List.unmodifiable(tasks),
      activities,
      List.unmodifiable(drafts),
    );
  }

  static int _taskIndex(List<PlannerTask> tasks, Map<String, Object?> args) {
    final id = _text(args, 'id', 100);
    final index = tasks.indexWhere((task) => task.id == id);
    if (index < 0) {
      throw const FormatException(
        'The assistant could not identify that task.',
      );
    }
    return index;
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
