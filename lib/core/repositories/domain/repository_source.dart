class RepositorySource {
  const RepositorySource({
    required this.uri,
    required this.enabled,
    this.packageBaseUri,
    this.checksumUri,
    this.name,
  });

  final Uri uri;
  final bool enabled;
  final Uri? packageBaseUri;
  final Uri? checksumUri;
  final String? name;

  bool get hasResolvedEndpoint => packageBaseUri != null;

  String get displayName {
    final customName = name?.trim();
    if (customName != null && customName.isNotEmpty) {
      return customName;
    }
    if (uri.host.isNotEmpty) {
      return uri.host;
    }
    return uri.toString();
  }

  Map<String, Object?> toJson() {
    return {
      'uri': uri.toString(),
      'enabled': enabled,
      if (packageBaseUri != null) 'packageBaseUri': packageBaseUri.toString(),
      if (checksumUri != null) 'checksumUri': checksumUri.toString(),
      if (name?.trim().isNotEmpty == true) 'name': name!.trim(),
    };
  }

  factory RepositorySource.fromJson(Map<String, Object?> json) {
    final uri = _parseHttpUri(json['uri'], field: 'Repository source URI');
    final packageBaseUri = _parseOptionalHttpUri(
      json['packageBaseUri'],
      field: 'Repository package base URI',
    );
    final checksumUri = _parseOptionalHttpUri(
      json['checksumUri'],
      field: 'Repository checksum URI',
    );

    return RepositorySource(
      uri: uri,
      enabled: json['enabled'] is bool ? json['enabled']! as bool : true,
      packageBaseUri: packageBaseUri,
      checksumUri: checksumUri,
      name: json['name']?.toString(),
    );
  }

  RepositorySource copyWith({
    bool? enabled,
    Uri? packageBaseUri,
    Uri? checksumUri,
    String? name,
  }) {
    return RepositorySource(
      uri: uri,
      enabled: enabled ?? this.enabled,
      packageBaseUri: packageBaseUri ?? this.packageBaseUri,
      checksumUri: checksumUri ?? this.checksumUri,
      name: name ?? this.name,
    );
  }

  static Uri _parseHttpUri(Object? value, {required String field}) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$field is missing.');
    }
    final uri = Uri.tryParse(value.trim());
    if (!_isHttpUri(uri)) {
      throw FormatException('$field is invalid.');
    }
    return uri!;
  }

  static Uri? _parseOptionalHttpUri(
    Object? value, {
    required String field,
  }) {
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (!_isHttpUri(uri)) {
      throw FormatException('$field is invalid.');
    }
    return uri;
  }

  static bool _isHttpUri(Uri? uri) {
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}
