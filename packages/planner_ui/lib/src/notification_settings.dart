import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';

import 'design.dart';

class NotificationSettingsPanel extends StatefulWidget {
  const NotificationSettingsPanel({super.key, required this.settings});

  final PlannerNotificationSettings settings;

  @override
  State<NotificationSettingsPanel> createState() =>
      _NotificationSettingsPanelState();
}

class _NotificationSettingsPanelState extends State<NotificationSettingsPanel>
    with WidgetsBindingObserver {
  Set<PlannerNotificationKind>? _enabled;
  bool? _permission;
  QuietHours? _quiet;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_working) _read();
  }

  Future<void> _read() async {
    try {
      final permission = await widget.settings.hasPermission();
      final quiet = await widget.settings.readQuietHours();
      final enabled = <PlannerNotificationKind>{
        for (final kind in PlannerNotificationKind.values)
          if (await widget.settings.isEnabled(kind)) kind,
      };
      if (mounted) {
        setState(() {
          _permission = permission;
          _enabled = enabled;
          _quiet = quiet;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load notification settings.');
      }
    }
  }

  Future<void> _toggle(PlannerNotificationKind kind, bool enabled) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (enabled && !await widget.settings.requestPermission()) {
        if (mounted) {
          setState(() {
            _permission = false;
            _error = 'Allow notifications in device settings, then try again.';
          });
        }
        return;
      }
      await widget.settings.setEnabled(kind, enabled);
      await _read();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update notification settings.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveQuietHours(QuietHours? hours) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.settings.saveQuietHours(hours);
      if (mounted) setState(() => _quiet = hours);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save quiet hours.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _editQuietHours(QuietHours current) async {
    final edited = await showDialog<QuietHours>(
      context: context,
      builder: (_) => _QuietHoursDialog(current: current),
    );
    if (mounted && edited != null) await _saveQuietHours(edited);
  }

  Future<void> _openSettings() async {
    try {
      await widget.settings.openSystemSettings();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open device settings.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Notifications', style: context.type.titleMedium),
          ),
          if (_permission == false)
            TextButton(
              onPressed: _working ? null : _openSettings,
              child: const Text('Device notification settings'),
            ),
          if (_error case final error?)
            Semantics(liveRegion: true, child: Text(error)),
          if (enabled == null)
            _error == null
                ? const Text('Loading notification settings')
                : TextButton(onPressed: _read, child: const Text('Retry'))
          else ...[
            _switch(
              PlannerNotificationKind.taskDue,
              'Scheduled tasks',
              'At the start time, or at 09:00 for date-only tasks.',
              enabled,
            ),
            _switch(
              PlannerNotificationKind.briefingReady,
              'Daily briefings',
              'When a new briefing is ready.',
              enabled,
            ),
            _switch(
              PlannerNotificationKind.reminder,
              'Task reminders',
              'Notify before a task when you set a reminder.',
              enabled,
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Quiet hours'),
              subtitle: Text(
                _quiet == null
                    ? 'Delay task alerts and snoozes until quiet hours end.'
                    : '${context.clock(_quiet!.startMinute)} – ${context.clock(_quiet!.endMinute)}',
              ),
              value: _quiet != null,
              onChanged: _working
                  ? null
                  : (enabled) => _saveQuietHours(
                      enabled
                          ? QuietHours(startMinute: 22 * 60, endMinute: 7 * 60)
                          : null,
                    ),
            ),
            if (_quiet case final current?)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: _working ? null : () => _editQuietHours(current),
                  child: const Text('Edit quiet hours'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _switch(
    PlannerNotificationKind kind,
    String title,
    String subtitle,
    Set<PlannerNotificationKind> enabled,
  ) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
    value: enabled.contains(kind),
    onChanged: _working ? null : (value) => _toggle(kind, value),
  );
}

class _QuietHoursDialog extends StatefulWidget {
  const _QuietHoursDialog({required this.current});

  final QuietHours current;

  @override
  State<_QuietHoursDialog> createState() => _QuietHoursDialogState();
}

class _QuietHoursDialogState extends State<_QuietHoursDialog> {
  late int _start = widget.current.startMinute;
  late int _end = widget.current.endMinute;

  Future<void> _pick({required bool start}) async {
    final minute = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (!mounted || picked == null) return;
    setState(() {
      final value = picked.hour * 60 + picked.minute;
      if (start) {
        _start = value;
      } else {
        _end = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Quiet hours'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton(
          onPressed: () => _pick(start: true),
          child: Text('Starts at ${context.clock(_start)}'),
        ),
        TextButton(
          onPressed: () => _pick(start: false),
          child: Text('Ends at ${context.clock(_end)}'),
        ),
        if (_start == _end) const Text('Choose different start and end times.'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _start == _end
            ? null
            : () => Navigator.pop(
                context,
                QuietHours(startMinute: _start, endMinute: _end),
              ),
        child: const Text('Save'),
      ),
    ],
  );
}
