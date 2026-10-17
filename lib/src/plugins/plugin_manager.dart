import 'dart:convert';
import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/plugins/plugin_package.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

class PluginManager {
  PluginManager(this.rootDirectory);

  static const int maxPackageBytes = 16 * 1024 * 1024;
  static const int maxExtractedBytes = 32 * 1024 * 1024;
  static const int maxSingleFileBytes = 8 * 1024 * 1024;
  static const int maxManifestBytes = 64 * 1024;
  static const int maxEntries = 512;

  final Directory rootDirectory;

  static Future<PluginManager> openDefault() async {
    final support = await getApplicationSupportDirectory();
    return PluginManager(
      Directory(_joinFileSystemPath(support.path, 'plugins')),
    );
  }

  Future<List<InstalledPlugin>> listInstalled() async {
    if (!await rootDirectory.exists()) {
      return const <InstalledPlugin>[];
    }

    final plugins = <InstalledPlugin>[];
    await for (final entity in rootDirectory.list(followLinks: false)) {
      if (entity is! Directory) continue;

      final directoryName = _basename(entity.path);
      if (directoryName.startsWith('.')) continue;

      try {
        final manifestFile = File(
          _joinFileSystemPath(entity.path, 'manifest.json'),
        );
        if (!await manifestFile.exists()) continue;

        final manifest = _parseManifest(
          await manifestFile.readAsBytes(),
        );
        if (manifest.id != directoryName) continue;

        final entryFile = File(
          resolvePluginPath(entity.path, manifest.entry),
        );
        if (!await entryFile.exists()) continue;

        plugins.add(
          InstalledPlugin(directory: entity, manifest: manifest),
        );
      } on Object {
        continue;
      }
    }

    plugins.sort(
      (a, b) => a.manifest.name.toLowerCase().compareTo(
            b.manifest.name.toLowerCase(),
          ),
    );
    return List.unmodifiable(plugins);
  }

  Future<InstalledPlugin> installFile(File packageFile) async {
    final length = await packageFile.length();
    if (length > maxPackageBytes) {
      throw const PluginPackageException(
        'Pacote .addko excede o limite de 16 MiB.',
      );
    }
    return installBytes(await packageFile.readAsBytes());
  }

