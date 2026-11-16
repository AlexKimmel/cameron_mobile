import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';

import 'design.dart';

class BriefingScheduleSettings extends StatefulWidget {
  const BriefingScheduleSettings({
    super.key,
    required this.initial,
    required this.onSave,
  });

  final BriefingSchedule initial;
  final Future<void> Function(BriefingSchedule) onSave;

  @override
  State<BriefingScheduleSettings> createState() =>
      _BriefingScheduleSettingsState();
}

class _BriefingScheduleSettingsState extends State<BriefingScheduleSettings> {
  late BriefingSchedule _schedule = widget.initial;
  bool _saving = false;

  Future<void> _edit() async {
    final schedule = await showDialog<BriefingSchedule>(
      context: context,
      builder: (_) => _BriefingScheduleDialog(initial: _schedule),
    );
    if (!mounted || schedule == null || schedule.key == _schedule.key) return;

    setState(() => _saving = true);
    try {
      await widget.onSave(schedule);
      if (mounted) setState(() => _schedule = schedule);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save briefing times.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Briefing times', style: context.type.titleMedium),
        Text(
          BriefingPeriod.values
              .map((period) => context.clock(_schedule.minuteFor(period)))
              .join('  ·  '),
        ),
        TextButton(
          onPressed: _saving ? null : _edit,
          child: Text(
            _saving ? 'Saving briefing times…' : 'Edit briefing times',
          ),
        ),
      ],
    ),
  );
}

class _BriefingScheduleDialog extends StatefulWidget {
  const _BriefingScheduleDialog({required this.initial});

  final BriefingSchedule initial;

  @override
  State<_BriefingScheduleDialog> createState() =>
      _BriefingScheduleDialogState();
}

class _BriefingScheduleDialogState extends State<_BriefingScheduleDialog> {
  late Map<String, int> _times = widget.initial.toJson();

  Future<void> _pick(BriefingPeriod period) async {
    final minute = _times[period.name]!;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (mounted && time != null) {
      setState(() => _times[period.name] = time.hour * 60 + time.minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final distinct =
        _times.values.toSet().length == BriefingPeriod.values.length;
    return AlertDialog(
      title: const Text('Edit briefing times'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Times use your device’s local time.'),
          for (final period in BriefingPeriod.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(switch (period) {
                BriefingPeriod.morning => 'Morning',
                BriefingPeriod.midday => 'Midday',
                BriefingPeriod.evening => 'Evening',
              }),
              trailing: Text(context.clock(_times[period.name]!)),
              onTap: () => _pick(period),
            ),
          if (!distinct)
            Semantics(
              liveRegion: true,
              child: const Text('Choose three different briefing times.'),
            ),
          TextButton(
            onPressed: () =>
                setState(() => _times = BriefingSchedule.defaults.toJson()),
            child: const Text('Use default times'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: distinct
              ? () => Navigator.pop(context, BriefingSchedule.fromJson(_times))
              : null,
          child: const Text('Save times'),
        ),
      ],
    );
  }
}
