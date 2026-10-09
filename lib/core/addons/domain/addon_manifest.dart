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

  /// Kodi 21 extension points that are backed by a Python invoker rather than
  /// simply being added to sys.path as an xbmc.python.module dependency.
  static const Set<String> pythonExecutableExtensionPoints = {
    'xbmc.python.pluginsource',
    'xbmc.python.script',
    'xbmc.python.weather',
    'xbmc.python.lyrics',
    'xbmc.python.library',
    'xbmc.subtitle.module',
    'xbmc.service',
  };

  /// Top-level Kodi Omega extension points that may be backed by a binary add-on
  /// instance. VideoCodec is intentionally absent: in Omega it is an instance
  /// ABI used by another add-on, not a standalone addon.xml type mapping.
  static const Set<String> binaryExtensionPoints = {
    'kodi.audiodecoder',
    'kodi.audioencoder',
    'kodi.gameclient',
    'kodi.imagedecoder',
    'kodi.inputstream',
    'kodi.peripheral',
    'kodi.pvrclient',
    'kodi.vfs',
    'xbmc.player.musicviz',
    'xbmc.ui.screensaver',
  };

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

  bool get isPythonModule => extensions.any(
        (extension) => extension.point == 'xbmc.python.module',
      );

  bool get isPythonService => extensions.any(
        (extension) => extension.point == 'xbmc.service',
      );

  bool get isPythonExecutable => extensions.any(
        (extension) =>
            pythonExecutableExtensionPoints.contains(extension.point),
      );

  bool get isWebInterface => extensions.any(
        (extension) => extension.point == 'xbmc.webinterface',
      );

  bool get isBinaryAddon => extensions.any(
        (extension) => binaryExtensionPoints.contains(extension.point),
      );

  Iterable<AddonExtension> get pythonExecutableExtensions => extensions.where(
        (extension) =>
            pythonExecutableExtensionPoints.contains(extension.point),
      );

  Iterable<AddonExtension> get binaryExtensions => extensions.where(
        (extension) => binaryExtensionPoints.contains(extension.point),
      );

  AddonExtension? extensionFor(String point) {
    for (final extension in extensions) {
      if (extension.point == point) {
        return extension;
      }
    }
    return null;
  }

  String? pythonEntrypointFor(String point) {
    return extensionFor(point)?.library;
  }

  String? get pythonEntrypoint =>
      pythonEntrypointFor('xbmc.python.pluginsource');

  String? get pythonScriptEntrypoint =>
      pythonEntrypointFor('xbmc.python.script');

  String? get pythonServiceEntrypoint =>
      pythonEntrypointFor('xbmc.service');

  String? get pythonServiceStartMode =>
      extensionFor('xbmc.service')?.attributes['start'];

  /// Resolve the platform-specific library attribute used by Kodi binary
  /// add-ons, e.g. library_android or library_linux. Some packages use a plain
  /// `library` attribute, so keep it as a final fallback.
  String? binaryLibraryFor(
    AddonExtension extension, {
    required String platform,
  }) {
    if (!binaryExtensionPoints.contains(extension.point)) {
      return null;
    }
    final platformLibrary = extension.attributes['library_$platform']?.trim();
    if (platformLibrary != null && platformLibrary.isNotEmpty) {
      return platformLibrary;
    }
    final genericLibrary = extension.library?.trim();
    if (genericLibrary != null && genericLibrary.isNotEmpty) {
      return genericLibrary;
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
