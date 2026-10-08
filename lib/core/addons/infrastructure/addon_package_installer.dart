import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../domain/installed_addon.dart';
import 'addon_manifest_parser.dart';

class AddonInstallException implements Exception {
  const AddonInstallException(this.message);

  final String message;

  @override
  String toString() => 'AddonInstallException: $message';
}

class AddonPackageInstaller {
  AddonPackageInstaller({
    http.Client? client,
    this.manifestParser = const AddonManifestParser(),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const int _maxDownloadBytes = 256 * 1024 * 1024;
  static const int _maxExpandedBytes = 512 * 1024 * 1024;

  final http.Client _client;
  final bool _ownsClient;
  final AddonManifestParser manifestParser;

  Future<InstalledAddon> installFromUri({
    required Uri packageUri,
    required Directory addonsRoot,
    String? expectedAddonId,
    String? expectedVersion,
  }) async {
    final response = await _client.get(
      packageUri,
      headers: const {'User-Agent': 'AddKo/0.1.0'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AddonInstallException(
        'HTTP ${response.statusCode} ao baixar $packageUri.',
      );
    }
    if (response.bodyBytes.length > _maxDownloadBytes) {
      throw const AddonInstallException(
        'O pacote ultrapassa o limite de download de 256 MB.',
      );
    }

    return installBytes(
      bytes: response.bodyBytes,
      addonsRoot: addonsRoot,
      expectedAddonId: expectedAddonId,
      expectedVersion: expectedVersion,
    );
  }

  Future<InstalledAddon> installBytes({
    required List<int> bytes,
    required Directory addonsRoot,
    String? expectedAddonId,
    String? expectedVersion,
  }) async {
    if (bytes.isEmpty) {
      throw const AddonInstallException('O pacote ZIP está vazio.');
    }
    if (bytes.length > _maxDownloadBytes) {
      throw const AddonInstallException(
        'O pacote ZIP ultrapassa o limite de 256 MB.',
      );
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } on Object catch (error) {
      throw AddonInstallException('ZIP inválido: $error');
    }

    final manifestFile = _findManifest(archive);
    final manifestText = _decodeArchiveFile(manifestFile.file);
    final manifest = manifestParser.parse(manifestText);

    if (expectedAddonId != null &&
        manifest.id.toLowerCase() != expectedAddonId.toLowerCase()) {
      throw AddonInstallException(
        'O pacote baixado declara ${manifest.id}, mas era esperado $expectedAddonId.',
      );
    }
    if (expectedVersion != null && manifest.version != expectedVersion) {
      throw AddonInstallException(
        'O pacote ${manifest.id} declara versão ${manifest.version}, mas o índice anunciou $expectedVersion.',
      );
    }

    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(manifest.id)) {
      throw AddonInstallException(
        'O id do addon contém caracteres inseguros: ${manifest.id}',
      );
    }

    final expandedSize = archive.files.fold<int>(
      0,
      (sum, file) => sum + (file.isFile ? file.size : 0),
    );
    if (expandedSize > _maxExpandedBytes) {
      throw const AddonInstallException(
        'O conteúdo expandido do pacote ultrapassa 512 MB.',
      );
    }

    await addonsRoot.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final staging = Directory(
      p.join(addonsRoot.path, '.staging-${manifest.id}-$stamp'),
    );
    final target = Directory(p.join(addonsRoot.path, manifest.id));
    final backup = Directory(
      p.join(addonsRoot.path, '.backup-${manifest.id}-$stamp'),
    );

    try {
      await staging.create(recursive: true);
      await _extractArchive(
        archive: archive,
        rootPrefix: manifestFile.rootPrefix,
        destination: staging,
      );

      final stagedManifest = File(p.join(staging.path, 'addon.xml'));
      if (!await stagedManifest.exists()) {
        throw const AddonInstallException(
          'O pacote não gerou addon.xml na raiz do addon.',
        );
      }

      await _moveExistingAside(target, backup);

      try {
        await staging.rename(target.path);
      } on FileSystemException catch (error) {
        // Android can report ENOENT if another install from an older build was
        // still finishing. Re-check the filesystem before deciding whether the
        // replacement really failed.
        if (await target.exists()) {
          await target.delete(recursive: true);
          await staging.rename(target.path);
        } else {
          if (await backup.exists()) {
            await backup.rename(target.path);
          }
          rethrow;
        }
      } on Object {
        if (await backup.exists() && !await target.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }

      if (await backup.exists()) {
        await backup.delete(recursive: true);
      }

      return InstalledAddon(
        manifest: manifest,
        installPath: target.path,
      );
    } on AddonInstallException {
      rethrow;
    } on Object catch (error) {
      throw AddonInstallException('Falha ao instalar ${manifest.id}: $error');
    } finally {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      if (await backup.exists() && await target.exists()) {
        await backup.delete(recursive: true);
      }
    }
  }

  Future<void> _moveExistingAside(
    Directory target,
    Directory backup,
  ) async {
    if (!await target.exists()) {
      return;
    }

    try {
      await target.rename(backup.path);
    } on FileSystemException {
      // exists() and rename() are separate syscalls. If the directory vanished
      // between them, another operation already removed it and we can proceed.
      if (!await target.exists()) {
        return;
      }
      rethrow;
    }
  }

  _ManifestArchiveFile _findManifest(Archive archive) {
    final candidates = <_ManifestArchiveFile>[];

    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final normalized = file.name.replaceAll('\\', '/');
      if (normalized == 'addon.xml') {
        candidates.add(_ManifestArchiveFile(file: file, rootPrefix: ''));
      } else if (normalized.endsWith('/addon.xml')) {
        final prefix = normalized.substring(
          0,
          normalized.length - '/addon.xml'.length,
        );
        candidates.add(_ManifestArchiveFile(file: file, rootPrefix: prefix));
      }
    }

    if (candidates.isEmpty) {
      throw const AddonInstallException('O ZIP não contém addon.xml.');
    }

    candidates.sort(
      (left, right) => _depth(left.rootPrefix).compareTo(_depth(right.rootPrefix)),
    );
    return candidates.first;
  }

  Future<void> _extractArchive({
    required Archive archive,
    required String rootPrefix,
    required Directory destination,
  }) async {
    final prefix = rootPrefix.isEmpty ? '' : '$rootPrefix/';

    for (final file in archive.files) {
      var archiveName = file.name.replaceAll('\\', '/');
      if (prefix.isNotEmpty) {
        if (!archiveName.startsWith(prefix)) {
          continue;
        }
        archiveName = archiveName.substring(prefix.length);
      }

      if (archiveName.isEmpty) {
        continue;
      }

      final safeRelativePath = _safeRelativePath(archiveName);
      if (safeRelativePath == null) {
        throw AddonInstallException(
          'O ZIP contém um caminho inseguro: ${file.name}',
        );
      }

      final outputPath = p.join(destination.path, safeRelativePath);
      if (file.isFile) {
        final output = File(outputPath);
        await output.parent.create(recursive: true);
        final content = List<int>.from(file.content as List<int>);
        await output.writeAsBytes(content, flush: true);
      } else {
        await Directory(outputPath).create(recursive: true);
      }
    }
  }

  String? _safeRelativePath(String value) {
    final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
    if (normalized == '.' ||
        normalized.startsWith('../') ||
        normalized == '..' ||
        normalized.startsWith('/') ||
        p.posix.isAbsolute(normalized)) {
      return null;
    }

    final segments = p.posix.split(normalized);
    if (segments.any((segment) => segment == '..' || segment.isEmpty)) {
      return null;
    }

    return p.joinAll(segments);
  }

  String _decodeArchiveFile(ArchiveFile file) {
    try {
      return utf8.decode(List<int>.from(file.content as List<int>));
    } on Object catch (error) {
      throw AddonInstallException('addon.xml não está em UTF-8 válido: $error');
    }
  }

  int _depth(String prefix) {
    if (prefix.isEmpty) {
      return 0;
    }
    return prefix.split('/').where((segment) => segment.isNotEmpty).length;
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class _ManifestArchiveFile {
  const _ManifestArchiveFile({
    required this.file,
    required this.rootPrefix,
  });

  final ArchiveFile file;
  final String rootPrefix;
}
