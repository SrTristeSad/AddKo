import 'package:xml/xml.dart';

import '../domain/addon_dependency.dart';
import '../domain/addon_manifest.dart';

class AddonManifestFormatException implements Exception {
  const AddonManifestFormatException(this.message);

  final String message;

  @override
  String toString() => 'AddonManifestFormatException: $message';
}

class AddonManifestParser {
  const AddonManifestParser();

  AddonManifest parse(String source) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(source);
    } on XmlParserException catch (error) {
      throw AddonManifestFormatException('XML inválido: ${error.message}');
    }

    final root = document.rootElement;
    if (root.name.local != 'addon') {
      throw const AddonManifestFormatException(
        'O elemento raiz precisa ser <addon>.',
      );
    }

    final id = _requiredAttribute(root, 'id');
    final name = _requiredAttribute(root, 'name');
    final version = _requiredAttribute(root, 'version');
    final providerName = root.getAttribute('provider-name') ?? '';

    final dependencies = <AddonDependency>[];
    final requires = root.getElement('requires');
    if (requires != null) {
      for (final import in requires.findElements('import')) {
        final dependencyId = import.getAttribute('addon');
        if (dependencyId == null || dependencyId.trim().isEmpty) {
          continue;
        }

        dependencies.add(
          AddonDependency(
            id: dependencyId.trim(),
            version: _nullableTrimmed(import.getAttribute('version')),
            optional: _parseBool(import.getAttribute('optional')),
          ),
        );
      }
    }

    final extensions = <AddonExtension>[];
    for (final element in root.findElements('extension')) {
      final point = element.getAttribute('point');
      if (point == null || point.trim().isEmpty) {
        continue;
      }

      final attributes = <String, String>{};
      for (final attribute in element.attributes) {
        attributes[attribute.name.local] = attribute.value;
      }

      final provides = element
          .findElements('provides')
          .expand(
            (providesElement) => providesElement.innerText
                .split(RegExp(r'\s+'))
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty),
          )
          .toList(growable: false);

      extensions.add(
        AddonExtension(
          point: point.trim(),
          library: _nullableTrimmed(element.getAttribute('library')),
          attributes: Map.unmodifiable(attributes),
          provides: List.unmodifiable(provides),
        ),
      );
    }

    final metadata = root.findElements('extension').where(
          (element) => element.getAttribute('point') == 'xbmc.addon.metadata',
        );
    final metadataElement = metadata.isEmpty ? null : metadata.first;
    final assets = metadataElement?.getElement('assets');

    return AddonManifest(
      id: id,
      name: name,
      version: version,
      providerName: providerName,
      dependencies: List.unmodifiable(dependencies),
      extensions: List.unmodifiable(extensions),
      summary: _firstLocalizedText(metadataElement, 'summary'),
      description: _firstLocalizedText(metadataElement, 'description'),
      iconPath: _nullableTrimmed(assets?.getElement('icon')?.innerText),
      fanartPath: _nullableTrimmed(assets?.getElement('fanart')?.innerText),
    );
  }

  String _requiredAttribute(XmlElement element, String name) {
    final value = element.getAttribute(name);
    if (value == null || value.trim().isEmpty) {
      throw AddonManifestFormatException(
        'Atributo obrigatório "$name" não encontrado.',
      );
    }
    return value.trim();
  }

  String? _firstLocalizedText(XmlElement? parent, String elementName) {
    if (parent == null) {
      return null;
    }

    final values = parent.findElements(elementName);
    if (values.isEmpty) {
      return null;
    }

    return _nullableTrimmed(values.first.innerText);
  }

  String? _nullableTrimmed(String? value) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _parseBool(String? value) {
    if (value == null) {
      return false;
    }
    return value.toLowerCase() == 'true' || value == '1';
  }
}
