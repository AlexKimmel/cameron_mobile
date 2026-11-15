import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';

import 'design.dart';

class ToolSettingsScreen extends StatefulWidget {
  const ToolSettingsScreen({
    super.key,
    required this.tools,
    required this.store,
    required this.available,
    this.calendar,
  });

  final List<DeviceTool> tools;
  final DeviceToolStore? store;
  final bool Function(DeviceTool) available;
  final DeviceCalendar? calendar;

  @override
  State<ToolSettingsScreen> createState() => _ToolSettingsScreenState();
}

class _ToolSettingsScreenState extends State<ToolSettingsScreen>
    with WidgetsBindingObserver {
  Set<String>? _enabled;
  bool _saving = false;
  bool _loadFailed = false;
  bool? _calendarAccess;
  bool _requestingAccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read();
    _readCalendarAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _readCalendarAccess();
  }

  Future<void> _readCalendarAccess() async {
    final calendar = widget.calendar;
    if (calendar == null) return;
    try {
      final granted = await calendar.hasAccess();
      if (mounted) setState(() => _calendarAccess = granted);
    } catch (_) {
      if (mounted) setState(() => _calendarAccess = null);
    }
  }

  Future<void> _grantCalendarAccess() async {
    final calendar = widget.calendar!;
    setState(() => _requestingAccess = true);
    try {
      final granted = await calendar.requestAccess();
      if (!mounted) return;
      setState(() => _calendarAccess = granted);
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You can grant Calendar access in device settings.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not request Calendar access.')),
        );
      }
    } finally {
      if (mounted) setState(() => _requestingAccess = false);
    }
  }

  Future<void> _openCalendarSettings() async {
    try {
      await widget.calendar!.openSettings();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Open device settings to manage Calendar access.'),
          ),
        );
      }
    }
  }

  Future<void> _read() async {
    final store = widget.store;
    if (store == null) return;
    if (_loadFailed) setState(() => _loadFailed = false);
    try {
      final enabled = <String>{};
      for (final tool in widget.tools) {
        if (widget.available(tool) && await store.isEnabled(tool.name)) {
          enabled.add(tool.name);
        }
      }
      if (mounted) setState(() => _enabled = enabled);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _setEnabled(DeviceTool tool, bool enabled) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.store!.setEnabled(tool.name, enabled);
      if (!mounted) return;
      setState(() {
        if (enabled) {
          _enabled!.add(tool.name);
        } else {
          _enabled!.remove(tool.name);
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update ${tool.label}. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.store != null;
    final enabled = _enabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Tool settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'Choose which tools the assistant can use. You review each device action or task completion before it runs.',
                  style: context.type.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (_loadFailed)
                  ListTile(
                    title: const Text('Could not load tool settings.'),
                    trailing: TextButton(
                      onPressed: _read,
                      child: const Text('Retry'),
                    ),
                  )
                else if (available && enabled == null)
                  const Center(child: CircularProgressIndicator())
                else
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final tool in widget.tools)
                          SwitchListTile(
                            title: Text(tool.label),
                            subtitle: Text(
                              widget.available(tool)
                                  ? tool.description
                                  : 'Unavailable on this device.',
                            ),
                            value: enabled?.contains(tool.name) ?? false,
                            onChanged:
                                available && widget.available(tool) && !_saving
                                ? (value) => _setEnabled(tool, value)
                                : null,
                          ),
                      ],
                    ),
                  ),
                if (widget.calendar != null) ...[
                  const SizedBox(height: 16),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Calendar access',
                          style: context.type.titleMedium,
                        ),
                        Text(switch (_calendarAccess) {
                          true => 'Granted',
                          false => 'Off',
                          null => 'Permission status unavailable',
                        }),
                        const Text(
                          'Cameron reads events for the date you approve.',
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (_calendarAccess != true)
                              FilledButton.tonal(
                                onPressed: _requestingAccess
                                    ? null
                                    : _grantCalendarAccess,
                                child: const Text('Grant calendar access'),
                              ),
                            TextButton(
                              onPressed: _requestingAccess
                                  ? null
                                  : _openCalendarSettings,
                              child: const Text('Device settings'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
