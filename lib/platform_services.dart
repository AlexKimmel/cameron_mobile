import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:planner/planner.dart';
import 'package:planner_ui/planner_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

class PreferencesTaskStore implements TaskStore {
  static const _key = 'planner.tasks.v1';
  final _prefs = SharedPreferencesAsync();

  @override
  Future<List<PlannerTask>> read() async {
    final data = await _prefs.getString(_key);
    if (data == null) return const [];
    return (jsonDecode(data) as List)
        .cast<Map<String, dynamic>>()
        .map(PlannerTask.fromJson)
        .toList();
  }

  @override
  Future<void> save(List<PlannerTask> tasks) => _prefs.setString(
    _key,
    jsonEncode(tasks.map((task) => task.toJson()).toList()),
  );
}

class PreferencesDeviceToolStore implements DeviceToolStore {
  final _prefs = SharedPreferencesAsync();

  String _key(String name) => 'planner.tools.v1.$name';

  @override
  Future<bool> isEnabled(String name) async =>
      await _prefs.getBool(_key(name)) ?? false;

  @override
  Future<void> setEnabled(String name, bool enabled) =>
      _prefs.setBool(_key(name), enabled);
}

Future<bool> Function(DeviceToolDraft)? get mobileToolOpener =>
    _isMobile ? _openDeviceTool : null;

Future<bool> _openDeviceTool(DeviceToolDraft draft) async {
  const channel = MethodChannel('cameron/communication');
  return await channel.invokeMethod<bool>(draft.tool.name, draft.arguments) ??
      false;
}

bool get _isMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

class MobileDictation implements PlannerDictation {
  static bool get supported => _isMobile;

  final _speech = SpeechToText();
  void Function(String?)? _onDone;
  int _request = 0;

  void _done([String? error]) {
    final callback = _onDone;
    _onDone = null;
    callback?.call(error);
  }

  @override
  Future<bool> start({
    required ValueChanged<String> onText,
    required ValueChanged<double> onLevel,
    required ValueChanged<String?> onDone,
  }) async {
    final request = ++_request;
    final authorized = await _speech.initialize(
      options: [SpeechToText.androidNoBluetooth],
      onStatus: (status) {
        if (status == SpeechToText.doneStatus) _done();
      },
      onError: (error) => _done(
        'On-device dictation ended. Check your speech settings and try again.',
      ),
    );
    if (!authorized ||
        request != _request ||
        !await SpeechToTextPlatform.instance.hasOnDeviceSupport() ||
        request != _request) {
      return false;
    }
    _onDone = onDone;
    try {
      await _speech.listen(
        onResult: (result) {
          if (request == _request) onText(result.recognizedWords);
        },
        onSoundLevelChange: (level) {
          if (request != _request || !level.isFinite) return;
          final normalized = defaultTargetPlatform == TargetPlatform.iOS
              ? (level + 55) / 45
              : (level + 2) / 12;
          onLevel(normalized.clamp(0.0, 1.0));
        },
        listenOptions: SpeechListenOptions(
          cancelOnError: true,
          onDevice: true,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
        ),
      );
      if (request != _request) await _speech.cancel();
      return request == _request;
    } catch (_) {
      _onDone = null;
      rethrow;
    }
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() async {
    _request++;
    _onDone = null;
    await _speech.cancel();
  }
}
