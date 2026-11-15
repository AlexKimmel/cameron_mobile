import 'recurrence_rule.dart';

enum TaskOrigin { manual, assistant, tool }

enum TaskPriority { normal, high }

class TaskStep {
  const TaskStep(this.title, {this.done = false});

  final String title;
  final bool done;

  Map<String, Object?> toJson() => {'title': title, 'done': done};

  factory TaskStep.fromJson(Map<String, dynamic> json) =>
      TaskStep(json['title'] as String, done: json['done'] as bool);
}

class PlannerTask {
  const PlannerTask({
    required this.id,
    required this.title,
    required this.day,
    this.notes = '',
    this.priority = TaskPriority.normal,
    this.origin = TaskOrigin.manual,
    this.startMinute,
    this.duration = 0,
    this.completedOn,
    this.steps = const [],
    this.repeat,
    this.occurrence,
    this.skipped = false,
    this.reminderMinutes,
  });

  final String id;
  final String title;
  final String day;
  final String notes;
  final TaskPriority priority;
  final TaskOrigin origin;
  final int? startMinute;
  final int duration;
  final String? completedOn;
  final List<TaskStep> steps;
  final RepeatRule? repeat;
  final TaskOccurrence? occurrence;
  final bool skipped;
  final int? reminderMinutes;

  bool get done => completedOn != null;

  static const _keep = Object();

  PlannerTask copyWith({
    String? id,
    String? title,
    String? day,
    String? notes,
    TaskPriority? priority,
    TaskOrigin? origin,
    Object? startMinute = _keep,
    int? duration,
    Object? completedOn = _keep,
    List<TaskStep>? steps,
    Object? repeat = _keep,
    Object? occurrence = _keep,
    bool? skipped,
    Object? reminderMinutes = _keep,
  }) => PlannerTask(
    id: id ?? this.id,
    title: title ?? this.title,
    day: day ?? this.day,
    notes: notes ?? this.notes,
    priority: priority ?? this.priority,
    origin: origin ?? this.origin,
    startMinute: identical(startMinute, _keep)
        ? this.startMinute
        : startMinute as int?,
    duration: duration ?? this.duration,
    completedOn: identical(completedOn, _keep)
        ? this.completedOn
        : completedOn as String?,
    steps: steps == null ? this.steps : List.unmodifiable(steps),
    repeat: identical(repeat, _keep) ? this.repeat : repeat as RepeatRule?,
    occurrence: identical(occurrence, _keep)
        ? this.occurrence
        : occurrence as TaskOccurrence?,
    skipped: skipped ?? this.skipped,
    reminderMinutes: identical(reminderMinutes, _keep)
        ? this.reminderMinutes
        : reminderMinutes as int?,
  );

  PlannerTask toggleDone(String today) =>
      copyWith(completedOn: done ? null : today);

  PlannerTask rescheduled(
    String newDay, {
    int? newStart,
    TaskOrigin? newOrigin,
  }) => copyWith(
    day: newDay,
    origin: newOrigin,
    startMinute: newStart ?? startMinute,
  );

  PlannerTask withSteps(List<TaskStep> steps) => copyWith(steps: steps);

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'day': day,
    'notes': notes,
    'priority': priority.name,
    'origin': origin.name,
    'startMinute': startMinute,
    'duration': duration,
    'completedOn': completedOn,
    'steps': steps.map((step) => step.toJson()).toList(),
    if (repeat != null) 'repeat': repeat!.toJson(),
    if (occurrence != null) 'occurrence': occurrence!.toJson(),
    if (skipped) 'skipped': true,
    if (reminderMinutes != null) 'reminderMinutes': reminderMinutes,
  };

  factory PlannerTask.fromJson(Map<String, dynamic> json) => PlannerTask(
    id: json['id'] as String,
    title: json['title'] as String,
    day: json['day'] as String,
    notes: json['notes'] as String,
    priority: TaskPriority.values.byName(json['priority'] as String),
    origin: TaskOrigin.values.byName(json['origin'] as String),
    startMinute: json['startMinute'] as int?,
    duration: json['duration'] as int,
    completedOn: json['completedOn'] as String?,
    steps: (json['steps'] as List)
        .cast<Map<String, dynamic>>()
        .map(TaskStep.fromJson)
        .toList(),
    repeat: json['repeat'] == null
        ? null
        : RepeatRule.fromJson(json['repeat'] as Map<String, dynamic>),
    occurrence: json['occurrence'] == null
        ? null
        : TaskOccurrence.fromJson(json['occurrence'] as Map<String, dynamic>),
    skipped: json['skipped'] as bool? ?? false,
    reminderMinutes: switch (json['reminderMinutes']) {
      final int minutes when minutes >= 0 && minutes <= 1440 => minutes,
      _ => null,
    },
  );
}

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

abstract interface class TaskStore {
  Future<List<PlannerTask>> read();
  Future<void> save(List<PlannerTask> tasks);
}

class MemoryTaskStore implements TaskStore {
  MemoryTaskStore([List<PlannerTask> tasks = const []])
    : _tasks = List.unmodifiable(tasks);

  List<PlannerTask> _tasks;

  @override
  Future<List<PlannerTask>> read() async => _tasks;

  @override
  Future<void> save(List<PlannerTask> tasks) async {
    _tasks = List.unmodifiable(tasks);
  }
}
