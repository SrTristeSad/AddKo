class RepositoryDescriptor {
  const RepositoryDescriptor({
    required this.addonId,
    required this.name,
    required this.endpoints,
  });

  final String addonId;
  final String name;
  final List<RepositoryEndpoint> endpoints;
}

class RepositoryEndpoint {
  const RepositoryEndpoint({
    required this.infoUri,
    required this.dataUri,
    required this.compressed,
    required this.zipPackages,
    this.checksumUri,
    this.minimumVersion,
  });

  final Uri infoUri;
  final Uri dataUri;
  final Uri? checksumUri;
  final bool compressed;
  final bool zipPackages;
  final String? minimumVersion;
}
