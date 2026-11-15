import 'dart:convert';

import 'task.dart';

class TaskUndo {
  const TaskUndo._(this._changes, this._originalOrder);

  final Map<String, ({PlannerTask? before, PlannerTask? after})> _changes;
  final List<String> _originalOrder;

  static TaskUndo? between(List<PlannerTask> before, List<PlannerTask> after) {
    final original = {for (final task in before) task.id: task};
    final current = {for (final task in after) task.id: task};
    final changes = {
      for (final id in {...original.keys, ...current.keys})
        if (!_same(original[id], current[id]))
          id: (before: original[id], after: current[id]),
    };
    return changes.isEmpty ? null : TaskUndo._(changes, original.keys.toList());
  }

  /// Returns null when a task in the undo operation has since changed.
  List<PlannerTask>? restore(List<PlannerTask> records) {
    final current = {for (final task in records) task.id: task};
    for (final entry in _changes.entries) {
      if (!_same(current[entry.key], entry.value.after)) return null;
    }

    final restored = <PlannerTask>[];
    for (final task in records) {
      final change = _changes[task.id];
      final value = change == null ? task : change.before;
      if (value != null) restored.add(value);
    }
    for (final (index, id) in _originalOrder.indexed) {
      final original = _changes[id]?.before;
      if (original != null && !current.containsKey(id)) {
        restored.insert(index.clamp(0, restored.length), original);
      }
    }
    return restored;
  }
}

bool _same(PlannerTask? a, PlannerTask? b) =>
    identical(a, b) ||
    (a != null &&
        b != null &&
        jsonEncode(a.toJson()) == jsonEncode(b.toJson()));
