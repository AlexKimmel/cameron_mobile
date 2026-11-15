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
      final enabled = <PlannerNotificationKind>{
        for (final kind in PlannerNotificationKind.values)
          if (await widget.settings.isEnabled(kind)) kind,
      };
      if (mounted) {
        setState(() {
          _permission = permission;
          _enabled = enabled;
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
