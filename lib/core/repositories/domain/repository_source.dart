class RepositorySource {
  const RepositorySource({
    required this.uri,
    required this.enabled,
  });

  final Uri uri;
  final bool enabled;

  String get displayName {
    if (uri.host.isNotEmpty) {
      return uri.host;
    }
    return uri.toString();
  }

  Map<String, Object?> toJson() {
    return {
      'uri': uri.toString(),
      'enabled': enabled,
    };
  }

  factory RepositorySource.fromJson(Map<String, Object?> json) {
    final rawUri = json['uri'];
    if (rawUri is! String || rawUri.trim().isEmpty) {
      throw const FormatException('Repository source without a valid URI.');
    }

    final uri = Uri.tryParse(rawUri.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException('Repository source URI is invalid.');
    }

    return RepositorySource(
      uri: uri,
      enabled: json['enabled'] is bool ? json['enabled']! as bool : true,
    );
  }

  RepositorySource copyWith({bool? enabled}) {
    return RepositorySource(
      uri: uri,
      enabled: enabled ?? this.enabled,
    );
  }
}
