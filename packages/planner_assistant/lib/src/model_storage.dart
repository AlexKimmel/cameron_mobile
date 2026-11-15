import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:planner/planner.dart';

const defaultFilename = 'botpsy-0.8b-q4_k_m-imat.gguf';

final defaultSource = Uri.https(
  'huggingface.co',
  '/qvac/BotPsy-0.8B-GGUFs/resolve/main/$defaultFilename',
);

final _qwenSource = Uri.https(
  'huggingface.co',
  '/ggml-org/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
);

final _presets = {
  defaultSource: (
    name: 'BotPsy-0.8B',
    size: '529 MB',
    digest: '482db2dfdbc8ab7db3d3216fd8ef071d7381dd8547aff9933bc03312839d4d83',
  ),
  _qwenSource: (
    name: 'Qwen3-1.7B',
    size: '1.28 GB',
    digest: 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5',
  ),
};

class ModelStorage implements AssistantModelLibrary {
  ModelStorage(this._directory, this._validate, this._release);

  final Future<String> Function() _directory;
  final Future<void> Function(File) _validate;
  final Future<void> Function(File) _release;
  bool _writing = false;

  Future<File> _inDirectory(String name) async =>
      File('${await _directory()}${Platform.pathSeparator}$name');

  Future<File> file(Uri source) => _inDirectory(
    source == defaultSource
        ? defaultFilename
        : 'model-${sha256.convert(utf8.encode(source.toString()))}.gguf',
  );

  Future<bool> installed(Uri source) async {
    final model = await file(source);
    if (!await model.exists()) return false;
    return source == defaultSource ? await model.length() == 529296960 : true;
  }

  Future<({Uri active, Set<Uri> imports})> _read() async {
    final catalog = await _inDirectory('assistant-models.json');
    if (!await catalog.exists()) {
      return (active: defaultSource, imports: <Uri>{});
    }
    final json =
        jsonDecode(await catalog.readAsString()) as Map<String, dynamic>;
    final imports = {
      for (final url in json['imports'] as List) _parse(url as String),
    };
    final active = _parse(json['active'] as String);
    return (
      active: _presets.containsKey(active) || imports.contains(active)
          ? active
          : defaultSource,
      imports: imports,
    );
  }

  Future<void> _save(Uri active, Set<Uri> imports) async {
    final catalog = await _inDirectory('assistant-models.json');
    await catalog.parent.create(recursive: true);
    final partial = File('${catalog.path}.part');
    await partial.writeAsString(
      jsonEncode({
        'active': '$active',
        'imports': [for (final source in imports) '$source'],
      }),
      flush: true,
    );
    await partial.rename(catalog.path);
  }

  Future<Uri> selected() async => (await _read()).active;

  @override
  Future<List<AssistantModel>> listModels() async {
    final catalog = await _read();
    return [
      for (final source in {..._presets.keys, ...catalog.imports})
        AssistantModel(
          source: source,
          name: _presets[source]?.name ?? source.pathSegments.last,
          sizeLabel: _presets[source]?.size,
          downloaded: await installed(source),
          active: catalog.active == source,
        ),
    ];
  }

  @override
  Future<void> addModel(String url) => _write(() async {
    final source = _parse(url);
    final catalog = await _read();
    if (_presets.containsKey(source) || !catalog.imports.add(source)) return;
    await _save(catalog.active, catalog.imports);
  });

  @override
  Future<void> selectModel(Uri source) => _write(() async {
    final catalog = await _read();
    if (!_presets.containsKey(source) && !catalog.imports.contains(source)) {
      throw const FormatException('Add this model to the library first.');
    }
    if (!await installed(source)) {
      throw const FormatException('Download this model before using it.');
    }
    final current = await file(catalog.active);
    await _release(current);
    await _save(source, catalog.imports);
  });

  @override
  Future<void> deleteDownload(Uri source) => _write(() async {
    final catalog = await _read();
    final downloaded = await file(source);
    await _release(downloaded);
    if (source == catalog.active && source != defaultSource) {
      await _save(defaultSource, catalog.imports);
    }
    if (await downloaded.exists()) await downloaded.delete();
  });

  @override
  Future<void> downloadModel(Uri source, void Function(double?) progress) =>
      _write(() async {
        final catalog = await _read();
        if (!_presets.containsKey(source) &&
            !catalog.imports.contains(source)) {
          throw const FormatException('Add this model to the library first.');
        }
        if (await installed(source)) return;
        await _release(await file(catalog.active));
        await _download(source, progress);
      });

  Future<void> _write(Future<void> Function() action) async {
    if (_writing) throw StateError('Another model operation is in progress.');
    _writing = true;
    try {
      await action();
    } finally {
      _writing = false;
    }
  }

  Future<void> _download(Uri source, void Function(double?) progress) async {
    final destination = await file(source);
    await destination.parent.create(recursive: true);
    final partial = File('${destination.path}.partial.gguf');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final response = await (await client.getUrl(source))
          .close()
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != HttpStatus.ok) {
        throw FormatException(
          'Hugging Face returned HTTP ${response.statusCode}. Check that the file is public.',
        );
      }
      final size = response.contentLength;
      var received = 0;
      var lastPercent = -1;
      final stream = response.timeout(const Duration(seconds: 45)).map((chunk) {
        received += chunk.length;
        if (size > 0) {
          final percent = (received * 100 ~/ size).clamp(0, 100);
          if (percent != lastPercent) {
            lastPercent = percent;
            progress(percent / 100);
          }
        }
        return chunk;
      });
      progress(size > 0 ? 0 : null);
      final sink = partial.openWrite();
      try {
        await sink.addStream(stream);
      } finally {
        await sink.close();
      }
      progress(null);
      if (received < 4 || (size >= 0 && received != size)) {
        throw const FormatException('The model download was incomplete.');
      }
      final magic = await partial.openRead(0, 4).first;
      if (ascii.decode(magic, allowInvalid: true) != 'GGUF') {
        throw const FormatException('This download is not a GGUF model.');
      }
      if (_presets[source]?.digest case final digest?) {
        if ((await sha256.bind(partial.openRead()).first).toString() !=
            digest) {
          throw const FormatException('The model failed its integrity check.');
        }
      }
      if (source != defaultSource) await _validate(partial);
      await partial.rename(destination.path);
    } finally {
      client.close(force: true);
      if (await partial.exists()) await partial.delete();
    }
  }
}

Uri _parse(String input) {
  const error = FormatException('Enter a public Hugging Face GGUF file URL.');
  final url = Uri.tryParse(input.trim());
  if (url == null ||
      url.scheme != 'https' ||
      url.host != 'huggingface.co' ||
      url.hasPort ||
      url.userInfo.isNotEmpty) {
    throw error;
  }
  final path = url.pathSegments.toList();
  if (path.length < 5 ||
      (path[2] != 'blob' && path[2] != 'resolve') ||
      !path.last.toLowerCase().endsWith('.gguf') ||
      RegExp(
        r'-\d{5}-of-\d{5}\.gguf$',
        caseSensitive: false,
      ).hasMatch(path.last) ||
      path.any(
        (part) =>
            part.isEmpty ||
            part == '.' ||
            part == '..' ||
            part.contains(RegExp(r'[/\\\x00-\x1f]')),
      )) {
    throw error;
  }
  path[2] = 'resolve';
  return Uri(scheme: 'https', host: 'huggingface.co', pathSegments: path);
}
