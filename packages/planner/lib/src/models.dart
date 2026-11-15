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
