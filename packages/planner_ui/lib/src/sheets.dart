import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';

import 'design.dart';

abstract interface class PlannerDictation {
  Future<bool> start({
    required ValueChanged<String> onText,
    required ValueChanged<double> onLevel,
    required ValueChanged<String?> onDone,
  });
  Future<void> stop();
  Future<void> cancel();
}

Future<T?> showPlannerSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: context.reducedMotionStyle,
      backgroundColor: context.palette.surface,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: child,
        ),
      ),
    );

Future<DateTime?> pickTaskDate(
  BuildContext context, {
  required DateTime now,
  required DateTime initial,
}) {
  final first = DateTime(now.year - 10);
  final last = DateTime(now.year + 10, 12, 31);
  return showDatePicker(
    context: context,
    currentDate: now,
    firstDate: initial.isBefore(first) ? initial : first,
    lastDate: initial.isAfter(last) ? initial : last,
    initialDate: initial,
  );
}

sealed class TaskEditResult {
  const TaskEditResult();
}

class SaveTask extends TaskEditResult {
  const SaveTask(this.task);

  final PlannerTask task;
}

class DeleteTask extends TaskEditResult {
  const DeleteTask();
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({
    super.key,
    required this.now,
    this.task,
    this.timed = false,
  });

  final DateTime now;
  final PlannerTask? task;
  final bool timed;

  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.task?.title);
  late final _notes = TextEditingController(text: widget.task?.notes);
  late final _duration = TextEditingController(
    text: widget.task == null
        ? (widget.timed ? '30' : '')
        : '${widget.task!.duration}',
  );
  late DateTime _day = widget.task == null
      ? widget.now
      : DateTime.parse(widget.task!.day);
  late bool _high = widget.task?.priority == TaskPriority.high;
  late RepeatFrequency? _frequency = widget.task?.repeat?.frequency;
  late final _repeatEvery = TextEditingController(
    text: '${widget.task?.repeat?.interval ?? 1}',
  );
  late final _weekdays = {...?widget.task?.repeat?.weekdays};
  late DateTime? _repeatUntil = DateTime.tryParse(
    widget.task?.repeat?.until ?? '',
  );
  bool _badEndDate = false;

  bool get _canRepeat =>
      widget.task?.occurrence == null && widget.task?.done != true;

  String get _kind => widget.task?.repeat != null
      ? 'series'
      : widget.task?.occurrence != null
      ? 'occurrence'
      : 'task';
  late TimeOfDay? _time = switch (widget.task?.startMinute) {
    final int minute => TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    _ => widget.timed ? TimeOfDay.fromDateTime(widget.now) : null,
  };

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _duration.dispose();
    _repeatEvery.dispose();
    super.dispose();
  }

  Future<void> _date() async {
    final date = await pickTaskDate(context, now: widget.now, initial: _day);
    if (mounted && date != null) setState(() => _day = date);
  }

  Future<void> _startTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.fromDateTime(widget.now),
    );
    if (mounted && time != null) setState(() => _time = time);
  }

  Future<void> _pickRepeatEnd() async {
    final end = await pickTaskDate(
      context,
      now: widget.now,
      initial: _repeatUntil ?? _day,
    );
    if (mounted && end != null) {
      setState(() {
        _repeatUntil = end;
        _badEndDate = dayKey(end).compareTo(dayKey(_day)) < 0;
      });
    }
  }

  void _save() {
    final valid = _form.currentState!.validate();
    final day = dayKey(_day);
    final frequency = _frequency;
    final until = _repeatUntil == null ? null : dayKey(_repeatUntil!);
    final badEnd =
        frequency != null && until != null && until.compareTo(day) < 0;
    setState(() => _badEndDate = badEnd);
    if (!valid || badEnd) return;

    final original =
        widget.task ??
        PlannerTask(
          id: 'task-${DateTime.now().microsecondsSinceEpoch}',
          title: '',
          day: day,
        );
    final time = _time;
    Navigator.pop(
      context,
      SaveTask(
        original.copyWith(
          title: _title.text.trim(),
          notes: _notes.text.trim(),
          day: day,
          repeat: frequency == null
              ? null
              : RepeatRule(
                  frequency: frequency,
                  interval: int.parse(_repeatEvery.text.trim()),
                  weekdays: frequency == RepeatFrequency.weekly
                      ? _weekdays
                      : const {},
                  until: until,
                ),
          startMinute: time == null ? null : time.hour * 60 + time.minute,
          duration: int.tryParse(_duration.text.trim()) ?? 0,
          priority: _high ? TaskPriority.high : TaskPriority.normal,
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $_kind?'),
        content: Text(widget.task!.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      Navigator.pop(context, const DeleteTask());
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.task != null
              ? 'Edit $_kind'
              : widget.timed
              ? 'New session'
              : 'New task',
          style: context.type.headlineSmall,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _title,
          autofocus: widget.task == null,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Task name'),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Enter a task name.'
              : null,
        ),
        TextFormField(
          controller: _notes,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            M3EButton.tonal(
              onPressed: _date,
              icon: const Icon(Icons.today_outlined),
              label: Text(
                MaterialLocalizations.of(context).formatShortDate(_day),
              ),
            ),
            M3EButton.tonal(
              onPressed: _startTime,
              icon: const Icon(Icons.schedule),
              label: Text(_time?.format(context) ?? 'Start time'),
            ),
            if (_time != null && !widget.timed)
              IconButton(
                onPressed: () => setState(() => _time = null),
                tooltip: 'Clear start time',
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _duration,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Duration in minutes'),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return null;
            final minutes = int.tryParse(value.trim());
            return minutes == null || minutes < 0 || minutes > 1440
                ? 'Enter a number from 0 to 1440.'
                : null;
          },
        ),
        if (_canRepeat) ...[const SizedBox(height: 16), _repeatFields(context)],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('High priority'),
          value: _high,
          onChanged: (value) => setState(() => _high = value),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.task != null)
              M3EButton.text(onPressed: _delete, child: Text('Delete $_kind')),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            M3EButton.filled(onPressed: _save, label: Text('Save $_kind')),
          ],
        ),
      ],
    ),
  );

  Widget _repeatFields(BuildContext context) {
    final frequency = _frequency;
    final labels = MaterialLocalizations.of(context);
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: frequency?.name ?? 'none',
          decoration: const InputDecoration(labelText: 'Repeat'),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('Does not repeat')),
            DropdownMenuItem(value: 'daily', child: Text('Daily')),
            DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
            DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
          ],
          onChanged: (value) => setState(() {
            _frequency = value == null || value == 'none'
                ? null
                : RepeatFrequency.values.byName(value);
            _badEndDate = false;
          }),
        ),
        if (frequency != null) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _repeatEvery,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: switch (frequency) {
                RepeatFrequency.daily => 'Days between repeats',
                RepeatFrequency.weekly => 'Weeks between repeats',
                RepeatFrequency.monthly => 'Months between repeats',
              },
            ),
            validator: (value) {
              final interval = int.tryParse(value?.trim() ?? '');
              return interval == null || interval < 1 || interval > 366
                  ? 'Enter a number from 1 to 366.'
                  : null;
            },
          ),
          if (frequency == RepeatFrequency.weekly)
            Wrap(
              spacing: 6,
              children: [
                for (var day = DateTime.monday; day <= DateTime.sunday; day++)
                  FilterChip(
                    label: Text(weekdays[day - 1].substring(0, 3)),
                    tooltip: weekdays[day - 1],
                    selected: _weekdays.isEmpty
                        ? day == _day.weekday
                        : _weekdays.contains(day),
                    onSelected: (selected) => setState(() {
                      if (_weekdays.isEmpty) _weekdays.add(_day.weekday);
                      if (selected) {
                        _weekdays.add(day);
                      } else if (_weekdays.length > 1) {
                        _weekdays.remove(day);
                      }
                    }),
                  ),
              ],
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _pickRepeatEnd,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _repeatUntil == null
                      ? 'Set repeat end date'
                      : 'Repeat until ${labels.formatShortDate(_repeatUntil!)}',
                ),
              ),
              if (_repeatUntil != null)
                IconButton(
                  onPressed: () => setState(() {
                    _repeatUntil = null;
                    _badEndDate = false;
                  }),
                  tooltip: 'Clear repeat end date',
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (_badEndDate)
            Text(
              'End date must be on or after the start date.',
              style: TextStyle(color: context.palette.error),
            ),
        ],
      ],
    );
  }
}

