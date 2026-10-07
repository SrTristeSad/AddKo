class LegacyPluginInvocation {
  const LegacyPluginInvocation({
    required this.addonId,
    required this.addonPath,
    required this.entrypointPath,
    required this.pluginUrl,
    required this.handle,
    required this.query,
    required this.profilePath,
    required this.addonsRoot,
    required this.addonDataRoot,
    required this.shimsPath,
    required this.pythonPaths,
    required this.specialPaths,
    this.argv,
  });

  final String addonId;
  final String addonPath;
  final String entrypointPath;
  final String pluginUrl;
  final int handle;
  final String query;
  final String profilePath;
  final String addonsRoot;
  final String addonDataRoot;
  final String shimsPath;
  final List<String> pythonPaths;
  final Map<String, String> specialPaths;
  final List<String>? argv;

  Map<String, Object?> toJson() {
    return {
      'addon_id': addonId,
      'addon_path': addonPath,
      'entrypoint_path': entrypointPath,
      'plugin_url': pluginUrl,
      'handle': handle,
      'query': query,
      'profile_path': profilePath,
      'addons_root': addonsRoot,
      'addon_data_root': addonDataRoot,
      'shims_path': shimsPath,
      'python_paths': pythonPaths,
      'special_paths': specialPaths,
      if (argv != null) 'argv': argv,
    };
  }
}
