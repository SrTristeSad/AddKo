class AddonDependency {
  const AddonDependency({
    required this.id,
    this.version,
    this.optional = false,
  });

  final String id;
  final String? version;
  final bool optional;

  @override
  String toString() {
    final requiredVersion = version == null ? '' : ' >= $version';
    final suffix = optional ? ' (optional)' : '';
    return '$id$requiredVersion$suffix';
  }
}
