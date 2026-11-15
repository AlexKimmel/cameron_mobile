import 'package:planner/planner.dart';

class BotPsyAssistant implements PlannerAssistant {
  BotPsyAssistant({
    required Future<String> Function() modelDirectory,
    bool background = false,
  });

  @override
  bool get supported => false;

  @override
  Future<bool> isInstalled() async => false;

  @override
  Future<void> install(void Function(double? fraction) onProgress) async =>
      throw UnsupportedError('BotPsy is available in the native app.');

  @override
  Future<AssistantReply> ask(
    String prompt, {
    required List<PlannerTask> tasks,
    required DateTime now,
    bool readOnly = false,
    List<DeviceTool> deviceTools = const [],
  }) async => throw UnsupportedError('BotPsy is available in the native app.');

  @override
  Future<void> dispose() async {}
}
