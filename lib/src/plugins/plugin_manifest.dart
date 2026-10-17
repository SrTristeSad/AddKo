class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.entry,
    required this.permissions,
    this.dependencies = const <String>{},
    this.nativeEngines = const <String>{},
  });

  static final RegExp _idPattern =
      RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)+$');

  final String id;
  final String name;
  final String version;
  final String entry;
  final Set<PluginPermission> permissions;
  final Set<String> dependencies;
  final Set<String> nativeEngines;

  factory PluginManifest.fromJson(Map<String, Object?> json) {
    final id = _requiredString(json, 'id');
    final name = _requiredString(json, 'name');
    final version = _requiredString(json, 'version');
    final entry = _requiredString(json, 'entry');

    if (!_isValidPluginId(id)) {
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

    final dependencies = <String>{};
    final rawDependencies = json['dependencies'];
    if (rawDependencies != null) {
      if (rawDependencies is! List<Object?>) {
        throw const FormatException('dependencies deve ser uma lista.');
      }
      if (rawDependencies.length > 32) {
        throw const FormatException('Plugin declara dependências demais.');
      }

      for (final value in rawDependencies) {
        if (value is! String) {
          throw const FormatException('Dependência de plugin inválida.');
        }
        final dependency = value.trim();
        if (!_isValidPluginId(dependency)) {
          throw FormatException('ID de dependência inválido: $dependency');
        }
        if (dependency == id) {
          throw const FormatException('Plugin não pode depender de si mesmo.');
        }
        if (!dependencies.add(dependency)) {
          throw FormatException('Dependência duplicada: $dependency');
        }
      }
    }

    final nativeEngines = <String>{};
    final rawNative = json['native_engines'];
    if (rawNative != null) {
      if (rawNative is! List || rawNative.length > 4) {
        throw const FormatException('native_engines deve conter até quatro IDs.');
      }
      for (final value in rawNative) {
        if (value is! String ||
            !RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(value) ||
            !nativeEngines.add(value)) {
          throw const FormatException('ID de motor nativo inválido ou duplicado.');
        }
      }
      if (nativeEngines.isNotEmpty &&
          !permissions.contains(PluginPermission.nativeEngine)) {
        throw const FormatException(
          'Declare permissão native_engine para solicitar motores nativos.',
        );
      }
    }

    return PluginManifest(
      id: id,
      name: name,
      version: version,
      entry: entry,
      permissions: Set.unmodifiable(permissions),
      dependencies: Set.unmodifiable(dependencies),
      nativeEngines: Set.unmodifiable(nativeEngines),
    );
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key é obrigatório.');
    }
    return value.trim();
  }

  static bool _isValidPluginId(String value) {
    return value.isNotEmpty && value.length <= 128 && _idPattern.hasMatch(value);
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
  background('background'),
  nativeEngine('native_engine');

  const PluginPermission(this.wireName);

  final String wireName;

  static PluginPermission parse(String value) {
    for (final permission in values) {
      if (permission.wireName == value) return permission;
    }
    throw FormatException('Permissão desconhecida: $value');
  }
}
