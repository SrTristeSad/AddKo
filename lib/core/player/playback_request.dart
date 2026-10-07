import '../runtime/legacy/legacy_plugin_item.dart';

class PlaybackRequest {
  const PlaybackRequest({
    required this.uri,
    required this.headers,
    required this.properties,
    required this.subtitles,
    this.title,
    this.mimeType,
    this.inputStreamAddon,
    this.manifestType,
    this.drmLicenseKey,
  });

  final String uri;
  final String? title;
  final String? mimeType;
  final Map<String, String> headers;
  final Map<String, String> properties;
  final List<String> subtitles;
  final String? inputStreamAddon;
  final String? manifestType;
  final String? drmLicenseKey;

  bool get requiresKodiInputStream {
    final addon = inputStreamAddon?.trim();
    return addon != null && addon.isNotEmpty;
  }

  bool get hasDrmConfiguration {
    return drmLicenseKey?.trim().isNotEmpty == true ||
        properties.keys.any((key) {
          final normalized = key.toLowerCase();
          return normalized.contains('license') || normalized.contains('drm');
        });
  }

  factory PlaybackRequest.fromLegacyItem(LegacyPluginItem item) {
    final rawTarget = item.path.isNotEmpty ? item.path : item.url;
    final parsed = _parseKodiUrl(rawTarget);
    final normalizedProperties = <String, String>{
      for (final entry in item.properties.entries)
        entry.key.toLowerCase(): entry.value,
    };

    String? property(List<String> names) {
      for (final name in names) {
        final value = normalizedProperties[name.toLowerCase()]?.trim();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
      return null;
    }

    return PlaybackRequest(
      uri: parsed.uri,
      title: item.label.isEmpty ? null : item.label,
      mimeType: item.mimeType,
      headers: parsed.headers,
      properties: Map.unmodifiable(item.properties),
      subtitles: List.unmodifiable(item.subtitles),
      inputStreamAddon: property([
        'inputstream',
        'inputstreamaddon',
        'inputstream.adaptive',
      ]),
      manifestType: property([
        'inputstream.adaptive.manifest_type',
        'inputstream.adaptive.manifest_type',
      ]),
      drmLicenseKey: property([
        'inputstream.adaptive.license_key',
        'inputstream.adaptive.license_key',
      ]),
    );
  }

  static _KodiUrlParts _parseKodiUrl(String rawValue) {
    final separator = rawValue.indexOf('|');
    if (separator < 0) {
      return _KodiUrlParts(uri: rawValue, headers: const {});
    }

    final uri = rawValue.substring(0, separator);
    final rawHeaders = rawValue.substring(separator + 1);
    final headers = <String, String>{};

    for (final pair in rawHeaders.split('&')) {
      if (pair.trim().isEmpty) {
        continue;
      }
      final equals = pair.indexOf('=');
      if (equals < 0) {
        continue;
      }
      final rawKey = pair.substring(0, equals);
      final rawHeaderValue = pair.substring(equals + 1);
      try {
        headers[Uri.decodeComponent(rawKey)] = Uri.decodeComponent(rawHeaderValue);
      } on FormatException {
        headers[rawKey] = rawHeaderValue;
      }
    }

    return _KodiUrlParts(
      uri: uri,
      headers: Map.unmodifiable(headers),
    );
  }
}

class _KodiUrlParts {
  const _KodiUrlParts({required this.uri, required this.headers});

  final String uri;
  final Map<String, String> headers;
}
