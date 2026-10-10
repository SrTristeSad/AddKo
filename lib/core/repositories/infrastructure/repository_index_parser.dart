import 'dart:ffi';

import 'package:xml/xml.dart';

import '../../addons/domain/addon_manifest.dart';
import '../../addons/infrastructure/addon_manifest_parser.dart';
import '../domain/repository_catalog.dart';

class RepositoryIndexFormatException implements Exception {
  const RepositoryIndexFormatException(this.message);

  final String message;

  @override
  String toString() => 'RepositoryIndexFormatException: $message';
}

class RepositoryIndexParseResult {
  const RepositoryIndexParseResult({
    required this.addons,
    required this.skippedAddons,
  });

  final List<RepositoryAddonEntry> addons;
  final int skippedAddons;
}

class RepositoryIndexParser {
  const RepositoryIndexParser({
    this.addonManifestParser = const AddonManifestParser(),
  });

  final AddonManifestParser addonManifestParser;

  RepositoryIndexParseResult parse(
    String source, {
    Uri? packageBaseUri,
  }) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(source);
    } on XmlParserException catch (error) {
      throw RepositoryIndexFormatException('XML inválido: ${error.message}');
    }

    final root = document.rootElement;
    if (root.name.local != 'addons') {
      throw const RepositoryIndexFormatException(
        'O índice do repositório precisa usar <addons> como elemento raiz.',
      );
    }

    final entries = <RepositoryAddonEntry>[];
    var skipped = 0;

    for (final addonElement in root.findElements('addon')) {
      try {
        final manifest = addonManifestParser.parse(addonElement.toXmlString());
        if (!_matchesCurrentKodiPlatform(
          packageBaseUri,
          addonElement,
          manifest,
        )) {
          continue;
        }
        entries.add(
          RepositoryAddonEntry(
            manifest: manifest,
            category: _categoryFor(manifest),
            packageUri: _packageUriFor(packageBaseUri, manifest),
            iconUri: _iconUriFor(packageBaseUri, manifest),
          ),
        );
      } on AddonManifestFormatException {
        skipped += 1;
      }
    }

    entries.sort(
      (left, right) => left.manifest.name.toLowerCase().compareTo(
            right.manifest.name.toLowerCase(),
          ),
    );

    return RepositoryIndexParseResult(
      addons: List.unmodifiable(entries),
      skippedAddons: skipped,
    );
  }

  RepositoryAddonCategory _categoryFor(AddonManifest manifest) {
    for (final extension in manifest.extensions) {
      final point = extension.point.toLowerCase();
      final provides = extension.provides.map((value) => value.toLowerCase());

      // Kodi Omega binary/addon-instance families.
      if (point == 'kodi.inputstream') {
        return RepositoryAddonCategory.inputStream;
      }
      if (point == 'kodi.pvrclient' || point == 'xbmc.pvrclient') {
        return RepositoryAddonCategory.pvr;
      }
      if (point == 'kodi.gameclient' || point == 'kodi.addon.game') {
        return RepositoryAddonCategory.games;
      }
      if (point == 'kodi.game.controller') {
        return RepositoryAddonCategory.gameControllers;
      }
      if (point == 'kodi.peripheral') {
        return RepositoryAddonCategory.peripherals;
      }
      if (point == 'kodi.audiodecoder' || point == 'kodi.audioencoder') {
        return RepositoryAddonCategory.audioCodecs;
      }
      if (point == 'kodi.imagedecoder') {
        return RepositoryAddonCategory.imageDecoders;
      }
      if (point == 'kodi.vfs') {
        return RepositoryAddonCategory.vfs;
      }
      if (point == 'xbmc.ui.screensaver') {
        return RepositoryAddonCategory.screensavers;
      }
      if (point == 'xbmc.player.musicviz') {
        return RepositoryAddonCategory.visualizations;
      }

      // Core repository/resources/UI families.
      if (point == 'xbmc.addon.repository') {
        return RepositoryAddonCategory.repositories;
      }
      if (point.startsWith('xbmc.metadata.scraper.')) {
        return RepositoryAddonCategory.metadata;
      }
      if (point == 'xbmc.gui.skin') {
        return RepositoryAddonCategory.skins;
      }
      if (point == 'xbmc.webinterface') {
        return RepositoryAddonCategory.webInterfaces;
      }
      if (point.startsWith('kodi.resource.')) {
        return RepositoryAddonCategory.resources;
      }

      // Python invoker families.
      if (point == 'xbmc.python.module' || point == 'xbmc.python.library') {
        return RepositoryAddonCategory.modules;
      }
      if (point == 'xbmc.service') {
        return RepositoryAddonCategory.services;
      }
      if (point == 'xbmc.subtitle.module') {
        return RepositoryAddonCategory.subtitles;
      }
      if (point == 'xbmc.python.weather') {
        return RepositoryAddonCategory.weather;
      }
      if (point == 'xbmc.python.lyrics') {
        return RepositoryAddonCategory.lyrics;
      }
      if (point == 'xbmc.python.pluginsource') {
        if (provides.contains('video')) {
          return RepositoryAddonCategory.video;
        }
        if (provides.contains('audio')) {
          return RepositoryAddonCategory.audio;
        }
        if (provides.contains('image') || provides.contains('images')) {
          return RepositoryAddonCategory.images;
        }
        return RepositoryAddonCategory.programs;
      }
      if (point == 'xbmc.python.script' || point == 'kodi.context.item') {
        return RepositoryAddonCategory.programs;
      }

      // Static addon content types retained by Kodi's addon type table.
      if (point == 'xbmc.addon.video') {
        return RepositoryAddonCategory.video;
      }
      if (point == 'xbmc.addon.audio') {
        return RepositoryAddonCategory.audio;
      }
      if (point == 'xbmc.addon.image') {
        return RepositoryAddonCategory.images;
      }
      if (point == 'xbmc.addon.executable') {
        return RepositoryAddonCategory.programs;
      }
    }

    return RepositoryAddonCategory.other;
  }

  Uri? _packageUriFor(Uri? baseUri, AddonManifest manifest) {
    if (baseUri == null) {
      return null;
    }

    final normalizedBase = _directoryUri(baseUri);
    final directoryName = _packageDirectoryName(normalizedBase, manifest);
    return normalizedBase.resolve(
      '${Uri.encodeComponent(directoryName)}/${Uri.encodeComponent(manifest.id)}-${Uri.encodeComponent(manifest.version)}.zip',
    );
  }

  Uri? _iconUriFor(Uri? baseUri, AddonManifest manifest) {
    if (baseUri == null) {
      return null;
    }

    final normalizedBase = _directoryUri(baseUri);
    final directoryName = _packageDirectoryName(normalizedBase, manifest);
    final iconPath = manifest.iconPath?.trim();
    if (iconPath != null && iconPath.isNotEmpty) {
      return normalizedBase.resolve(
        '${Uri.encodeComponent(directoryName)}/$iconPath',
      );
    }

    return normalizedBase.resolve(
      '${Uri.encodeComponent(directoryName)}/icon.png',
    );
  }

  String _packageDirectoryName(Uri baseUri, AddonManifest manifest) {
    if (!_isKodiOfficialRepository(baseUri) || !_isBinaryAddon(manifest)) {
      return manifest.id;
    }

    final platform = _kodiPlatformSuffix();
    if (platform == null) {
      return manifest.id;
    }
    return '${manifest.id}+$platform';
  }

  bool _matchesCurrentKodiPlatform(
    Uri? baseUri,
    XmlElement addonElement,
    AddonManifest manifest,
  ) {
    if (baseUri == null ||
        !_isKodiOfficialRepository(baseUri) ||
        !_isBinaryAddon(manifest)) {
      return true;
    }

    final currentPlatform = _kodiPlatformSuffix();
    if (currentPlatform == null) {
      return true;
    }

    final platforms = addonElement
        .findElements('extension')
        .where(
          (element) => element.getAttribute('point') == 'xbmc.addon.metadata',
        )
        .expand((element) => element.findElements('platform'))
        .expand(
          (element) => element.innerText
              .split(RegExp(r'[\s,]+'))
              .map((value) => value.trim().toLowerCase())
              .where((value) => value.isNotEmpty),
        )
        .toSet();

    if (platforms.isEmpty || platforms.contains('all')) {
      return true;
    }
    return platforms.contains(currentPlatform.toLowerCase());
  }

  bool _isBinaryAddon(AddonManifest manifest) {
    return manifest.dependencies.any(
      (dependency) => dependency.id.toLowerCase().startsWith('kodi.binary.'),
    );
  }

  bool _isKodiOfficialRepository(Uri uri) {
    return uri.host.toLowerCase() == 'mirrors.kodi.tv' &&
        uri.path.toLowerCase().contains('/addons/');
  }

  String? _kodiPlatformSuffix() {
    final abi = Abi.current();
    if (abi == Abi.androidArm64) return 'android-aarch64';
    if (abi == Abi.androidArm) return 'android-armv7';
    if (abi == Abi.androidX64) return 'android-x86_64';
    if (abi == Abi.windowsX64) return 'windows-x86_64';
    if (abi == Abi.windowsIA32) return 'windows-i686';
    if (abi == Abi.macosArm64) return 'osx-arm64';
    if (abi == Abi.macosX64) return 'osx-x86_64';
    return null;
  }

  Uri _directoryUri(Uri uri) {
    if (uri.path.endsWith('/')) {
      return uri;
    }
    return uri.replace(path: '${uri.path}/');
  }
}
