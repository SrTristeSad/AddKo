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

  RepositorySource copyWith({bool? enabled}) {
    return RepositorySource(
      uri: uri,
      enabled: enabled ?? this.enabled,
    );
  }
}
