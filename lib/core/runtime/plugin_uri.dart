class PluginUri {
  const PluginUri({
    required this.addonId,
    required this.path,
    required this.queryParameters,
  });

  final String addonId;
  final String path;
  final Map<String, String> queryParameters;

  factory PluginUri.parse(String source) {
    final uri = Uri.parse(source);
    if (uri.scheme != 'plugin') {
      throw FormatException('URI precisa usar o esquema plugin://', source);
    }
    if (uri.host.isEmpty) {
      throw FormatException('URI plugin sem addon id.', source);
    }

    return PluginUri(
      addonId: uri.host,
      path: uri.path.isEmpty ? '/' : uri.path,
      queryParameters: Map.unmodifiable(uri.queryParameters),
    );
  }

  @override
  String toString() {
    return Uri(
      scheme: 'plugin',
      host: addonId,
      path: path,
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    ).toString();
  }
}
