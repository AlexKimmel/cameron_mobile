import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';

import 'briefing_screen.dart';
import 'design.dart';
import 'model_library_screen.dart';
import 'planner_dock.dart';
import 'sheets.dart';
import 'tasks_screen.dart';
import 'tool_settings_screen.dart';
import 'welcome_screen.dart';

class PlannerApp extends StatelessWidget {
  const PlannerApp({
    super.key,
    required this.store,
    required this.assistant,
    this.modelLibrary,
    this.toolStore,
    this.openDeviceTool,
    this.calendar,
    this.notificationSettings,
    this.backup,
    this.onboarding,
    this.deviceTools = communicationTools,
    this.dictation,
    this.briefingStore,
    this.healthBriefing,
    this.scheduleBriefings,
    this.initialTab = 0,
    this.clock = DateTime.now,
    this.previewActivities = const [],
    this.previewSummary,
  });

  final TaskStore store;
  final PlannerAssistant assistant;
  final AssistantModelLibrary? modelLibrary;
  final DeviceToolStore? toolStore;
  final Future<bool> Function(DeviceToolDraft)? openDeviceTool;
  final List<DeviceTool> deviceTools;
  final DeviceCalendar? calendar;
  final PlannerNotificationSettings? notificationSettings;
  final PlannerBackup? backup;
  final PlannerOnboarding? onboarding;
  final PlannerDictation? dictation;
  final BriefingStore? briefingStore;
  final BriefingHealth? healthBriefing;
  final Future<void> Function()? scheduleBriefings;
  final int initialTab;
  final DateTime Function() clock;
  final List<String> previewActivities;
  final String? previewSummary;

  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
    builder: (lightDynamic, darkDynamic) => MaterialApp(
      title: 'Cameron',
      debugShowCheckedModeBanner: false,
      theme: plannerTheme(lightDynamic),
      darkTheme: plannerTheme(darkDynamic, dark: true),
      themeMode: ThemeMode.system,
      builder: (context, child) => ListTileTheme(
        data: const ListTileThemeData(tileColor: Colors.transparent),
        child: M3ETheme(
          data: M3EThemeData.fromMaterial(Theme.of(context)),
          child: child!,
        ),
      ),
      home: _PlannerHome(
        store: store,
        assistant: assistant,
        modelLibrary: modelLibrary,
        toolStore: toolStore,
        openDeviceTool: openDeviceTool,
        calendar: calendar,
        notificationSettings: notificationSettings,
        backup: backup,
        onboarding: onboarding,
        deviceTools: deviceTools,
        dictation: dictation,
        briefingStore: briefingStore,
        healthBriefing: healthBriefing,
        scheduleBriefings: scheduleBriefings,
        initialTab: initialTab,
        clock: clock,
        initialActivities: previewActivities,
        initialSummary: previewSummary,
      ),
    ),
  );
}

class _PlannerHome extends StatefulWidget {
  const _PlannerHome({
    required this.store,
    required this.assistant,
    required this.modelLibrary,
    required this.toolStore,
    required this.openDeviceTool,
    required this.calendar,
    required this.notificationSettings,
    required this.backup,
    required this.onboarding,
    required this.deviceTools,
    required this.dictation,
    required this.briefingStore,
    required this.healthBriefing,
    required this.scheduleBriefings,
    required this.initialTab,
    required this.clock,
    required this.initialActivities,
    required this.initialSummary,
  });

  final TaskStore store;
  final PlannerAssistant assistant;
  final AssistantModelLibrary? modelLibrary;
  final DeviceToolStore? toolStore;
  final Future<bool> Function(DeviceToolDraft)? openDeviceTool;
  final List<DeviceTool> deviceTools;
  final DeviceCalendar? calendar;
  final PlannerNotificationSettings? notificationSettings;
  final PlannerBackup? backup;
  final PlannerOnboarding? onboarding;
  final PlannerDictation? dictation;
  final BriefingStore? briefingStore;
  final BriefingHealth? healthBriefing;
  final Future<void> Function()? scheduleBriefings;
  final int initialTab;
  final DateTime Function() clock;
  final List<String> initialActivities;
  final String? initialSummary;

  @override
  State<_PlannerHome> createState() => _PlannerHomeState();
}

