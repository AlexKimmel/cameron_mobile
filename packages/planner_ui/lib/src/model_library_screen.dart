import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';

import 'design.dart';

class ModelLibraryScreen extends StatefulWidget {
  const ModelLibraryScreen({super.key, required this.library});

  final AssistantModelLibrary library;

  @override
  State<ModelLibraryScreen> createState() => _ModelLibraryScreenState();
}

class _ModelLibraryScreenState extends State<ModelLibraryScreen> {
  List<AssistantModel>? _models;
  String? _error;
  VoidCallback? _retry;
  String? _working;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _run('Loading models', () async {}, retryable: true);
  }

  Future<void> _run(
    String working,
    Future<void> Function() action, {
    bool retryable = false,
  }) async {
    if (_working != null) return;
    setState(() {
      _working = working;
      _error = null;
      _retry = null;
      _progress = null;
    });
    try {
      await action();
      final models = await widget.library.listModels();
      if (mounted) setState(() => _models = models);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is FormatException
            ? error.message
            : 'Could not finish the model operation.';
        _retry = retryable
            ? () => _run(working, action, retryable: true)
            : null;
      });
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _add() async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => const _ModelSourceDialog(),
    );
    if (mounted && url != null) {
      await _run('Adding model', () => widget.library.addModel(url));
    }
  }

  Future<void> _download(AssistantModel model) =>
      _run('Downloading ${model.name}', () async {
        await widget.library.downloadModel(model.source, (fraction) {
          if (mounted) setState(() => _progress = fraction);
        });
        if (!_models!.any((entry) => entry.active && entry.downloaded)) {
          await widget.library.selectModel(model.source);
        }
      }, retryable: true);

  Future<void> _delete(AssistantModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete download?'),
        content: Text('Remove ${model.name} from this device?'),
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
      await _run(
        'Deleting download',
        () => widget.library.deleteDownload(model.source),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final working = _working;
    final models = _models;
    return PopScope(
      canPop: working == null,
      child: Scaffold(
        appBar: AppBar(title: const Text('Assistant models')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  if (working != null || _error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Semantics(
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (working != null) ...[
                              Text(working),
                              const SizedBox(height: 8),
                              if (!context.reduceMotion || _progress != null)
                                LinearProgressIndicator(value: _progress),
                            ],
                            if (_error case final error?)
                              Text(
                                error,
                                style: TextStyle(color: context.palette.error),
                              ),
                            if (_retry case final retry?)
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton(
                                  onPressed: retry,
                                  child: const Text('Retry'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        for (final model
                            in models ?? const <AssistantModel>[]) ...[
                          Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  model.name,
                                  style: context.type.titleMedium,
                                ),
                                Text(
                                  [
                                    ?model.sizeLabel,
                                    if (model.downloaded && model.active)
                                      'In use'
                                    else if (model.downloaded)
                                      'Downloaded'
                                    else
                                      'Available to download',
                                  ].join(' · '),
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    if (!model.downloaded)
                                      FilledButton.tonal(
                                        onPressed: working == null
                                            ? () => _download(model)
                                            : null,
                                        child: const Text('Download'),
                                      ),
                                    if (model.downloaded && !model.active)
                                      FilledButton.tonal(
                                        onPressed: working == null
                                            ? () => _run(
                                                'Switching model',
                                                () => widget.library
                                                    .selectModel(model.source),
                                              )
                                            : null,
                                        child: const Text('Use model'),
                                      ),
                                    if (model.downloaded)
                                      TextButton(
                                        onPressed: working == null
                                            ? () => _delete(model)
                                            : null,
                                        child: const Text('Delete download'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (models != null)
                          OutlinedButton.icon(
                            onPressed: working == null ? _add : null,
                            icon: const Icon(Icons.add_link),
                            label: const Text('Add Hugging Face model'),
                          ),
                      ],
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
}

class _ModelSourceDialog extends StatefulWidget {
  const _ModelSourceDialog();

  @override
  State<_ModelSourceDialog> createState() => _ModelSourceDialogState();
}

class _ModelSourceDialogState extends State<_ModelSourceDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add Hugging Face model'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.url,
      decoration: const InputDecoration(
        labelText: 'Public GGUF file URL',
        helperText: 'Use a single-file GGUF with a tool-calling chat template.',
        helperMaxLines: 3,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Add'),
      ),
    ],
  );
}
