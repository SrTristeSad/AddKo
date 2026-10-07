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

      if (point.contains('inputstream')) {
        return RepositoryAddonCategory.inputStream;
      }
      if (point.contains('pvrclient') || point.contains('.pvr')) {
        return RepositoryAddonCategory.pvr;
      }
      if (point == 'xbmc.addon.repository') {
        return RepositoryAddonCategory.repositories;
      }
      if (point == 'xbmc.python.module') {
        return RepositoryAddonCategory.modules;
      }
      if (point == 'xbmc.service') {
        return RepositoryAddonCategory.services;
      }
      if (point == 'xbmc.subtitle.module') {
        return RepositoryAddonCategory.subtitles;
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
      if (point == 'xbmc.python.script') {
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
    return normalizedBase.resolve(
      '${Uri.encodeComponent(manifest.id)}/${Uri.encodeComponent(manifest.id)}-${Uri.encodeComponent(manifest.version)}.zip',
    );
  }

  Uri? _iconUriFor(Uri? baseUri, AddonManifest manifest) {
    if (baseUri == null) {
      return null;
    }

    final normalizedBase = _directoryUri(baseUri);
    final iconPath = manifest.iconPath?.trim();
    if (iconPath != null && iconPath.isNotEmpty) {
      return normalizedBase.resolve(
        '${Uri.encodeComponent(manifest.id)}/$iconPath',
      );
    }

    return normalizedBase.resolve('${Uri.encodeComponent(manifest.id)}/icon.png');
  }

  Uri _directoryUri(Uri uri) {
    if (uri.path.endsWith('/')) {
      return uri;
    }
    return uri.replace(path: '${uri.path}/');
  }
}
