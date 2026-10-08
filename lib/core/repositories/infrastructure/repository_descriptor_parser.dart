import 'package:xml/xml.dart';

import '../domain/repository_descriptor.dart';

class RepositoryDescriptorFormatException implements Exception {
  const RepositoryDescriptorFormatException(this.message);

  final String message;

  @override
  String toString() => 'RepositoryDescriptorFormatException: $message';
}

class RepositoryDescriptorParser {
  const RepositoryDescriptorParser();

  RepositoryDescriptor parse(String source) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(source);
    } on XmlParserException catch (error) {
      throw RepositoryDescriptorFormatException(
        'XML inválido: ${error.message}',
      );
    }

    final addon = document.rootElement;
    if (addon.name.local != 'addon') {
      throw const RepositoryDescriptorFormatException(
        'O elemento raiz precisa ser <addon>.',
      );
    }

    final addonId = addon.getAttribute('id')?.trim();
    final name = addon.getAttribute('name')?.trim();
    if (addonId == null || addonId.isEmpty || name == null || name.isEmpty) {
      throw const RepositoryDescriptorFormatException(
        'Repositório sem id ou nome.',
      );
    }

    XmlElement? repositoryExtension;
    for (final extension in addon.findElements('extension')) {
      if (extension.getAttribute('point') == 'xbmc.addon.repository') {
        repositoryExtension = extension;
        break;
      }
    }

    if (repositoryExtension == null) {
      throw const RepositoryDescriptorFormatException(
        'O addon não declara xbmc.addon.repository.',
      );
    }

    final endpoints = <RepositoryEndpoint>[];
    for (final directory in repositoryExtension.findElements('dir')) {
      final info = directory.getElement('info');
      final data = directory.getElement('datadir');
      if (info == null || data == null) {
        continue;
      }

      final infoUri = Uri.tryParse(info.innerText.trim());
      final dataUri = Uri.tryParse(data.innerText.trim());
      final checksumText = directory.getElement('checksum')?.innerText.trim();
      final checksumUri = checksumText == null || checksumText.isEmpty
          ? null
          : Uri.tryParse(checksumText);

      if (infoUri == null || dataUri == null) {
        continue;
      }

      endpoints.add(
        RepositoryEndpoint(
          infoUri: infoUri,
          dataUri: dataUri,
          checksumUri: checksumUri,
          compressed: _parseBool(info.getAttribute('compressed')),
          zipPackages: _parseBool(data.getAttribute('zip')),
          minimumVersion: _nullableTrimmed(
            directory.getAttribute('minversion'),
          ),
          maximumVersion: _nullableTrimmed(
            directory.getAttribute('maxversion'),
          ),
        ),
      );
    }

    if (endpoints.isEmpty) {
      throw const RepositoryDescriptorFormatException(
        'Nenhum endpoint válido foi encontrado no repositório.',
      );
    }

    return RepositoryDescriptor(
      addonId: addonId,
      name: name,
      endpoints: List.unmodifiable(endpoints),
    );
  }

  bool _parseBool(String? value) {
    if (value == null) {
      return false;
    }
    return value.toLowerCase() == 'true' || value == '1';
  }

  String? _nullableTrimmed(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
