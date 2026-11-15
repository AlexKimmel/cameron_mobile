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

class PlannerApp extends StatelessWidget {
  const PlannerApp({
    super.key,
    required this.store,
    required this.assistant,
    this.modelLibrary,
    this.toolStore,
    this.openDeviceTool,
    this.calendar,
    this.deviceTools = communicationTools,
    this.dictation,
    this.briefingStore,
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
  final PlannerDictation? dictation;
  final BriefingStore? briefingStore;
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
        deviceTools: deviceTools,
        dictation: dictation,
        briefingStore: briefingStore,
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
    required this.deviceTools,
    required this.dictation,
    required this.briefingStore,
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
  final PlannerDictation? dictation;
  final BriefingStore? briefingStore;
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
  List<PlannerTask>? _tasks;
  late List<String> _activities = widget.initialActivities;
  late String? _summary = widget.initialSummary;
  late DateTime _displayTime = widget.clock();
  late String? _summarySlot = BriefingSlot.current(_displayTime)?.id;
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
  bool _checking = true;
  bool _installed = false;
  bool _installing = false;
  bool _managingModels = false;
  bool _asking = false;
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
    super.dispose();
  }

  void _scheduleClockRefresh() {
    _clockRefresh?.cancel();
    final now = widget.clock();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final next = BriefingSlot.next(now).start;
    final boundary = next.isBefore(midnight) ? next : midnight;
    _clockRefresh = Timer(boundary.difference(now), _refreshClock);
  }

  void _refreshClock() {
    final now = widget.clock();
    final slot = BriefingSlot.current(now)?.id;
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
    final slot = BriefingSlot.current(now);
    if (store == null ||
        tasks == null ||
        slot == null ||
        !_installed ||
        !_foreground ||
        _briefingRun != null ||
        _managingModels ||
        _settledBriefing == _briefingRevision ||
        _asking ||
        _startingVoice ||
        _listening ||
        _reviewingVoice) {
      return;
    }
    final revision = _briefingRevision;
    final run = _loadBriefing(store, now, slot, tasks, revision);
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
  ) async {
    setState(() {
      _briefingLoading = true;
      _briefingFailed = false;
    });
    bool stillCurrent() =>
        _briefingRevision == revision &&
        BriefingSlot.current(widget.clock())?.id == slot.id;
    try {
      final text = await BriefingService(
        store: store,
        assistant: widget.assistant,
      ).refresh(now, tasks);
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
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _readFailed = false;
          _invalidateBriefing();
        });
        unawaited(_refreshBriefing());
      }
    } catch (_) {
      if (mounted) setState(() => _readFailed = true);
    }
  }

  Future<void> _checkModel() async {
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
      if (mounted) _message('Could not check local model storage.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 84),
      ),
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
      if (mounted) _message('Download failed. Tap the mic to retry.');
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
    _endingVoice = true;
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
      _message('Could not finish dictation.');
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
        unawaited(_reviewTranscript(transcript.trim()));
        return;
      }
      _message(error ?? 'No speech detected.');
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

  Future<void> _reviewTranscript(String transcript) async {
    setState(() => _reviewingVoice = true);
    final result = await showPlannerSheet<PromptResult>(
      context,
      PromptSheet(transcript: transcript),
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

  void _showToolSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ToolSettingsScreen(
          tools: _toolCatalog,
          store: widget.toolStore,
          available: _toolAvailable,
          calendar: widget.calendar,
        ),
      ),
    );
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
      final task = _tasks!.firstWhere(
        (task) => task.id == draft.arguments['id'],
      );
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
    if (tasks == null || _asking || _saving) return;
    final now = widget.clock();
    setState(() => _asking = true);
    try {
      await _briefingRun;
      if (!mounted) return;
      final offered = await _enabledTools(_toolCatalog);
      if (!mounted) return;
      final reply = await widget.assistant.ask(
        prompt,
        tasks: tasks,
        now: now,
        deviceTools: offered,
      );
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
      );
      if (!mounted) return;
      _acceptToolResult(result);
      if (result.drafts.isNotEmpty) {
        if (result.activities.isNotEmpty) {
          _message(result.activities.join('\n'));
        }
        await showPlannerSheet<void>(
          context,
          DeviceToolReviewSheet(
            drafts: result.drafts,
            review: _reviewTool,
            open: _openTool,
          ),
        );
      } else if (result.activities.isNotEmpty) {
        _message(result.activities.join('\n'));
      } else {
        await showPlannerSheet<void>(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(reply.text.isEmpty ? 'No response.' : reply.text),
            ],
          ),
        );
      }
    } on FormatException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('Could not finish that request. Try again.');
    } finally {
      if (mounted) {
        setState(() => _asking = false);
        unawaited(_refreshBriefing());
      }
    }
  }

  Future<void> _edit({PlannerTask? task, bool timed = false}) async {
    if (_tasks == null || _asking || _saving || _listening || _startingVoice) {
      return;
    }
    final result = await showPlannerSheet<TaskEditResult>(
      context,
      TaskEditor(task: task, now: widget.clock(), timed: timed),
    );
    if (!mounted) return;
    switch (result) {
      case SaveTask(task: final edited):
        await _write(
          (tasks) => [
            for (final current in tasks)
              if (current.id == edited.id) edited else current,
            if (task == null) edited,
          ],
        );
      case DeleteTask():
        await _write(
          (tasks) => tasks.where((current) => current.id != task!.id).toList(),
        );
      case null:
        break;
    }
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
      _write(
        (tasks) => [
          for (final current in tasks)
            if (current.id == task.id) update(current) else current,
        ],
      ),
    );
  }

  Future<void> _write(
    List<PlannerTask> Function(List<PlannerTask>) update,
  ) async {
    final tasks = _tasks;
    if (tasks == null || _asking || _saving || _startingVoice || _listening) {
      return;
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
        unawaited(_refreshBriefing());
      }
    } catch (_) {
      if (mounted) _message('Could not save changes. Try again.');
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
          : const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      key: PageStorageKey(_tab),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: _tab == 0
          ? BriefingScreen(
              now: _displayTime,
              tasks: tasks,
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
              tasks: tasks,
              today: dayKey(_displayTime),
              filter: _taskFilter,
              onFilterChanged: (filter) => setState(() => _taskFilter = filter),
              canEdit: !_asking && !_saving && !_listening && !_startingVoice,
              onEdit: (task) => _edit(task: task),
              onToggle: _toggle,
              onStepToggle: _toggleStep,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final voiceAvailable =
        widget.dictation != null && widget.assistant.supported;
    final busy = _asking || _startingVoice || _installing || _managingModels;
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
                                    _startingVoice
                                ? null
                                : () => _edit(timed: _tab == 0),
                            icon: const Icon(Icons.add),
                            tooltip: _tab == 0 ? 'Add session' : 'Add task',
                          ),
                        ],
                      ),
                    ),
                    if (_installing)
                      LinearProgressIndicator(
                        value: _progress,
                        semanticsLabel: 'Assistant download',
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
