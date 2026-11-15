import 'package:material_ui/material_ui.dart';

import 'design.dart';

enum WelcomeAction { sample, quickAdd, setupAssistant, later }

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.assistantAvailable,
    required this.onSample,
  });

  final bool assistantAvailable;
  final Future<bool> Function() onSample;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _saving = false;
  bool _failed = false;

  Future<void> _sample() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      final saved = await widget.onSample();
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context, WelcomeAction.sample);
      } else {
        setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Welcome to Cameron',
                    style: context.type.headlineMedium,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try a day with example tasks or start planning your own.',
                  style: context.type.bodyLarge,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _sample,
                  icon: const Icon(Icons.view_day_outlined),
                  label: Text(
                    _saving ? 'Adding sample day' : 'Try a sample day',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => Navigator.pop(context, WelcomeAction.quickAdd),
                  icon: const Icon(Icons.add),
                  label: const Text('Add my first task'),
                ),
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        'Could not save the sample day. Try again.',
                        style: TextStyle(color: context.palette.error),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (widget.assistantAvailable)
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(
                            context,
                            WelcomeAction.setupAssistant,
                          ),
                    child: const Text('Set up the assistant'),
                  ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.pop(context, WelcomeAction.later),
                  child: Text(
                    widget.assistantAvailable
                        ? 'Set up the assistant later'
                        : 'Skip for now',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
