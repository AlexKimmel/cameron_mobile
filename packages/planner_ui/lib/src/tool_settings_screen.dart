import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';

import 'design.dart';

class ToolSettingsScreen extends StatefulWidget {
  const ToolSettingsScreen({
    super.key,
    required this.tools,
    required this.store,
  });

  final List<DeviceTool> tools;
  final DeviceToolStore? store;

  @override
  State<ToolSettingsScreen> createState() => _ToolSettingsScreenState();
}

class _ToolSettingsScreenState extends State<ToolSettingsScreen> {
  Set<String>? _enabled;
  bool _saving = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final store = widget.store;
    if (store == null) return;
    if (_loadFailed) setState(() => _loadFailed = false);
    try {
      final enabled = <String>{};
      for (final tool in widget.tools) {
        if (await store.isEnabled(tool.name)) enabled.add(tool.name);
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
                  available
                      ? 'Choose which tools BotPsy can use. You review each action before opening the phone, messaging, or email app. These tools require no additional device permissions.'
                      : 'Communication tools are available on Android and iOS.',
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
                            subtitle: Text(tool.description),
                            value: enabled?.contains(tool.name) ?? false,
                            onChanged: available && !_saving
                                ? (value) => _setEnabled(tool, value)
                                : null,
                          ),
                      ],
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