class BriefingFocusSheet extends StatefulWidget {
  const BriefingFocusSheet({super.key, required this.initial});

  final String initial;

  @override
  State<BriefingFocusSheet> createState() => _BriefingFocusSheetState();
}

class _BriefingFocusSheetState extends State<BriefingFocusSheet> {
  late final _focus = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Briefing focus', style: context.type.headlineSmall),
      const SizedBox(height: 12),
      TextField(
        controller: _focus,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        maxLength: 280,
        decoration: const InputDecoration(
          labelText: 'What should the briefing emphasize?',
          hintText: 'Upcoming deadlines or unfinished priorities',
        ),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _focus.text.trim()),
        child: const Text('Save focus'),
      ),
    ],
  );
}

sealed class PromptResult {
  const PromptResult();
}

class SubmitPrompt extends PromptResult {
  const SubmitPrompt(this.text);

  final String text;
}

class RetryDictation extends PromptResult {
  const RetryDictation();
}

class PromptSheet extends StatefulWidget {
  const PromptSheet({super.key, this.transcript, this.dictationError});

  final String? transcript;
  final String? dictationError;

  @override
  State<PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends State<PromptSheet> {
  final _form = GlobalKey<FormState>();
  late final _prompt = TextEditingController(text: widget.transcript);

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reviewing = widget.transcript != null;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (reviewing) ...[
            Text('Review transcript', style: context.type.headlineSmall),
            if (widget.dictationError case final error?)
              Text(error, style: TextStyle(color: context.palette.error)),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _prompt,
            autofocus: !reviewing,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: reviewing ? 'Transcript' : 'Request',
            ),
            validator: (value) =>
                value?.trim().isNotEmpty == true ? null : 'Enter a request.',
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (reviewing) ...[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, const RetryDictation()),
                  child: const Text('Record again'),
                ),
              ],
              M3EButton.filled(
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    Navigator.pop(context, SubmitPrompt(_prompt.text.trim()));
                  }
                },
                label: Text(reviewing ? 'Submit' : 'Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DeviceToolReviewSheet extends StatefulWidget {
  const DeviceToolReviewSheet({
    super.key,
    required this.drafts,
    required this.review,
    required this.open,
  });

  final List<DeviceToolDraft> drafts;
  final Map<String, String> Function(DeviceToolDraft) review;
  final Future<bool> Function(DeviceToolDraft) open;

  @override
  State<DeviceToolReviewSheet> createState() => _DeviceToolReviewSheetState();
}

