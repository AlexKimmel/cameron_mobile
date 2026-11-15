import 'dart:convert';

import 'models.dart';
import 'notifications.dart';
import 'recurrence.dart';
import 'task.dart';

abstract final class PlannerPreferenceKeys {
  static const toolPrefix = 'planner.tools.v1.';
  static const briefingFocus = 'planner.briefing.focus';
  static const quietHours = 'planner.notifications.quiet';

  static String notification(PlannerNotificationKind kind) =>
      'planner.notifications.${kind.name}';

  static bool includes(String key) =>
      key == briefingFocus ||
      key == quietHours ||
      RegExp(r'^planner\.tools\.v1\.[a-z_][a-z0-9_]*$').hasMatch(key) ||
      PlannerNotificationKind.values.any((kind) => notification(kind) == key);

  static bool accepts(String key, Object? value) {
    if (!includes(key)) return false;
    if (key == briefingFocus) return value is String;
    if (key != quietHours) return value is bool;
    if (value is! String) return false;
    final hours = jsonDecode(value);
    if (hours is! List ||
        hours.length != 2 ||
        hours.any((hour) => hour is! int)) {
      return false;
    }
    QuietHours(startMinute: hours.first as int, endMinute: hours.last as int);
    return true;
  }
}

class PlannerBackupSnapshot {
  PlannerBackupSnapshot({
    required this.createdAt,
    required List<PlannerTask> tasks,
    required Map<String, Object> preferences,
    this.models,
  }) : tasks = List.unmodifiable(tasks),
       preferences = Map.unmodifiable(preferences);

  final DateTime createdAt;
  final List<PlannerTask> tasks;
  final Map<String, Object> preferences;
  final ModelCatalogPreferences? models;

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'app': 'Cameron',
    'version': 1,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'tasks': [for (final task in tasks) task.toJson()],
    'settings': preferences,
    if (models != null) 'models': models!.toJson(),
  });

  factory PlannerBackupSnapshot.decode(String source) {
    try {
      final document = jsonDecode(source);
      if (document is! Map<String, dynamic> ||
          document['app'] != 'Cameron' ||
          document['version'] != 1) {
        throw const FormatException('Choose a supported Cameron backup file.');
      }
      final date = DateTime.parse(document['createdAt'] as String);
      final tasks = [
        for (final entry in document['tasks'] as List)
          PlannerTask.fromJson(entry as Map<String, dynamic>),
      ];
      _validateTasks(tasks);
      final preferences = (document['settings'] as Map<String, dynamic>);
      if (preferences.entries.any(
        (entry) => !PlannerPreferenceKeys.accepts(entry.key, entry.value),
      )) {
        throw const FormatException('The backup contains invalid settings.');
      }
      return PlannerBackupSnapshot(
        createdAt: date,
        tasks: tasks,
        preferences: preferences.cast<String, Object>(),
        models: document['models'] == null
            ? null
            : ModelCatalogPreferences.fromJson(
                document['models'] as Map<String, dynamic>,
              ),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('This file is not a valid Cameron backup.');
    }
  }
}

void _validateTasks(List<PlannerTask> tasks) {
  final ids = <String>{};
  final series = {
    for (final task in tasks)
      if (task.repeat != null) task.id,
  };
  bool validDay(String key) {
    final date = DateTime.tryParse(key);
    return date != null && dayKey(date) == key;
  }

  for (final task in tasks) {
    final occurrence = task.occurrence;
    if (task.id.isEmpty ||
        !ids.add(task.id) ||
        task.title.trim().isEmpty ||
        !validDay(task.day) ||
        (task.completedOn != null && !validDay(task.completedOn!)) ||
        task.duration < 0 ||
        task.duration > 1440 ||
        (task.startMinute != null &&
            (task.startMinute! < 0 || task.startMinute! >= 1440)) ||
        (task.skipped && occurrence == null) ||
        (occurrence != null &&
            (!series.contains(occurrence.seriesId) ||
                !validDay(occurrence.originalDay) ||
                task.id !=
                    occurrenceTaskId(
                      occurrence.seriesId,
                      occurrence.originalDay,
                    ) ||
                task.repeat != null))) {
      throw const FormatException('The backup contains invalid tasks.');
    }
  }
}

abstract interface class PlannerBackup {
  Future<bool> exportFile();
  Future<PlannerBackupSnapshot?> pickFile();
  Future<void> restore(PlannerBackupSnapshot snapshot);
}
