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
    final value = source.trim();
    const prefix = 'plugin://';
    if (value.length < prefix.length ||
        value.substring(0, prefix.length).toLowerCase() != prefix) {
      throw FormatException('URI precisa usar o esquema plugin://', source);
    }

    // Uri.host normalizes host names to lowercase. Kodi addon ids are not DNS
    // host names and third-party repositories sometimes publish mixed-case ids
    // (for example plugin.video.BrazucaPlay.Matrix). Parse the authority by
    // hand so the id reaches the installed-addon registry unchanged.
    final remainder = value.substring(prefix.length);
    var boundary = remainder.length;
    for (final marker in ['/', '?', '#']) {
      final index = remainder.indexOf(marker);
      if (index >= 0 && index < boundary) {
        boundary = index;
      }
    }

    final addonId = remainder.substring(0, boundary);
    if (addonId.isEmpty) {
      throw FormatException('URI plugin sem addon id.', source);
    }

    final tail = remainder.substring(boundary);
    final synthetic = Uri.parse(
      'https://addko.invalid${tail.startsWith('/') ? tail : '/$tail'}',
    );

    return PluginUri(
      addonId: addonId,
      path: synthetic.path.isEmpty ? '/' : synthetic.path,
      queryParameters: Map.unmodifiable(synthetic.queryParameters),
    );
  }

  @override
  String toString() {
    final normalizedPath = path.isEmpty
        ? '/'
        : path.startsWith('/')
            ? path
            : '/$path';
    final encodedQuery = queryParameters.isEmpty
        ? ''
        : '?${Uri(queryParameters: queryParameters).query}';
    return 'plugin://$addonId$normalizedPath$encodedQuery';
  }
}
