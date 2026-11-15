import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:planner/planner.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalPlannerBackup implements PlannerBackup {
  LocalPlannerBackup(this._tasks, {this._models});

  static const _maxBytes = 32 * 1024 * 1024;
  final TaskStore _tasks;
  final AssistantModelCatalog? _models;
  final _prefs = SharedPreferencesAsync();

  Future<Set<String>> _includedKeys() async =>
      (await _prefs.getKeys()).where(PlannerPreferenceKeys.includes).toSet();

  Future<PlannerBackupSnapshot> _capture() async {
    final settings = await _prefs.getAll(allowList: await _includedKeys());
    return PlannerBackupSnapshot(
      createdAt: DateTime.now(),
      tasks: await _tasks.read(),
      preferences: {
        for (final entry in settings.entries)
          if (PlannerPreferenceKeys.accepts(entry.key, entry.value))
            entry.key: entry.value!,
      },
      models: await _models?.readCatalog(),
    );
  }

  @override
  Future<bool> exportFile() async {
    final snapshot = await _capture();
    final bytes = utf8.encode(snapshot.encode());
    if (bytes.length > _maxBytes) {
      throw const FormatException('This backup is larger than 32 MB.');
    }
    final file = await FilePicker.saveFile(
      bytes: bytes,
      fileName: 'cameron-${dayKey(snapshot.createdAt)}.json',
      mimeType: 'application/json',
      dialogTitle: 'Save Cameron backup',
    );
    return file != null;
  }

  @override
  Future<PlannerBackupSnapshot?> pickFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      dialogTitle: 'Open Cameron backup',
    );
    if (file == null) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      bytes.add(chunk);
      if (bytes.length > _maxBytes) {
        throw const FormatException('Choose a Cameron backup under 32 MB.');
      }
    }
    return PlannerBackupSnapshot.decode(utf8.decode(bytes.takeBytes()));
  }

  @override
  Future<void> restore(PlannerBackupSnapshot snapshot) async {
    final previous = await _capture();
    try {
      await _replacePreferences(snapshot.preferences);
      final models = snapshot.models;
      if (models != null) await _models?.restoreCatalog(models);
      await _tasks.save(snapshot.tasks);
    } catch (_) {
      try {
        await _replacePreferences(previous.preferences);
        final priorModels = previous.models;
        if (priorModels != null) await _models?.restoreCatalog(priorModels);
        await _tasks.save(previous.tasks);
      } catch (_) {
        throw const FormatException(
          'Could not restore the backup. Some preferences may have changed.',
        );
      }
      rethrow;
    }
  }

  Future<void> _replacePreferences(Map<String, Object> values) async {
    final current = await _includedKeys();
    for (final key in current.difference(values.keys.toSet())) {
      await _prefs.remove(key);
    }
    for (final entry in values.entries) {
      switch (entry.value) {
        case final bool enabled:
          await _prefs.setBool(entry.key, enabled);
        case final String text:
          await _prefs.setString(entry.key, text);
      }
    }
  }
}
