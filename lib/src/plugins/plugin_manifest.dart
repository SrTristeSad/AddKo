class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.entry,
    required this.permissions,
  });

  final String id;
  final String name;
  final String version;
  final String entry;
  final Set<PluginPermission> permissions;

  factory PluginManifest.fromJson(Map<String, Object?> json) {
    final id = _requiredString(json, 'id');
    final name = _requiredString(json, 'name');
    final version = _requiredString(json, 'version');
    final entry = _requiredString(json, 'entry');

    if (!RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)+$').hasMatch(id)) {
      throw const FormatException('ID de plugin inválido.');
    }
    if (!entry.endsWith('.lua') || entry.contains('..') || entry.startsWith('/')) {
      throw const FormatException('Entrypoint Lua inválido.');
    }

    final rawPermissions = json['permissions'];
    if (rawPermissions is! List<Object?>) {
      throw const FormatException('permissions deve ser uma lista.');
    }

    final permissions = <PluginPermission>{};
    for (final value in rawPermissions) {
      if (value is! String) {
        throw const FormatException('Permissão inválida.');
      }
      permissions.add(PluginPermission.parse(value));
    }

    return PluginManifest(
      id: id,
      name: name,
      version: version,
      entry: entry,
      permissions: Set.unmodifiable(permissions),
    );
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key é obrigatório.');
    }
    return value.trim();
  }
}

enum PluginPermission {
  network('network'),
  storage('storage'),
  media('media'),
  background('background');

  const PluginPermission(this.wireName);

  final String wireName;

  static PluginPermission parse(String value) {
    for (final permission in values) {
      if (permission.wireName == value) return permission;
    }
    throw FormatException('Permissão desconhecida: $value');
  }
}
