import 'kodi_version.dart';

/// Kodi add-on API capabilities implemented by the AddKo legacy runtime.
///
/// AddKo currently targets the Kodi 21 (Omega) Python 3 compatibility line.
/// These values are used to validate <requires> entries instead of blindly
/// accepting every xbmc.* dependency as if the host implemented it.
class KodiHostCapabilities {
  const KodiHostCapabilities._();

  static const String kodiRelease = '21.0.0';

  static const Map<String, String> versions = {
    'xbmc.core': '0.1.0',
    'xbmc.addon': '21.0.0',
    'xbmc.python': '3.0.1',
    'xbmc.gui': '5.17.0',
    'xbmc.json': '13.5.0',
    'xbmc.metadata': '2.1.0',
  };

  static String? versionFor(String addonId) => versions[addonId];

  static bool satisfies(String addonId, String? minimumVersion) {
    final provided = versionFor(addonId);
    if (provided == null) {
      return false;
    }
    return KodiVersion(provided).isAtLeast(minimumVersion);
  }
}
