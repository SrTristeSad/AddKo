import 'kodi_version.dart';

/// Kodi add-on API capabilities exposed by the AddKo legacy host.
///
/// AddKo targets the Kodi 21 (Omega) compatibility line. Binary add-ons do not
/// download `kodi.binary.*` dependencies from repositories: those are virtual
/// capabilities supplied by Kodi itself. Keep these values aligned with
/// Kodi Omega's `xbmc/addons/kodi-dev-kit/include/kodi/versions.h`.
class KodiHostCapabilities {
  const KodiHostCapabilities._();

  static const String kodiRelease = '21.0.0';

  static const Map<String, String> versions = {
    // Core/Python add-on API capabilities.
    'xbmc.core': '0.1.0',
    'xbmc.addon': '21.0.0',
    'xbmc.python': '3.0.1',
    'xbmc.gui': '5.17.0',
    'xbmc.json': '13.5.0',
    'xbmc.metadata': '2.1.0',

    // Kodi Omega binary add-on global ABI capabilities.
    'kodi.binary.global.main': '2.0.2',
    'kodi.binary.global.general': '1.0.5',
    'kodi.binary.global.gui': '5.15.0',
    'kodi.binary.global.audioengine': '1.1.1',
    'kodi.binary.global.filesystem': '1.1.9',
    'kodi.binary.global.network': '1.0.4',
    'kodi.binary.global.tools': '1.0.4',

    // Kodi Omega binary add-on instance ABI capabilities.
    'kodi.binary.instance.audiodecoder': '4.0.0',
    'kodi.binary.instance.audioencoder': '3.0.0',
    'kodi.binary.instance.game': '3.0.2',
    'kodi.binary.instance.imagedecoder': '3.0.1',
    'kodi.binary.instance.inputstream': '3.3.0',
    'kodi.binary.instance.peripheral': '3.0.2',
    'kodi.binary.instance.pvr': '8.3.0',
    'kodi.binary.instance.screensaver': '2.2.0',
    'kodi.binary.instance.vfs': '3.0.1',
    'kodi.binary.instance.visualization': '4.0.0',
    'kodi.binary.instance.videocodec': '2.1.0',
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
