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
  late TimeOfDay? _time = switch (widget.task?.startMinute) {
    final int minute => TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    _ => widget.timed ? TimeOfDay.fromDateTime(widget.now) : null,
  };

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _date() async {
    final first = DateTime(widget.now.year - 10);
    final last = DateTime(widget.now.year + 10, 12, 31);
    final date = await showDatePicker(
      context: context,
      firstDate: _day.isBefore(first) ? _day : first,
      lastDate: _day.isAfter(last) ? _day : last,
      initialDate: _day,
    );
    if (mounted && date != null) setState(() => _day = date);
  }

  Future<void> _startTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.fromDateTime(widget.now),
    );
    if (mounted && time != null) setState(() => _time = time);
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final original = widget.task;
    final time = _time;
    Navigator.pop(
      context,
      SaveTask(
        PlannerTask(
          id: original?.id ?? 'task-${DateTime.now().microsecondsSinceEpoch}',
          title: _title.text.trim(),
          notes: _notes.text.trim(),
          duration: int.tryParse(_duration.text.trim()) ?? 0,
          day: dayKey(_day),
          startMinute: time == null ? null : time.hour * 60 + time.minute,
          priority: _high ? TaskPriority.high : TaskPriority.normal,
          completedOn: original?.completedOn,
          origin: original?.origin ?? TaskOrigin.manual,
          steps: original?.steps ?? const [],
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
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
              ? 'Edit task'
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
              M3EButton.text(
                onPressed: _delete,
                child: const Text('Delete task'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            M3EButton.filled(onPressed: _save, label: const Text('Save task')),
          ],
        ),
      ],
    ),
  );
}

class PromptSheet extends StatefulWidget {
  const PromptSheet({super.key});

  @override
  State<PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends State<PromptSheet> {
  final _form = GlobalKey<FormState>();
  final _prompt = TextEditingController();

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _prompt,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Request'),
          validator: (value) =>
              value?.trim().isNotEmpty == true ? null : 'Enter a request.',
        ),
        const SizedBox(height: 12),
        M3EButton.filled(
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.pop(context, _prompt.text.trim());
            }
          },
          label: const Text('Send'),
        ),
      ],
    ),
  );
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
  bool _opening = false;
  String? _error;

  Future<void> _open(int index) async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final opened = await widget.open(widget.drafts[index]);
      if (!mounted) return;
      if (opened) {
        setState(() => _opened.add(index));
        if (_opened.length == widget.drafts.length) Navigator.pop(context);
      } else {
        setState(() => _error = 'No app could open this action.');
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open this action.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

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
                  M3EButton.filled(
                    onPressed: _opening ? null : () => _open(index),
                    label: Text(draft.tool.reviewAction),
                  ),
                ],
              ),
            ),
          ),
      if (_error case final error?)
        Text(error, style: TextStyle(color: context.palette.error)),
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
