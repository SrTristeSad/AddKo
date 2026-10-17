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

    if (id.length > 128 ||
        !RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)+$').hasMatch(id)) {
      throw const FormatException('ID de plugin inválido.');
    }
    if (name.length > 120) {
      throw const FormatException('Nome de plugin muito longo.');
    }
    if (version.length > 64) {
      throw const FormatException('Versão de plugin muito longa.');
    }
    if (!_isSafeLuaEntrypoint(entry)) {
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

  static bool _isSafeLuaEntrypoint(String value) {
    if (!value.endsWith('.lua') ||
        value.length > 512 ||
        value.startsWith('/') ||
        value.contains(r'\') ||
        value.codeUnits.contains(0) ||
        RegExp(r'^[A-Za-z]:').hasMatch(value)) {
      return false;
    }

    final parts = value.split('/');
    if (parts.any(
      (part) =>
          part.isEmpty ||
          part == '.' ||
          part == '..' ||
          part.length > 255 ||
          part.contains(':'),
    )) {
      return false;
    }
    return true;
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
