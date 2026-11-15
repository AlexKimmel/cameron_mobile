class AssistantModel {
  const AssistantModel({
    required this.source,
    required this.name,
    this.sizeLabel,
    this.downloaded = false,
    this.active = false,
  });

  final Uri source;
  final String name;
  final String? sizeLabel;
  final bool downloaded;
  final bool active;
}

abstract interface class AssistantModelLibrary {
  Future<List<AssistantModel>> listModels();
  Future<void> addModel(String url);
  Future<void> downloadModel(Uri source, void Function(double?) onProgress);
  Future<void> selectModel(Uri source);
  Future<void> deleteDownload(Uri source);
}

class ModelCatalogPreferences {
  ModelCatalogPreferences({required this.active, required Set<Uri> sources})
    : sources = Set.unmodifiable(sources);

  final Uri active;
  final Set<Uri> sources;

  Map<String, Object?> toJson() => {
    'active': active.toString(),
    'sources': [for (final source in sources) source.toString()],
  };

  factory ModelCatalogPreferences.fromJson(Map<String, dynamic> json) =>
      ModelCatalogPreferences(
        active: parseHuggingFaceModelUrl(json['active'] as String),
        sources: {
          for (final source in json['sources'] as List)
            parseHuggingFaceModelUrl(source as String),
        },
      );
}

abstract interface class AssistantModelCatalog {
  Future<ModelCatalogPreferences> readCatalog();
  Future<void> restoreCatalog(ModelCatalogPreferences preferences);
}

Uri parseHuggingFaceModelUrl(String input) {
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
