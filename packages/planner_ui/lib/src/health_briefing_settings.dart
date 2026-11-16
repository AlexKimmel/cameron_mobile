import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';

import 'design.dart';

class HealthBriefingSettings extends StatefulWidget {
  const HealthBriefingSettings({
    super.key,
    required this.health,
    this.onChanged,
  });

  final BriefingHealth health;
  final VoidCallback? onChanged;

  @override
  State<HealthBriefingSettings> createState() => _HealthBriefingSettingsState();
}

class _HealthBriefingSettingsState extends State<HealthBriefingSettings> {
  bool? _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final enabled = await widget.health.isEnabled();
      if (mounted) setState(() => _enabled = enabled);
    } catch (_) {
      if (mounted) setState(() => _enabled = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final success = enabled
          ? await widget.health.requestAccess()
          : await _disable();
      if (!mounted) return;
      setState(() => _enabled = success ? enabled : false);
      if (!success && enabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Health access was not enabled. Check Apple Health or Health Connect permissions and try again.',
            ),
          ),
        );
      }
      widget.onChanged?.call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update health access.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _disable() async {
    await widget.health.disable();
    return true;
  }

  @override
  Widget build(BuildContext context) => Panel(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: const Text('Health context for briefings'),
          subtitle: const Text(
            'Optionally read steps, sleep, and workouts from Apple Health or Health Connect. Cameron uses a short summary for local briefings and does not save the raw records.',
          ),
          value: _enabled ?? false,
          onChanged: _enabled == null || _saving ? null : _setEnabled,
        ),
        if (_enabled == null || _saving)
          const LinearProgressIndicator(minHeight: 2),
      ],
    ),
  );
}
