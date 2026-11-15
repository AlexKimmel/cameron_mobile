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

  bool get done => completedOn != null;

  PlannerTask toggleDone(String today) => PlannerTask(
    id: id,
    title: title,
    day: day,
    notes: notes,
    priority: priority,
    origin: origin,
    startMinute: startMinute,
    duration: duration,
    completedOn: done ? null : today,
    steps: steps,
  );

  PlannerTask rescheduled(
    String newDay, {
    int? newStart,
    TaskOrigin? newOrigin,
  }) => PlannerTask(
    id: id,
    title: title,
    day: newDay,
    notes: notes,
    priority: priority,
    origin: newOrigin ?? origin,
    startMinute: newStart ?? startMinute,
    duration: duration,
    completedOn: completedOn,
    steps: steps,
  );

  PlannerTask withSteps(List<TaskStep> steps) => PlannerTask(
    id: id,
    title: title,
    day: day,
    notes: notes,
    priority: priority,
    origin: origin,
    startMinute: startMinute,
    duration: duration,
    completedOn: completedOn,
    steps: List.unmodifiable(steps),
  );

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