  Future<InstalledPlugin> installBytes(List<int> packageBytes) async {
    if (packageBytes.isEmpty) {
      throw const PluginPackageException('Pacote .addko vazio.');
    }
    if (packageBytes.length > maxPackageBytes) {
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
    if (archive.length > maxEntries) {
      throw const PluginPackageException(
        'Pacote .addko contém arquivos demais.',
      );
    }

    final records = <_ArchiveRecord>[];
    final exactPaths = <String>{};
    final caseInsensitivePaths = <String>{};
    var totalSize = 0;

    for (final entry in archive) {
      if (entry.isSymbolicLink) {
        throw const PluginPackageException(
          'Links simbólicos não são permitidos em pacotes .addko.',
        );
      }

      final path = _validateArchivePath(
        entry.name,
        isDirectory: entry.isDirectory,
      );
      final foldedPath = path.toLowerCase();

      if (!caseInsensitivePaths.add(foldedPath)) {
        throw PluginPackageException('Caminho duplicado no pacote: $path');
      }
      exactPaths.add(path);

      if (entry.isFile) {
        if (entry.size < 0 || entry.size > maxSingleFileBytes) {
          throw PluginPackageException(
            'Arquivo excede o limite permitido: $path',
          );
        }

        totalSize += entry.size;
        if (totalSize > maxExtractedBytes) {
          throw const PluginPackageException(
            'Pacote expandido excede o limite de 32 MiB.',
          );
        }
      }

      records.add(_ArchiveRecord(path: path, entry: entry));
    }

    _ArchiveRecord? manifestRecord;
    for (final record in records) {
      if (record.path == 'manifest.json' && record.entry.isFile) {
        manifestRecord = record;
        break;
      }
    }
    if (manifestRecord == null) {
      throw const PluginPackageException(
        'manifest.json é obrigatório na raiz do pacote.',
      );
    }
    if (manifestRecord.entry.size > maxManifestBytes) {
      throw const PluginPackageException('manifest.json é grande demais.');
    }

    final manifestBytes = manifestRecord.entry.readBytes();
    if (manifestBytes == null) {
      throw const PluginPackageException(
        'Não foi possível ler manifest.json.',
      );
    }

    final manifest = _parseManifest(manifestBytes);
    if (!exactPaths.contains(manifest.entry)) {
      throw PluginPackageException(
        'Entrypoint não encontrado no pacote: ${manifest.entry}',
      );
    }

    final entryRecord = records.firstWhere(
      (record) => record.path == manifest.entry,
    );
    if (!entryRecord.entry.isFile) {
      throw PluginPackageException(
        'Entrypoint não é um arquivo: ${manifest.entry}',
      );
    }

    await rootDirectory.create(recursive: true);

    final nonce = DateTime.now().microsecondsSinceEpoch;
    final staging = Directory(
      _joinFileSystemPath(
        rootDirectory.path,
        '.${manifest.id}.installing-$nonce',
      ),
    );
    final destination = Directory(
      _joinFileSystemPath(rootDirectory.path, manifest.id),
    );
    final backup = Directory(
      _joinFileSystemPath(
        rootDirectory.path,
        '.${manifest.id}.backup-$nonce',
      ),
    );

    var oldMovedToBackup = false;
    try {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      await staging.create(recursive: true);

      for (final record in records) {
        final outputPath = resolvePluginPath(staging.path, record.path);
        if (record.entry.isDirectory) {
          await Directory(outputPath).create(recursive: true);
          continue;
        }

        final data = record.entry.readBytes();
        if (data == null || data.length != record.entry.size) {
          throw PluginPackageException(
            'Conteúdo inválido no arquivo: ${record.path}',
          );
        }

        final output = File(outputPath);
        await output.parent.create(recursive: true);
        await output.writeAsBytes(data, flush: true);
      }

      if (await destination.exists()) {
        await destination.rename(backup.path);
        oldMovedToBackup = true;
      }

      try {
        await staging.rename(destination.path);
      } on Object {
        if (oldMovedToBackup &&
            await backup.exists() &&
            !await destination.exists()) {
          await backup.rename(destination.path);
          oldMovedToBackup = false;
        }
        rethrow;
      }

      if (oldMovedToBackup && await backup.exists()) {
        try {
          await backup.delete(recursive: true);
        } on Object {
          // A nova versão já está ativa; o backup órfão pode ser limpo depois.
        }
      }

      return InstalledPlugin(
        directory: destination,
        manifest: manifest,
      );
    } on PluginPackageException {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    } on Object catch (error) {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      if (oldMovedToBackup &&
          await backup.exists() &&
          !await destination.exists()) {
        await backup.rename(destination.path);
      }
      throw PluginPackageException('Falha ao instalar pacote: $error');
    }
  }

  static PluginManifest _parseManifest(List<int> bytes) {
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

    try {
      return PluginManifest.fromJson(json);
    } on FormatException catch (error) {
      throw PluginPackageException(error.message);
    }
  }
}

class PluginPackageException implements Exception {
  const PluginPackageException(this.message);

  final String message;

  @override
  String toString() => 'PluginPackageException: $message';
}

class _ArchiveRecord {
  const _ArchiveRecord({
    required this.path,
    required this.entry,
  });

  final String path;
  final ArchiveFile entry;
}

String _validateArchivePath(String raw, {required bool isDirectory}) {
  if (raw.isEmpty ||
      raw.length > 512 ||
      raw.startsWith('/') ||
      raw.contains(r'\') ||
      raw.codeUnits.contains(0) ||
      RegExp(r'^[A-Za-z]:').hasMatch(raw)) {
    throw PluginPackageException('Caminho inseguro no pacote: $raw');
  }

  var path = raw;
  if (isDirectory) {
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
  }

  if (path.isEmpty) {
    throw const PluginPackageException(
      'Diretório raiz explícito não é permitido no pacote.',
    );
  }

  final segments = path.split('/');
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

String _joinFileSystemPath(String left, String right) {
  final separator = Platform.pathSeparator;
  return left.endsWith(separator) ? '$left$right' : '$left$separator$right';
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/');
  return parts.lastWhere((part) => part.isNotEmpty, orElse: () => '');
}
