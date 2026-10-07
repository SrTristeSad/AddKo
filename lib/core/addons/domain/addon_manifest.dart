import 'addon_dependency.dart';

class AddonManifest {
  const AddonManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.providerName,
    required this.dependencies,
    required this.extensions,
    this.summary,
    this.description,
    this.iconPath,
    this.fanartPath,
  });

  final String id;
  final String name;
  final String version;
  final String providerName;
  final List<AddonDependency> dependencies;
  final List<AddonExtension> extensions;
  final String? summary;
  final String? description;
  final String? iconPath;
  final String? fanartPath;

  bool get isRepository =>
      extensions.any((extension) => extension.point == 'xbmc.addon.repository');

  bool get isPythonPlugin => extensions.any(
        (extension) => extension.point == 'xbmc.python.pluginsource',
      );

  bool get isPythonScript => extensions.any(
        (extension) => extension.point == 'xbmc.python.script',
      );

  String? get pythonEntrypoint {
    for (final extension in extensions) {
      if (extension.point == 'xbmc.python.pluginsource') {
        return extension.library;
      }
    }
    return null;
  }

  String? get pythonScriptEntrypoint {
    for (final extension in extensions) {
      if (extension.point == 'xbmc.python.script') {
        return extension.library;
      }
    }
    return null;
  }
}

class AddonExtension {
  const AddonExtension({
    required this.point,
    required this.attributes,
    required this.provides,
    this.library,
  });

  final String point;
  final String? library;
  final Map<String, String> attributes;
  final List<String> provides;
}
