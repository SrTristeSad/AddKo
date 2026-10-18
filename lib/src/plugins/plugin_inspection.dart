import 'dart:convert';
import 'dart:io';

import 'package:addko/src/plugins/plugin_manager.dart';
import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:archive/archive.dart';

class PluginPackagePreview {
  const PluginPackagePreview({
    required this.manifest,
    required this.packageBytes,
    required this.extractedBytes,
    required this.entryCount,
  });

  final PluginManifest manifest;
  final int packageBytes;
  final int extractedBytes;
  final int entryCount;
}

Future<PluginPackagePreview> inspectAddkoFile(File file) async {
  final length = await file.length();
  if (length > PluginManager.maxPackageBytes) {
    throw const PluginPackageException(
      'Pacote .addko excede o limite de 16 MiB.',
    );
  }
  return inspectAddkoBytes(await file.readAsBytes());
}

PluginPackagePreview inspectAddkoBytes(List<int> packageBytes) {
  if (packageBytes.isEmpty) {
    throw const PluginPackageException('Pacote .addko vazio.');
  }
  if (packageBytes.length > PluginManager.maxPackageBytes) {
    throw const PluginPackageException(
      'Pacote .addko excede o limite de 16 MiB.',
    );
  }

  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(packageBytes, verify: true);
  } on Object catch (error) {
    throw PluginPackageException('ZIP .addko inválido: $error');
  }

  if (archive.isEmpty) {
    throw const PluginPackageException('Pacote .addko não contém arquivos.');
  }
  if (archive.length > PluginManager.maxEntries) {
    throw const PluginPackageException(
      'Pacote .addko contém arquivos demais.',
    );
  }

  ArchiveFile? manifestEntry;
  final paths = <String>{};
  var extractedBytes = 0;

  for (final entry in archive) {
    if (entry.isSymbolicLink) {
      throw const PluginPackageException(
        'Links simbólicos não são permitidos em pacotes .addko.',
      );
    }

    final safePath = _safeArchivePath(
      entry.name,
      isDirectory: entry.isDirectory,
    );
    if (!paths.add(safePath.toLowerCase())) {
      throw PluginPackageException('Caminho duplicado no pacote: $safePath');
    }

    if (entry.isFile) {
      if (entry.size < 0 || entry.size > PluginManager.maxSingleFileBytes) {
        throw PluginPackageException(
          'Arquivo excede o limite permitido: $safePath',
        );
      }
      extractedBytes += entry.size;
      if (extractedBytes > PluginManager.maxExtractedBytes) {
        throw const PluginPackageException(
          'Pacote expandido excede o limite de 32 MiB.',
        );
      }
    }

    if (safePath == 'manifest.json' && entry.isFile) {
      manifestEntry = entry;
    }
  }

  if (manifestEntry == null) {
    throw const PluginPackageException(
      'manifest.json é obrigatório na raiz do pacote.',
    );
  }
  if (manifestEntry.size > PluginManager.maxManifestBytes) {
    throw const PluginPackageException('manifest.json é grande demais.');
  }

  final bytes = manifestEntry.readBytes();
  if (bytes == null) {
    throw const PluginPackageException('Não foi possível ler manifest.json.');
  }

  final String source;
  try {
    source = utf8.decode(bytes, allowMalformed: false);
  } on Object catch (error) {
    throw PluginPackageException(
      'manifest.json não está em UTF-8 válido: $error',
    );
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on Object catch (error) {
    throw PluginPackageException('manifest.json inválido: $error');
  }
  if (decoded is! Map) {
    throw const PluginPackageException(
      'manifest.json deve conter um objeto JSON.',
    );
  }

  final json = <String, Object?>{};
  for (final entry in decoded.entries) {
    if (entry.key is! String) {
      throw const PluginPackageException(
        'manifest.json contém uma chave inválida.',
      );
    }
    json[entry.key as String] = entry.value;
  }

  final PluginManifest manifest;
  try {
    manifest = PluginManifest.fromJson(json);
  } on FormatException catch (error) {
    throw PluginPackageException(error.message);
  }

  final entryPath = manifest.entry.toLowerCase();
  final matchingEntry = archive.any((entry) {
    if (!entry.isFile) return false;
    return _safeArchivePath(entry.name, isDirectory: false).toLowerCase() ==
        entryPath;
  });
  if (!matchingEntry) {
    throw PluginPackageException(
      'Entrypoint não encontrado no pacote: ${manifest.entry}',
    );
  }

  return PluginPackagePreview(
    manifest: manifest,
    packageBytes: packageBytes.length,
    extractedBytes: extractedBytes,
    entryCount: archive.length,
  );
}

String _safeArchivePath(String raw, {required bool isDirectory}) {
  if (raw.isEmpty ||
      raw.length > 512 ||
      raw.startsWith('/') ||
      raw.contains(r'\') ||
      raw.codeUnits.contains(0) ||
      RegExp(r'^[A-Za-z]:').hasMatch(raw)) {
    throw PluginPackageException('Caminho inseguro no pacote: $raw');
  }

  var value = raw;
  if (isDirectory) {
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
  }
  if (value.isEmpty) {
    throw const PluginPackageException(
      'Diretório raiz explícito não é permitido no pacote.',
    );
  }

  final segments = value.split('/');
  for (final segment in segments) {
    if (segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.length > 255 ||
        segment.contains(':')) {
      throw PluginPackageException('Caminho inseguro no pacote: $raw');
    }
  }
  return segments.join('/');
}