class _PlannerHomeState extends State<_PlannerHome>
    with WidgetsBindingObserver {
  late int _tab = widget.initialTab;
  TaskFilter _taskFilter = TaskFilter.all;
  final _taskSearch = TextEditingController();
  List<PlannerTask>? _tasks;
  late List<String> _activities = widget.initialActivities;
  late String? _summary = widget.initialSummary;
  late DateTime _displayTime = widget.clock();
  BriefingSchedule _briefingSchedule = BriefingSchedule.defaults;
  late String? _summarySlot = _currentBriefing(_displayTime)?.id;
  Future<void>? _briefingRun;
  int _briefingRevision = 0;
  int? _settledBriefing;
  bool _briefingLoading = false;
  bool _briefingFailed = false;
  bool _editingBriefingFocus = false;
  bool _foreground = true;
  final _voiceLevel = ValueNotifier(0.0);
  int _voiceRun = 0;
  bool _startingVoice = false;
  bool _listening = false;
  bool _endingVoice = false;
  bool _reviewingVoice = false;
  Timer? _finishVoiceTimer;
  bool _readFailed = false;
  bool _welcomeChecked = false;
  bool _checking = true;
  bool _installed = false;
  bool _installing = false;
  bool _managingModels = false;
  bool _restoringBackup = false;
  bool _asking = false;
  bool _generatingResponse = false;
  String? _chatPrompt;
  AssistantReply? _chatReply;
  List<PlannerTask>? _chatTasks;
  DateTime? _chatNow;
  String? _chatError;
  bool _chatLoading = false;
  int _assistantRequestId = 0;
  bool _saving = false;
  double? _progress;
  Timer? _clockRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleClockRefresh();
    unawaited(_read());
    unawaited(_checkModel());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockRefresh?.cancel();
    _finishVoiceTimer?.cancel();
    if (_listening || _startingVoice) unawaited(_cancelDictation());
    _voiceLevel.dispose();
    _taskSearch.dispose();
    super.dispose();
  }

  BriefingSlot? _currentBriefing(DateTime now) =>
      BriefingSlot.current(now, schedule: _briefingSchedule);

  void _scheduleClockRefresh() {
    _clockRefresh?.cancel();
    final now = widget.clock();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final next = BriefingSlot.next(now, schedule: _briefingSchedule).start;
    final boundary = next.isBefore(midnight) ? next : midnight;
    _clockRefresh = Timer(boundary.difference(now), _refreshClock);
  }

  void _refreshClock() {
    final now = widget.clock();
    final slot = _currentBriefing(now)?.id;
    setState(() {
      if (dayKey(_displayTime) != dayKey(now)) _activities = const [];
      if (_summarySlot != slot ||
          dayKey(_displayTime) != dayKey(now) ||
          _displayTime.timeZoneOffset != now.timeZoneOffset) {
        _invalidateBriefing();
        _summarySlot = slot;
      }
      _displayTime = now;
    });
    _scheduleClockRefresh();
    unawaited(_refreshBriefing());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      final offsetChanged =
          _displayTime.timeZoneOffset != widget.clock().timeZoneOffset;
      _refreshClock();
      if (offsetChanged && _installed) unawaited(_scheduleBriefings());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      if (_listening || _startingVoice) {
        _voiceRun++;
        _finishVoiceTimer?.cancel();
        setState(() {
          _startingVoice = false;
          _listening = false;
          _endingVoice = false;
        });
        unawaited(_cancelDictation());
      }
    }
  }

  Future<void> _scheduleBriefings() async {
    await widget.scheduleBriefings?.call();
  }

  void _invalidateBriefing() {
    if (widget.briefingStore == null) return;
    _briefingRevision++;
    _summary = null;
    _briefingFailed = false;
  }

  Future<void> _refreshBriefing() async {
    final store = widget.briefingStore;
    final tasks = _tasks;
    final now = widget.clock();
    final slot = _currentBriefing(now);
    if (store == null ||
        tasks == null ||
        slot == null ||
        !_installed ||
        !_foreground ||
        _briefingRun != null ||
        _managingModels ||
        _restoringBackup ||
        _settledBriefing == _briefingRevision ||
        _asking ||
        _startingVoice ||
        _listening ||
        _reviewingVoice) {
      return;
    }
    final revision = _briefingRevision;
    final run = _loadBriefing(
      store,
      now,
      slot,
      tasks,
      revision,
      _briefingSchedule,
    );
    _briefingRun = run;
    await run;
    _briefingRun = null;
    if (mounted && _briefingRevision != revision) {
      unawaited(_refreshBriefing());
    }
  }

  Future<void> _loadBriefing(
    BriefingStore store,
    DateTime now,
    BriefingSlot slot,
    List<PlannerTask> tasks,
    int revision,
    BriefingSchedule schedule,
  ) async {
    setState(() {
      _briefingLoading = true;
      _briefingFailed = false;
    });
    bool stillCurrent() =>
        _briefingRevision == revision &&
        _currentBriefing(widget.clock())?.id == slot.id;
    try {
      final text = await BriefingService(
        store: store,
        assistant: widget.assistant,
        health: widget.healthBriefing,
      ).refresh(now, tasks, schedule: schedule);
      if (mounted && stillCurrent()) {
        setState(() {
          _summary = text;
          _settledBriefing = revision;
        });
      }
    } catch (error) {
      debugPrint('Could not refresh briefing: $error');
      if (mounted && stillCurrent()) {
        setState(() {
          _briefingFailed = true;
          _settledBriefing = revision;
        });
      }
    } finally {
      if (mounted) setState(() => _briefingLoading = false);
    }
  }

  void _retryBriefing() {
    setState(_invalidateBriefing);
    unawaited(_refreshBriefing());
  }

  Future<void> _editBriefingFocus() async {
    final store = widget.briefingStore;
    if (store == null || _editingBriefingFocus) return;
    setState(() => _editingBriefingFocus = true);
    try {
      final original = await store.readFocus();
      if (!mounted) return;
      final focus = await showPlannerSheet<String>(
        context,
        BriefingFocusSheet(initial: original),
      );
      if (!mounted || focus == null || focus == original) return;
      await store.saveFocus(focus);
      if (mounted) _retryBriefing();
    } catch (_) {
      if (mounted) _message('Could not update briefing focus. Try again.');
    } finally {
      if (mounted) setState(() => _editingBriefingFocus = false);
    }
  }

  Future<void> _read() async {
    try {
      final tasks = await widget.store.read();
      var schedule = _briefingSchedule;
      try {
        schedule = await widget.briefingStore?.readSchedule() ?? schedule;
      } catch (error) {
        debugPrint('Could not load briefing times: $error');
      }
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _briefingSchedule = schedule;
          _summarySlot = _currentBriefing(_displayTime)?.id;
          _readFailed = false;
          _invalidateBriefing();
        });
        _refreshClock();
        unawaited(_maybeWelcome());
      }
    } catch (_) {
      if (mounted) setState(() => _readFailed = true);
    }
  }

  Future<void> _maybeWelcome() async {
    final onboarding = widget.onboarding;
    if (onboarding == null || _welcomeChecked) return;
    _welcomeChecked = true;
    try {
      if (await onboarding.hasSeenWelcome() || !mounted) return;
      if (_tasks?.isNotEmpty == true) {
        await onboarding.markWelcomeSeen();
        return;
      }
      final choice = await Navigator.of(context).push<WelcomeAction>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => WelcomeScreen(
            assistantAvailable: widget.assistant.supported,
            onSample: () => _write(
              (tasks) =>
                  tasks.isEmpty ? samplePlannerDay(widget.clock()) : tasks,
            ),
          ),
        ),
      );
      if (!mounted) return;
      try {
        await onboarding.markWelcomeSeen();
      } catch (error) {
        debugPrint('Could not persist the welcome state: $error');
      }
      if (!mounted) return;
      switch (choice) {
        case WelcomeAction.quickAdd:
          setState(() => _tab = 1);
          await _edit();
        case WelcomeAction.setupAssistant:
          await _showDownload();
        case WelcomeAction.sample:
        case WelcomeAction.later:
        case null:
          break;
      }
    } catch (error) {
      debugPrint('Could not finish first-run onboarding: $error');
    }
  }

  Future<void> _checkModel() async {
    if (!_checking) setState(() => _checking = true);
    try {
      final installed =
          widget.assistant.supported && await widget.assistant.isInstalled();
      if (mounted) {
        setState(() => _installed = installed);
        if (installed) {
          unawaited(_scheduleBriefings());
          unawaited(_refreshBriefing());
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _installed = false);
        _message(
          'Could not check local model storage.',
          action: SnackBarAction(label: 'Retry', onPressed: _checkModel),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _message(
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 4),
  }) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 84),
      ),
      snackBarAnimationStyle: context.reducedMotionStyle,
    );

  Future<void> _showDownload() async {
    final library = widget.modelLibrary;
    if (library != null) {
      if (_managingModels) return;
      setState(() => _managingModels = true);
      await _briefingRun;
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ModelLibraryScreen(library: library)),
      );
      if (!mounted) return;
      setState(() {
        _managingModels = false;
        _checking = true;
      });
      await _checkModel();
      return;
    }

    final download = await showPlannerSheet<bool>(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Download assistant', style: context.type.headlineSmall),
          const SizedBox(height: 8),
          const Text('BotPsy-0.8B · 529 MB'),
          const SizedBox(height: 16),
          M3EButton.filled(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.download),
            label: const Text('Download'),
          ),
        ],
      ),
    );
    if (mounted && download == true) await _install();
  }

  Future<void> _install() async {
    if (_installing || _installed) return;
    setState(() {
      _installing = true;
      _progress = 0;
    });
    try {
      await widget.assistant.install((value) {
        if (mounted) setState(() => _progress = value);
      });
      if (mounted) {
        setState(() => _installed = true);
        unawaited(_scheduleBriefings());
        unawaited(_refreshBriefing());
      }
    } catch (_) {
      if (mounted) {
        _message(
          'Could not download the assistant model.',
          action: SnackBarAction(label: 'Retry', onPressed: _install),
        );
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _cancelDictation() async {
    try {
      await widget.dictation?.cancel();
    } catch (error) {
      debugPrint('Could not cancel dictation: $error');
    }
  }

  Future<void> _finishVoice(PlannerDictation dictation) async {
    setState(() => _endingVoice = true);
    final run = _voiceRun;
    void fail() {
      if (!mounted || _voiceRun != run) return;
      _voiceRun++;
      _finishVoiceTimer?.cancel();
      setState(() {
        _listening = false;
        _endingVoice = false;
      });
      unawaited(_cancelDictation());
      _dictationError('Could not finish dictation.');
    }

    _finishVoiceTimer = Timer(const Duration(seconds: 4), fail);
    try {
      await dictation.stop();
    } catch (_) {
      fail();
    }
  }

  Future<void> _voice() async {
    final dictation = widget.dictation;
    if (dictation == null ||
        _startingVoice ||
        _endingVoice ||
        _reviewingVoice ||
        _checking ||
        _installing ||
        _asking ||
        _saving ||
        _restoringBackup ||
        _tasks == null) {
      return;
    }
    if (_listening) {
      await _finishVoice(dictation);
      return;
    }
    if (!_installed) {
      await _showDownload();
      return;
    }

    final run = ++_voiceRun;
    var transcript = '';
    _voiceLevel.value = 0;
    setState(() => _startingVoice = true);

    void done(String? error) {
      if (!mounted || run != _voiceRun) return;
      _voiceRun++;
      _finishVoiceTimer?.cancel();
      setState(() {
        _startingVoice = false;
        _listening = false;
        _endingVoice = false;
      });
      if (transcript.trim().isNotEmpty) {
        unawaited(_reviewTranscript(transcript.trim(), error: error));
        return;
      }
      _dictationError(error ?? 'No speech detected.');
      unawaited(_refreshBriefing());
    }

    try {
      final started = await dictation.start(
        onText: (text) {
          if (mounted && run == _voiceRun) transcript = text;
        },
        onLevel: (level) {
          if (mounted && run == _voiceRun) _voiceLevel.value = level;
        },
        onDone: done,
      );
      if (!mounted || run != _voiceRun) return;
      if (started) {
        setState(() {
          _startingVoice = false;
          _listening = true;
        });
      } else {
        done('On-device dictation is unavailable.');
      }
    } catch (_) {
      done('Could not start dictation.');
    }
  }

  void _dictationError(String message) {
    _message(
      message,
      action: SnackBarAction(label: 'Retry', onPressed: _voice),
    );
  }

  Future<void> _reviewTranscript(String transcript, {String? error}) async {
    setState(() => _reviewingVoice = true);
    final result = await showPlannerSheet<PromptResult>(
      context,
      PromptSheet(transcript: transcript, dictationError: error),
    );
    if (!mounted) return;
    setState(() => _reviewingVoice = false);
    switch (result) {
      case SubmitPrompt(:final text):
        await _ask(text);
      case RetryDictation():
        await _voice();
      case null:
        await _refreshBriefing();
    }
  }

  Future<void> _showToolSettings() async {
    final restored = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ToolSettingsScreen(
          tools: _toolCatalog,
          store: widget.toolStore,
          available: _toolAvailable,
          calendar: widget.calendar,
          healthBriefing: widget.healthBriefing,
          onHealthChanged: _retryBriefing,
          briefingSchedule: widget.briefingStore == null || _tasks == null
              ? null
              : _briefingSchedule,
          saveBriefingSchedule: _saveBriefingSchedule,
          notifications: widget.notificationSettings,
          backup: widget.backup,
          restoreBackup: _restoreBackup,
        ),
      ),
    );
    if (mounted && restored == true) _message('Backup restored.');
  }

  Future<void> _saveBriefingSchedule(BriefingSchedule schedule) async {
    await widget.briefingStore!.saveSchedule(schedule);
    if (!mounted) return;
    _briefingSchedule = schedule;
    _refreshClock();
    if (_installed) await _scheduleBriefings();
  }

  Future<void> _restoreBackup(PlannerBackupSnapshot snapshot) async {
    setState(() => _restoringBackup = true);
    try {
      await _briefingRun;
      await widget.backup!.restore(snapshot);
      if (!mounted) return;
      await _read();
      if (mounted) await _checkModel();
    } finally {
      if (mounted) {
        setState(() => _restoringBackup = false);
        unawaited(_refreshBriefing());
      }
    }
  }

  List<DeviceTool> get _toolCatalog => [
    ...widget.deviceTools,
    taskCompletionTool,
    calendarReadTool,
  ];

  bool _toolAvailable(DeviceTool tool) => switch (tool.name) {
    'complete_task' => widget.assistant.supported,
    'read_calendar' => widget.assistant.supported && widget.calendar != null,
    _ => widget.openDeviceTool != null,
  };

  Future<List<DeviceTool>> _enabledTools(Iterable<DeviceTool> tools) async {
    final store = widget.toolStore;
    if (store == null) return const [];
    try {
      return [
        for (final tool in tools)
          if (_toolAvailable(tool) && await store.isEnabled(tool.name)) tool,
      ];
    } catch (_) {
      if (mounted) _message('Could not read Tool settings.');
      return const [];
    }
  }

  Future<bool> _openTool(DeviceToolDraft draft) async {
    if ((await _enabledTools([draft.tool])).isEmpty) {
      throw const FormatException(
        'This tool is disabled or unavailable in Tool settings.',
      );
    }
    if (!mounted) return false;
    if (draft.tool.name == taskCompletionTool.name) {
      final result = await PlannerTools().apply(
        [PlannerToolCall(draft.tool.name, draft.arguments)],
        store: widget.store,
        currentTasks: _tasks!,
        now: widget.clock(),
        approvedTaskCompletion: true,
      );
      if (mounted) {
        _acceptToolResult(result);
        _message(result.activities.join('\n'));
      }
      return true;
    }
    if (draft.tool.name == calendarReadTool.name) {
      final calendar = widget.calendar!;
      final granted =
          await calendar.hasAccess() || await calendar.requestAccess();
      if (!granted) {
        throw const FormatException(
          'Calendar access is off. Open Tool settings to manage it.',
        );
      }
      final day = DateTime.parse(draft.arguments['day']!);
      final events = await calendar.eventsOn(day);
      if (!mounted) return false;
      await showPlannerSheet<void>(
        context,
        CalendarEventsSheet(day: day, events: events),
      );
      return true;
    }
    return await widget.openDeviceTool?.call(draft) ?? false;
  }

  void _acceptToolResult(ToolResult result) {
    setState(() {
      _tasks = result.tasks;
      if (result.activities.isNotEmpty) {
        _invalidateBriefing();
        _activities = [
          ...result.activities.reversed,
          ..._activities,
        ].take(20).toList();
      }
    });
  }

  Map<String, String> _reviewTool(DeviceToolDraft draft) {
    if (draft.tool.name == taskCompletionTool.name) {
      final task = findTaskRecord(_tasks!, draft.arguments['id']!)!;
      return {'Task': task.title, 'Scheduled date': task.day};
    }
    return {
      for (final field in draft.tool.fields)
        field.label: ?draft.arguments[field.name],
    };
  }

  Future<void> _typePrompt() async {
    if (!_installed) {
      await _showDownload();
      return;
    }
    final result = await showPlannerSheet<PromptResult>(
      context,
      const PromptSheet(),
    );
    if (!mounted) return;
    if (result case SubmitPrompt(:final text)) await _ask(text);
  }

  Future<void> _ask(String prompt) async {
    final tasks = _tasks;
    if (tasks == null ||
        _asking ||
        _saving ||
        _startingVoice ||
        _listening ||
        _managingModels ||
        _restoringBackup) {
      return;
    }
    final now = widget.clock();
    final requestId = ++_assistantRequestId;
    setState(() {
      _asking = true;
      _generatingResponse = true;
      _chatPrompt = prompt;
      _chatReply = null;
      _chatTasks = tasks;
      _chatNow = now;
      _chatError = null;
      _chatLoading = true;
    });
    try {
      await _briefingRun;
      if (!mounted || requestId != _assistantRequestId) return;
      final offered = await _enabledTools(_toolCatalog);
      if (!mounted || requestId != _assistantRequestId) return;
      final reply = await widget.assistant.ask(
        prompt,
        tasks: expandTasks(tasks, now),
        now: now,
        deviceTools: offered,
      );
      if (!mounted || requestId != _assistantRequestId) return;
      if (reply.calls.isEmpty && reply.text.trim().isEmpty) {
        throw StateError('Empty assistant response.');
      }
      setState(() {
        _chatReply = reply;
        _chatLoading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _assistantRequestId) return;
      setState(() {
        _chatError = error is FormatException
            ? error.message
            : 'Could not generate an assistant response.';
        _chatLoading = false;
      });
    } finally {
      if (mounted && requestId == _assistantRequestId) {
        setState(() {
          _asking = false;
          _generatingResponse = false;
        });
        unawaited(_refreshBriefing());
      }
    }
  }

  void _dismissAssistantReview() {
    _assistantRequestId++;
    setState(() {
      _asking = false;
      _generatingResponse = false;
      _chatPrompt = null;
      _chatReply = null;
      _chatTasks = null;
      _chatNow = null;
      _chatError = null;
      _chatLoading = false;
    });
  }

  Future<void> _acceptAssistantReview() async {
    final reply = _chatReply;
    final tasks = _chatTasks;
    final now = _chatNow;
    if (reply == null || tasks == null || now == null || _asking) return;
    setState(() => _asking = true);
    try {
      final offered = await _enabledTools(_toolCatalog);
      if (!mounted) return;
      final enabled = await _enabledTools(
        offered.where(
          (tool) => reply.calls.any((call) => call.name == tool.name),
        ),
      );
      if (!mounted) return;
      final result = await PlannerTools().apply(
        reply.calls,
        store: widget.store,
        currentTasks: tasks,
        now: now,
        deviceTools: enabled,
        reviewSchedule: _pickScheduleTime,
      );
      if (!mounted) return;
      if (result.cancelled) {
        setState(() {
          _chatPrompt = null;
          _chatReply = null;
          _chatTasks = null;
          _chatNow = null;
          _chatError = null;
        });
        return;
      }
      setState(() {
        _chatPrompt = null;
        _chatReply = null;
        _chatTasks = null;
        _chatNow = null;
        _chatError = null;
      });
      _acceptToolResult(result);
      final activityMessage = result.activities.join('\n');
      if (result.drafts.isNotEmpty) {
        if (activityMessage.isNotEmpty) _message(activityMessage);
        await showPlannerSheet<void>(
          context,
          DeviceToolReviewSheet(
            drafts: result.drafts,
            review: _reviewTool,
            open: _openTool,
          ),
        );
        if (mounted) {
          _offerTaskUndo(
            tasks,
            _tasks!,
            activityMessage.isEmpty
                ? 'Assistant task changes saved.'
                : activityMessage,
          );
        }
      } else if (activityMessage.isNotEmpty) {
        if (!_offerTaskUndo(tasks, result.tasks, activityMessage)) {
          _message(activityMessage);
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _chatError = error is FormatException
              ? error.message
              : 'Could not apply the assistant response.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _asking = false);
        unawaited(_refreshBriefing());
      }
    }
  }

  Future<void> _edit({PlannerTask? task, bool timed = false}) async {
    final records = _tasks;
    if (records == null || _asking || _saving || _listening || _startingVoice) {
      return;
    }
    var target = task;
    final series = task == null ? null : taskSeries(records, task);
    if (task != null && series != null) {
      final wholeSeries = await showPlannerSheet<bool>(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit repeating task', style: context.type.headlineSmall),
            const SizedBox(height: 8),
            Text(task.title),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('This occurrence'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Whole series'),
            ),
          ],
        ),
      );
      if (!mounted || wholeSeries == null) return;
      if (wholeSeries) target = series;
    }
    final result = await showPlannerSheet<TaskEditResult>(
      context,
      TaskEditor(
        task: target,
        now: widget.clock(),
        timed: timed,
        showReminders: widget.notificationSettings != null,
        reviewSchedule: _reviewTaskSchedule,
      ),
    );
    if (!mounted || result == null) return;
    await _write((tasks) {
      final updated = tasks.toList();
      switch (result) {
        case SaveTask(task: final edited):
          if (target?.repeat != null && edited.repeat == null) {
            detachTaskOccurrences(updated, target!);
          }
          saveTaskRecord(updated, edited);
        case DeleteTask():
          final removed = target!;
          if (removed.occurrence != null) {
            saveTaskRecord(updated, removed.copyWith(skipped: true));
          } else {
            updated.removeWhere(
              (entry) =>
                  entry.id == removed.id ||
                  entry.occurrence?.seriesId == removed.id,
            );
          }
      }
      return updated;
    }, undoMessage: result is DeleteTask ? 'Deleted “${target!.title}”' : null);
  }

  Future<int?> _pickScheduleTime(ScheduleConflict conflict) => showDialog<int>(
    context: context,
    builder: (_) => ScheduleConflictDialog(conflict: conflict),
  );

  Future<PlannerTask?> _reviewTaskSchedule(PlannerTask task) async {
    final conflict = inspectSchedule(_tasks!, task, widget.clock());
    if (conflict == null) return task;
    final minute = await _pickScheduleTime(conflict);
    return minute == null ? null : task.copyWith(startMinute: minute);
  }

  Future<void> _reschedule(PlannerTask task) async {
    final day = await pickTaskDate(
      context,
      now: widget.clock(),
      initial: DateTime.parse(task.day),
    );
    if (!mounted || day == null || dayKey(day) == task.day) return;
    final resolved = await _reviewTaskSchedule(task.rescheduled(dayKey(day)));
    if (!mounted || resolved == null) return;
    _updateTask(task, (_) => resolved);
  }

  void _toggle(PlannerTask task) => _updateTask(
    task,
    (current) => current.toggleDone(dayKey(widget.clock())),
  );

  void _toggleStep(PlannerTask task, int index) => _updateTask(
    task,
    (current) => current.withSteps([
      for (final (position, step) in current.steps.indexed)
        if (position == index) TaskStep(step.title, done: !step.done) else step,
    ]),
  );

  void _updateTask(PlannerTask task, PlannerTask Function(PlannerTask) update) {
    unawaited(
      _write((tasks) {
        final current = findTaskRecord(tasks, task.id);
        if (current == null) return tasks;
        final updated = tasks.toList();
        saveTaskRecord(updated, update(current));
        return updated;
      }),
    );
  }

  bool _offerTaskUndo(
    List<PlannerTask> before,
    List<PlannerTask> after,
    String message,
  ) {
    final undo = TaskUndo.between(before, after);
    if (undo == null) return false;
    _message(
      message,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => _undoTaskChanges(undo),
      ),
      duration: const Duration(seconds: 8),
    );
    return true;
  }

  Future<void> _undoTaskChanges(TaskUndo undo) async {
    final current = _tasks;
    if (current == null) return;
    if (_asking || _saving || _startingVoice || _listening) {
      _message(
        'Finish the current action before undoing.',
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _undoTaskChanges(undo),
        ),
      );
      return;
    }
    final restored = undo.restore(current);
    if (restored == null) {
      _message('A task has already changed since that action.');
      return;
    }
    final saved = await _write((_) => restored);
    if (!mounted) return;
    if (saved) {
      final message = 'Undid task changes';
      setState(() => _activities = [message, ..._activities].take(20).toList());
      _message(message);
    } else {
      _message(
        'Could not undo the task changes.',
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _undoTaskChanges(undo),
        ),
      );
    }
  }

  Future<bool> _write(
    List<PlannerTask> Function(List<PlannerTask>) update, {
    String? undoMessage,
  }) async {
    final tasks = _tasks;
    if (tasks == null ||
        _asking ||
        _saving ||
        _startingVoice ||
        _listening ||
        _restoringBackup) {
      return false;
    }
    setState(() => _saving = true);
    try {
      final updated = update(tasks);
      await widget.store.save(updated);
      if (mounted) {
        setState(() {
          _tasks = updated;
          _invalidateBriefing();
        });
        if (undoMessage != null) _offerTaskUndo(tasks, updated, undoMessage);
        unawaited(_refreshBriefing());
      }
      return true;
    } catch (_) {
      if (mounted) _message('Could not save changes. Try again.');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _screen(BuildContext context) {
    final tasks = _tasks;
    if (tasks == null) {
      return _readFailed
          ? Center(
              child: M3EButton.tonal(
                onPressed: _read,
                label: const Text('Retry loading tasks'),
              ),
            )
          : Center(
              child: context.reduceMotion
                  ? const Text('Loading tasks')
                  : const CircularProgressIndicator(
                      semanticsLabel: 'Loading tasks',
                    ),
            );
    }
    final visible = expandTasks(tasks, _displayTime);
    return SingleChildScrollView(
      key: PageStorageKey(_tab),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: _tab == 0
          ? BriefingScreen(
              now: _displayTime,
              schedule: _briefingSchedule,
              tasks: visible,
              summary: _summary,
              loading: _briefingLoading,
              onRetry: _briefingFailed ? _retryBriefing : null,
              onEditFocus: widget.briefingStore == null || _editingBriefingFocus
                  ? null
                  : _editBriefingFocus,
              activities: _activities,
              onEdit: (task) => _edit(task: task),
            )
          : TasksScreen(
              tasks: visible,
              today: dayKey(_displayTime),
              filter: _taskFilter,
              search: _taskSearch,
              onFilterChanged: (filter) => setState(() => _taskFilter = filter),
              onReschedule: _reschedule,
              canEdit:
                  !_asking &&
                  !_saving &&
                  !_listening &&
                  !_startingVoice &&
                  !_restoringBackup,
              onEdit: (task) => _edit(task: task),
              onToggle: _toggle,
              onStepToggle: _toggleStep,
            ),
    );
  }

  Widget _assistantOverlay(BuildContext context) {
    final prompt = _chatPrompt;
    final palette = context.palette;
    final reply = _chatReply;
    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        reverseDuration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .96, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: prompt == null
            ? const SizedBox.expand(key: ValueKey('assistant-overlay-hidden'))
            : Stack(
                key: const ValueKey('assistant-overlay-visible'),
                children: [
                  ModalBarrier(color: palette.scrim.withValues(alpha: .42)),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 520,
                            maxHeight: MediaQuery.sizeOf(context).height * .82,
                          ),
                          child: Material(
                            color: palette.surfaceContainerHigh,
                            elevation: 12,
                            shadowColor: palette.shadow,
                            borderRadius: BorderRadius.circular(28),
                            clipBehavior: Clip.antiAlias,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Review assistant response',
                                          style: context.type.titleLarge,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Dismiss response',
                                        onPressed: _chatLoading || !_asking
                                            ? _dismissAssistantReview
                                            : null,
                                        icon: const Icon(Icons.close),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: palette.primaryContainer,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        prompt,
                                        style: context.type.bodyLarge!.copyWith(
                                          color: palette.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                  ),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeInOutCubic,
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      switchInCurve: Curves.easeOut,
                                      switchOutCurve: Curves.easeIn,
                                      child: _chatLoading || _asking
                                          ? Row(
                                              key: ValueKey(
                                                _asking && !_chatLoading
                                                    ? 'applying'
                                                    : 'thinking',
                                              ),
                                              children: [
                                                const SizedBox.square(
                                                  dimension: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                                const SizedBox(width: 10),
                                                Text(
                                                  _asking && !_chatLoading
                                                      ? 'Applying approved actions…'
                                                      : 'Thinking…',
                                                  style:
                                                      context.type.bodyMedium,
                                                ),
                                              ],
                                            )
                                          : const SizedBox.shrink(
                                              key: ValueKey('assistant-idle'),
                                            ),
                                    ),
                                  ),
                                  if (reply != null)
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 260,
                                      ),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      transitionBuilder: (child, animation) =>
                                          FadeTransition(
                                            opacity: animation,
                                            child: SlideTransition(
                                              position: Tween<Offset>(
                                                begin: const Offset(0, .06),
                                                end: Offset.zero,
                                              ).animate(animation),
                                              child: child,
                                            ),
                                          ),
                                      child: Column(
                                        key: ValueKey(reply),
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (reply.calls.isNotEmpty) ...[
                                            const SizedBox(height: 18),
                                            Text(
                                              'Proposed actions',
                                              style: context.type.titleSmall,
                                            ),
                                            const SizedBox(height: 6),
                                            for (final (index, call)
                                                in reply.calls.indexed)
                                              TweenAnimationBuilder<double>(
                                                key: ValueKey(
                                                  '${call.name}-$index',
                                                ),
                                                tween: Tween(begin: 0, end: 1),
                                                duration: Duration(
                                                  milliseconds:
                                                      220 + index * 70,
                                                ),
                                                curve: Curves.easeOutCubic,
                                                builder:
                                                    (
                                                      context,
                                                      value,
                                                      child,
                                                    ) => Opacity(
                                                      opacity: value,
                                                      child:
                                                          Transform.translate(
                                                            offset: Offset(
                                                              0,
                                                              10 * (1 - value),
                                                            ),
                                                            child: child,
                                                          ),
                                                    ),
                                                child: ListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  leading: Icon(
                                                    Icons.build_outlined,
                                                    color: palette.secondary,
                                                  ),
                                                  title: Text(
                                                    call.name.replaceAll(
                                                      '_',
                                                      ' ',
                                                    ),
                                                  ),
                                                  subtitle: SelectableText(
                                                    call.arguments.toString(),
                                                  ),
                                                ),
                                              ),
                                          ],
                                          if (reply.text.trim().isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            Align(
                                              alignment: AlignmentDirectional
                                                  .centerStart,
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  14,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: palette
                                                      .surfaceContainerLowest,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: SelectableText(
                                                  reply.text.trim(),
                                                  style: context.type.bodyLarge,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  if (_chatError case final error?) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      error,
                                      style: context.type.bodyMedium!.copyWith(
                                        color: palette.error,
                                      ),
                                    ),
                                  ],
                                  if (!_chatLoading && !_asking) ...[
                                    const SizedBox(height: 18),
                                    Wrap(
                                      alignment: WrapAlignment.end,
                                      spacing: 8,
                                      children: [
                                        if (_chatError != null)
                                          TextButton(
                                            onPressed: () => _ask(prompt),
                                            child: const Text('Retry'),
                                          ),
                                        TextButton(
                                          onPressed: _dismissAssistantReview,
                                          child: const Text('Dismiss'),
                                        ),
                                        if (reply != null)
                                          FilledButton(
                                            onPressed: _acceptAssistantReview,
                                            child: const Text('Accept'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final voiceAvailable =
        widget.dictation != null && widget.assistant.supported;
    final busy =
        _asking ||
        _chatPrompt != null ||
        _startingVoice ||
        _installing ||
        _managingModels ||
        _restoringBackup;
    final status = switch ((
      _installing,
      _generatingResponse,
      _startingVoice,
      _endingVoice,
    )) {
      (true, _, _, _) => 'Downloading assistant model',
      (_, true, _, _) => 'Generating response',
      (_, _, true, _) => 'Starting dictation',
      (_, _, _, true) => 'Finishing dictation',
      _ => null,
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 12, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _tab == 0 ? 'Daily Briefing' : 'Tasks',
                              style: context.type.titleLarge!.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (widget.assistant.supported)
                            IconButton(
                              onPressed:
                                  busy ||
                                      _checking ||
                                      _saving ||
                                      _listening ||
                                      _tasks == null
                                  ? null
                                  : _typePrompt,
                              icon: const Icon(Icons.keyboard_outlined),
                              tooltip: 'Type a request',
                            ),
                          if (widget.modelLibrary != null)
                            IconButton(
                              onPressed: busy || _checking || _listening
                                  ? null
                                  : _showDownload,
                              icon: const Icon(Icons.memory),
                              tooltip: 'Assistant models',
                            ),
                          IconButton(
                            onPressed: busy || _listening
                                ? null
                                : _showToolSettings,
                            icon: const Icon(Icons.settings_outlined),
                            tooltip: 'Tool settings',
                          ),
                          IconButton(
                            onPressed:
                                _tasks == null ||
                                    _asking ||
                                    _saving ||
                                    _listening ||
                                    _startingVoice ||
                                    _restoringBackup
                                ? null
                                : () => _edit(timed: _tab == 0),
                            icon: const Icon(Icons.add),
                            tooltip: _tab == 0 ? 'Add session' : 'Add task',
                          ),
                        ],
                      ),
                    ),
                    if (status != null)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(status, style: context.type.labelMedium),
                              const SizedBox(height: 6),
                              if (!context.reduceMotion ||
                                  (_installing && _progress != null))
                                LinearProgressIndicator(
                                  value: _installing ? _progress : null,
                                ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(child: _screen(context)),
                  ],
                ),
                PositionedDirectional(
                  start: 12,
                  end: 12,
                  bottom: 12,
                  child: Center(
                    child: PlannerDock(
                      tab: _tab,
                      onTab: (index) {
                        setState(() => _tab = index);
                        unawaited(_refreshBriefing());
                      },
                      onVoice: voiceAvailable && !busy ? _voice : null,
                      listening: _listening,
                      busy: voiceAvailable && busy,
                      level: _voiceLevel,
                    ),
                  ),
                ),
                _assistantOverlay(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