class _DeviceToolReviewSheetState extends State<DeviceToolReviewSheet> {
  final _opened = <int>{};
  int? _pending;
  int? _failed;
  String? _error;

  Future<void> _open(int index) async {
    if (_pending != null || _opened.contains(index)) return;
    setState(() {
      _pending = index;
      _failed = null;
      _error = null;
    });
    try {
      final opened = await widget.open(widget.drafts[index]);
      if (!mounted) return;
      if (opened) {
        setState(() => _opened.add(index));
        if (_opened.length == widget.drafts.length) Navigator.pop(context);
      } else {
        _showError(index, 'No app could open this action.');
      }
    } on FormatException catch (error) {
      if (mounted) _showError(index, error.message);
    } catch (_) {
      if (mounted) _showError(index, 'Could not finish this action.');
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  void _showError(int index, String message) => setState(() {
    _failed = index;
    _error = message;
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Review actions', style: context.type.headlineSmall),
      const SizedBox(height: 12),
      for (final (index, draft) in widget.drafts.indexed)
        if (!_opened.contains(index))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(draft.tool.label, style: context.type.titleMedium),
                  for (final field in widget.review(draft).entries) ...[
                    const SizedBox(height: 8),
                    Text(field.key, style: context.type.labelMedium),
                    SelectableText(field.value),
                  ],
                  const SizedBox(height: 12),
                  if (_failed == index)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(color: context.palette.error),
                      ),
                    ),
                  M3EButton.filled(
                    onPressed: _pending == null ? () => _open(index) : null,
                    label: Text(
                      _pending == index
                          ? 'Working…'
                          : _failed == index
                          ? 'Retry'
                          : draft.tool.reviewAction,
                    ),
                  ),
                ],
              ),
            ),
          ),
    ],
  );
}

class CalendarEventsSheet extends StatelessWidget {
  const CalendarEventsSheet({
    super.key,
    required this.day,
    required this.events,
  });

  final DateTime day;
  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    String time(DateTime value) => localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final tomorrow = DateTime(day.year, day.month, day.day + 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Calendar events', style: context.type.headlineSmall),
        Text(localizations.formatFullDate(day)),
        const SizedBox(height: 12),
        if (events.isEmpty) const Text('No events for this date.'),
        for (final event in events)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(event.title.isEmpty ? 'Untitled event' : event.title),
            subtitle: Text(
              event.allDay
                  ? 'All day'
                  : '${event.start.isBefore(day) ? 'From previous day' : time(event.start)}'
                        ' – ${event.end.isAfter(tomorrow) ? 'Continues next day' : time(event.end)}',
            ),
          ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
