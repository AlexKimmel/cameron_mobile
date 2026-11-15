import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';

import 'design.dart';

class BackupSettingsPanel extends StatefulWidget {
  const BackupSettingsPanel({
    super.key,
    required this.backup,
    required this.restore,
    required this.onRestored,
  });

  final PlannerBackup backup;
  final Future<void> Function(PlannerBackupSnapshot) restore;
  final VoidCallback onRestored;

  @override
  State<BackupSettingsPanel> createState() => _BackupSettingsPanelState();
}

class _BackupSettingsPanelState extends State<BackupSettingsPanel> {
  String? _working;
  String? _feedback;

  Future<void> _run(String progress, Future<void> Function() action) async {
    if (_working != null) return;
    setState(() {
      _feedback = null;
      _working = progress;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _feedback = error is FormatException
              ? error.message
              : 'Could not finish the backup operation. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _export() => _run('Preparing backup', () async {
    if (await widget.backup.exportFile() && mounted) {
      setState(() => _feedback = 'Backup saved.');
    }
  });

  Future<void> _import() => _run('Opening backup', () async {
    final snapshot = await widget.backup.pickFile();
    if (snapshot == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _BackupPreview(snapshot: snapshot),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _working = 'Restoring backup');
    await widget.restore(snapshot);
    if (mounted) widget.onRestored();
  });

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text('Backup', style: context.type.titleMedium),
        ),
        const Text('Save or restore your tasks and settings as a local file.'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: _working == null ? _export : null,
              child: const Text('Export backup'),
            ),
            OutlinedButton(
              onPressed: _working == null ? _import : null,
              child: const Text('Import backup'),
            ),
          ],
        ),
        if ((_working ?? _feedback) case final status?)
          Semantics(liveRegion: true, child: Text(status)),
      ],
    ),
  );
}

class _BackupPreview extends StatelessWidget {
  const _BackupPreview({required this.snapshot});

  final PlannerBackupSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final tasks = snapshot.tasks.where((task) => !task.skipped).toList();
    final completed = tasks.where((task) => task.done).length;
    final focus =
        snapshot.preferences[PlannerPreferenceKeys.briefingFocus] as String?;
    return AlertDialog(
      title: const Text('Preview backup'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            MaterialLocalizations.of(context)
                .formatFullDate(snapshot.createdAt.toLocal()),
          ),
          Text('${tasks.length} tasks and series · $completed completed'),
          const SizedBox(height: 8),
          for (final task in tasks.take(5))
            Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (tasks.length > 5) Text('And ${tasks.length - 5} more'),
          const SizedBox(height: 12),
          Text('${snapshot.preferences.length} saved settings'),
          if (focus != null && focus.isNotEmpty)
            Text(
              'Briefing focus · $focus',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (snapshot.models case final models?)
            Text(
              'Selected model · ${models.active.pathSegments.last}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 12),
          const Text(
            'Restoring replaces your current tasks and preference settings.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Restore backup'),
        ),
      ],
    );
  }
}
