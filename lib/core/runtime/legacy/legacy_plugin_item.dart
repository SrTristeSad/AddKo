class LegacyPluginItem {
  const LegacyPluginItem({
    required this.label,
    required this.path,
    required this.url,
    required this.isFolder,
    this.label2 = '',
    this.art = const {},
    this.properties = const {},
    this.info = const {},
    this.videoInfo = const {},
    this.audioInfo = const {},
    this.mimeType,
    this.subtitles = const [],
    this.contextMenu = const [],
  });

  final String label;
  final String label2;
  final String path;
  final String url;
  final bool isFolder;
  final Map<String, String> art;
  final Map<String, String> properties;
  final Map<String, Object?> info;
  final Map<String, Object?> videoInfo;
  final Map<String, Object?> audioInfo;
  final String? mimeType;
  final List<String> subtitles;
  final List<LegacyContextMenuItem> contextMenu;

  bool get isPlayable {
    final value = properties['IsPlayable'] ?? properties['isPlayable'];
    return value?.toLowerCase() == 'true' || value == '1';
  }

  factory LegacyPluginItem.fromJson(Map<String, Object?> json) {
    final rawContext = json['context_menu'];
    return LegacyPluginItem(
      label: json['label']?.toString() ?? '',
      label2: json['label2']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      isFolder: json['is_folder'] == true,
      art: _stringMap(json['art']),
      properties: _stringMap(json['properties']),
      info: _objectMap(json['info']),
      videoInfo: _objectMap(json['video_info']),
      audioInfo: _objectMap(json['audio_info']),
      mimeType: json['mime_type']?.toString(),
      subtitles: _stringList(json['subtitles']),
      contextMenu: rawContext is List
          ? rawContext
              .whereType<Map>()
              .map(
                (item) => LegacyContextMenuItem.fromJson(
                  Map<String, Object?>.from(item),
                ),
              )
              .toList(growable: false)
          : const [],
    );
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) {
      return const {};
    }
    return Map.unmodifiable({
      for (final entry in value.entries)
        entry.key.toString(): entry.value?.toString() ?? '',
    });
  }

  static Map<String, Object?> _objectMap(Object? value) {
    if (value is! Map) {
      return const {};
    }
    return Map.unmodifiable(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return List.unmodifiable(value.map((item) => item.toString()));
  }
}

class LegacyContextMenuItem {
  const LegacyContextMenuItem({
    required this.label,
    required this.command,
  });

  final String label;
  final String command;

  factory LegacyContextMenuItem.fromJson(Map<String, Object?> json) {
    return LegacyContextMenuItem(
      label: json['label']?.toString() ?? '',
      command: json['command']?.toString() ?? '',
    );
  }
}
