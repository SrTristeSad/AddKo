import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/plugins/plugin_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

typedef RepositoryFetcher = Future<List<int>> Function(Uri url, int maxBytes);

class RepositoryException implements Exception {
  const RepositoryException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RepositoryAddon {
  const RepositoryAddon({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.file,
    required this.sha256,
    required this.repository,
    this.category = 'Outros',
    this.icon,
    this.iconSha256,
  });
  final String id;
  final String name;
  final String version;
  final String description;
  final Uri file;
  final String sha256;
  final Uri repository;
  final String category;
  final Uri? icon;
  final String? iconSha256;
}

class RepositoryIndex {
  const RepositoryIndex({required this.url, required this.name, required this.addons});
  final Uri url;
  final String name;
  final List<RepositoryAddon> addons;
}

class RepositoryStatus {
  const RepositoryStatus({required this.url, this.index, this.error});
  final Uri url;
  final RepositoryIndex? index;
  final String? error;
}

class AddKoRepositoryManager {
  AddKoRepositoryManager(this.configFile, {RepositoryFetcher? fetcher})
      : _fetcher = fetcher ?? fetchHttps;

  static const int maxIndexBytes = 512 * 1024;
  static const int maxRepositories = 40;
  static const int maxAddons = 256;
  static const int maxIconBytes = 256 * 1024;
  static final RegExp _digestPattern = RegExp(r'^[0-9a-fA-F]{64}$');
  static final RegExp _relativePackagePattern =
      RegExp(r'^[a-zA-Z0-9_./-]+\.addko

  final File configFile;
  final RepositoryFetcher _fetcher;

  static Future<AddKoRepositoryManager> openDefault() async {
    final support = await getApplicationSupportDirectory();
    return AddKoRepositoryManager(
      File('${support.path}${Platform.pathSeparator}repositories.json'),
    );
  }

  static Uri parseRepositoryUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isEmpty ||
        !uri.path.toLowerCase().endsWith('.json') ||
        uri.host.length > 253 ||
        uri.toString().length > 2048 ||
        !_publicHostname(uri.host)) {
      throw const RepositoryException(
        'Informe a URL HTTPS direta de um índice JSON público.',
      );
    }
    return uri;
  }

  static bool _publicHostname(String host) {
    final value = host.toLowerCase();
    if (InternetAddress.tryParse(value) != null ||
        !value.contains('.') ||
        value.startsWith('.') ||
        value.endsWith('.') ||
        value.endsWith('.local') ||
        value.endsWith('.localhost') ||
        value.endsWith('.internal') ||
        value.endsWith('.home.arpa') ||
        value.endsWith('.test') ||
        value.endsWith('.invalid')) {
      return false;
    }
    return RegExp(r'^[a-z0-9.-]+$').hasMatch(value);
  }

  Future<List<Uri>> savedUrls() async {
    if (!await configFile.exists()) return <Uri>[];
    if (await configFile.length() > 64 * 1024) {
      throw const RepositoryException('Arquivo de repositórios grande demais.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(await configFile.readAsString());
    } on Object {
      throw const RepositoryException('Lista de repositórios corrompida.');
    }
    if (decoded is! List || decoded.length > maxRepositories) {
      throw const RepositoryException('Lista de repositórios inválida.');
    }
    final urls = <Uri>[];
    final seen = <String>{};
    for (final value in decoded) {
      if (value is! String) {
        throw const RepositoryException('URL de repositório inválida.');
      }
      final url = parseRepositoryUrl(value);
      if (!seen.add(url.toString())) {
        throw const RepositoryException('Repositório duplicado no arquivo.');
      }
      urls.add(url);
    }
    return urls;
  }

  Future<RepositoryIndex> add(String source) async {
    final url = parseRepositoryUrl(source);
    final existing = await savedUrls();
    if (existing.any((item) => item == url)) {
      throw const RepositoryException('Esse repositório já está cadastrado.');
    }
    if (existing.length >= maxRepositories) {
      throw const RepositoryException('Limite de repositórios atingido.');
    }
    final index = await loadIndex(url);
    await _persist(<Uri>[...existing, url]);
    return index;
  }

  Future<void> remove(Uri url) async {
    final existing = await savedUrls();
    await _persist(existing.where((item) => item != url).toList());
  }

  Future<void> _persist(List<Uri> urls) async {
    await configFile.parent.create(recursive: true);
    final temp = File('${configFile.path}.tmp');
    try {
      await temp.writeAsString(
        jsonEncode(urls.map((url) => url.toString()).toList()),
        flush: true,
      );
      await temp.rename(configFile.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<List<RepositoryStatus>> refresh() async {
    final urls = await savedUrls();
    final statuses = <RepositoryStatus>[];
    for (final url in urls) {
      try {
        statuses.add(RepositoryStatus(url: url, index: await loadIndex(url)));
      } on Object catch (error) {
        statuses.add(RepositoryStatus(url: url, error: '$error'));
      }
    }
    return statuses;
  }

  Future<RepositoryIndex> loadIndex(Uri url) async {
    final bytes = await _fetcher(url, maxIndexBytes);
    if (bytes.length > maxIndexBytes) {
      throw const RepositoryException('Índice excede o limite de 512 KiB.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object {
      throw const RepositoryException('Índice JSON inválido ou não UTF-8.');
    }
    if (decoded is! Map ||
        decoded['schema'] != 1 ||
        decoded['name'] is! String ||
        decoded['addons'] is! List) {
      throw const RepositoryException('Índice não segue o esquema AddKo v1.');
    }
    final name = (decoded['name'] as String).trim();
    if (name.isEmpty || name.length > 120) {
      throw const RepositoryException('Nome de repositório inválido.');
    }
    final rawAddons = decoded['addons'] as List;
    if (rawAddons.length > maxAddons) {
      throw const RepositoryException('Índice contém addons demais.');
    }
    final addons = <RepositoryAddon>[];
    final ids = <String>{};
    for (final raw in rawAddons) {
      if (raw is! Map) {
        throw const RepositoryException('Entrada de addon inválida.');
      }
      final id = raw['id'];
      final title = raw['name'];
      final version = raw['version'];
      final file = raw['file'];
      final sha = raw['sha256'];
      final description = raw['description'] ?? '';
      final category = raw['category'] ?? 'Outros';
      final icon = raw['icon'];
      final iconSha = raw['icon_sha256'];
      if (id is! String ||
          title is! String ||
          version is! String ||
          file is! String ||
          sha is! String ||
          description is! String ||
          description.length > 512 ||
          category is! String ||
          category.trim().isEmpty ||
          category.trim().length > 40 ||
          category.runes.any((unit) => unit < 32 || unit == 127) ||
          !_digestPattern.hasMatch(sha)) {
        throw const RepositoryException('Metadados de addon inválidos.');
      }
      try {
        PluginManifest.fromJson(<String, Object?>{
          'id': id,
          'name': title,
          'version': version,
          'entry': 'main.lua',
          'permissions': <Object?>[],
        });
      } on FormatException {
        throw RepositoryException('ID, nome ou versão inválidos: $id');
      }
      if (!ids.add(id)) {
        throw RepositoryException('ID duplicado no catálogo: $id');
      }
      final package = _resolveCatalogAsset(
        url,
        file,
        _relativePackagePattern,
        id,
      );
      Uri? iconUrl;
      String? iconDigest;
      if (icon != null || iconSha != null) {
        if (icon is! String ||
            iconSha is! String ||
            !_digestPattern.hasMatch(iconSha)) {
          throw RepositoryException('Ícone sem SHA-256 válido: $id');
        }
        iconUrl = _resolveCatalogAsset(
          url,
          icon,
          _relativeIconPattern,
          id,
        );
        iconDigest = iconSha.toLowerCase();
      }
      addons.add(RepositoryAddon(
        id: id,
        name: title,
        version: version,
        description: description,
        file: package,
        sha256: sha.toLowerCase(),
        repository: url,
        category: category.trim(),
        icon: iconUrl,
        iconSha256: iconDigest,
      ));
    }
    return RepositoryIndex(
      url: url,
      name: name,
      addons: List<RepositoryAddon>.unmodifiable(addons),
    );
  }


  static Uri _resolveCatalogAsset(
    Uri repository,
    String relative,
    RegExp pattern,
    String addonId,
  ) {
    if (relative.length > 300 ||
        !pattern.hasMatch(relative) ||
        relative.startsWith('/') ||
        relative.split('/').any(
          (part) => part.isEmpty || part == '.' || part == '..',
        )) {
      throw RepositoryException('Caminho de arquivo inseguro: $addonId');
    }
    final resolved = repository.resolve(relative);
    if (resolved.scheme != 'https' ||
        resolved.host != repository.host ||
        resolved.port != repository.port ||
        resolved.userInfo.isNotEmpty ||
        resolved.hasQuery ||
        resolved.hasFragment) {
      throw RepositoryException('Arquivo fora da origem autorizada: $addonId');
    }
    return resolved;
  }

  Future<Uint8List?> downloadIcon(RepositoryAddon addon) async {
    final uri = addon.icon;
    final expectedHash = addon.iconSha256;
    if (uri == null || expectedHash == null) return null;
    final bytes = await _fetcher(uri, maxIconBytes);
    if (bytes.isEmpty ||
        bytes.length > maxIconBytes ||
        sha256.convert(bytes).toString() != expectedHash) {
      throw const RepositoryException('Ícone inválido ou adulterado.');
    }
    final isPng = bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e &&
        bytes[3] == 0x47 && bytes[4] == 0x0d && bytes[5] == 0x0a &&
        bytes[6] == 0x1a && bytes[7] == 0x0a;
    final isJpeg = bytes.length >= 3 &&
        bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final isWebp = bytes.length >= 12 &&
        utf8.decode(bytes.sublist(0, 4)) == 'RIFF' &&
        utf8.decode(bytes.sublist(8, 12)) == 'WEBP';
    if (!isPng && !isJpeg && !isWebp) {
      throw const RepositoryException('Formato de ícone não suportado.');
    }
    return Uint8List.fromList(bytes);
  }

  Future<List<int>> download(RepositoryAddon addon) async {
    final bytes = await _fetcher(addon.file, PluginManager.maxPackageBytes);
    if (bytes.isEmpty || bytes.length > PluginManager.maxPackageBytes) {
      throw const RepositoryException('Tamanho do pacote .addko inválido.');
    }
    if (sha256.convert(bytes).toString() != addon.sha256) {
      throw const RepositoryException(
        'SHA-256 do pacote não confere com o índice. Instalação bloqueada.',
      );
    }
    return bytes;
  }

  static Future<List<int>> fetchHttps(Uri uri, int limit) async {
    if (uri.scheme != 'https' || !_publicHostname(uri.host)) {
      throw const RepositoryException('Somente origens HTTPS públicas são aceitas.');
    }
    final addresses = await InternetAddress.lookup(uri.host)
        .timeout(const Duration(seconds: 8));
    if (addresses.isEmpty || addresses.any((address) => !_isPublicAddress(address))) {
      throw const RepositoryException('Destino de rede local ou privado bloqueado.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw RepositoryException('Servidor retornou HTTP ${response.statusCode}.');
      }
      if (response.contentLength > limit) {
        throw const RepositoryException('Download excede o tamanho permitido.');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > limit) {
          throw const RepositoryException('Download excede o tamanho permitido.');
        }
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  static bool _isPublicAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal || address.isMulticast) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      final a = bytes[0];
      final b = bytes[1];
      return !(a == 0 ||
          a == 10 ||
          a == 127 ||
          a >= 224 ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 100 && b >= 64 && b <= 127) ||
          (a == 198 && (b == 18 || b == 19)));
    }
    if (bytes.length == 16) {
      if (bytes.every((b) => b == 0) || (bytes[0] & 0xfe) == 0xfc ||
          (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80)) {
        return false;
      }
      if (bytes.take(10).every((b) => b == 0) &&
          bytes[10] == 255 && bytes[11] == 255) {
        return false;
      }
    }
    return true;
  }
}
);
  static final RegExp _relativeIconPattern =
      RegExp(r'^[a-zA-Z0-9_./-]+\.(?:png|jpg|jpeg|webp)

  final File configFile;
  final RepositoryFetcher _fetcher;

  static Future<AddKoRepositoryManager> openDefault() async {
    final support = await getApplicationSupportDirectory();
    return AddKoRepositoryManager(
      File('${support.path}${Platform.pathSeparator}repositories.json'),
    );
  }

  static Uri parseRepositoryUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isEmpty ||
        !uri.path.toLowerCase().endsWith('.json') ||
        uri.host.length > 253 ||
        uri.toString().length > 2048 ||
        !_publicHostname(uri.host)) {
      throw const RepositoryException(
        'Informe a URL HTTPS direta de um índice JSON público.',
      );
    }
    return uri;
  }

  static bool _publicHostname(String host) {
    final value = host.toLowerCase();
    if (InternetAddress.tryParse(value) != null ||
        !value.contains('.') ||
        value.startsWith('.') ||
        value.endsWith('.') ||
        value.endsWith('.local') ||
        value.endsWith('.localhost') ||
        value.endsWith('.internal') ||
        value.endsWith('.home.arpa') ||
        value.endsWith('.test') ||
        value.endsWith('.invalid')) {
      return false;
    }
    return RegExp(r'^[a-z0-9.-]+$').hasMatch(value);
  }

  Future<List<Uri>> savedUrls() async {
    if (!await configFile.exists()) return <Uri>[];
    if (await configFile.length() > 64 * 1024) {
      throw const RepositoryException('Arquivo de repositórios grande demais.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(await configFile.readAsString());
    } on Object {
      throw const RepositoryException('Lista de repositórios corrompida.');
    }
    if (decoded is! List || decoded.length > maxRepositories) {
      throw const RepositoryException('Lista de repositórios inválida.');
    }
    final urls = <Uri>[];
    final seen = <String>{};
    for (final value in decoded) {
      if (value is! String) {
        throw const RepositoryException('URL de repositório inválida.');
      }
      final url = parseRepositoryUrl(value);
      if (!seen.add(url.toString())) {
        throw const RepositoryException('Repositório duplicado no arquivo.');
      }
      urls.add(url);
    }
    return urls;
  }

  Future<RepositoryIndex> add(String source) async {
    final url = parseRepositoryUrl(source);
    final existing = await savedUrls();
    if (existing.any((item) => item == url)) {
      throw const RepositoryException('Esse repositório já está cadastrado.');
    }
    if (existing.length >= maxRepositories) {
      throw const RepositoryException('Limite de repositórios atingido.');
    }
    final index = await loadIndex(url);
    await _persist(<Uri>[...existing, url]);
    return index;
  }

  Future<void> remove(Uri url) async {
    final existing = await savedUrls();
    await _persist(existing.where((item) => item != url).toList());
  }

  Future<void> _persist(List<Uri> urls) async {
    await configFile.parent.create(recursive: true);
    final temp = File('${configFile.path}.tmp');
    try {
      await temp.writeAsString(
        jsonEncode(urls.map((url) => url.toString()).toList()),
        flush: true,
      );
      await temp.rename(configFile.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<List<RepositoryStatus>> refresh() async {
    final urls = await savedUrls();
    final statuses = <RepositoryStatus>[];
    for (final url in urls) {
      try {
        statuses.add(RepositoryStatus(url: url, index: await loadIndex(url)));
      } on Object catch (error) {
        statuses.add(RepositoryStatus(url: url, error: '$error'));
      }
    }
    return statuses;
  }

  Future<RepositoryIndex> loadIndex(Uri url) async {
    final bytes = await _fetcher(url, maxIndexBytes);
    if (bytes.length > maxIndexBytes) {
      throw const RepositoryException('Índice excede o limite de 512 KiB.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object {
      throw const RepositoryException('Índice JSON inválido ou não UTF-8.');
    }
    if (decoded is! Map ||
        decoded['schema'] != 1 ||
        decoded['name'] is! String ||
        decoded['addons'] is! List) {
      throw const RepositoryException('Índice não segue o esquema AddKo v1.');
    }
    final name = (decoded['name'] as String).trim();
    if (name.isEmpty || name.length > 120) {
      throw const RepositoryException('Nome de repositório inválido.');
    }
    final rawAddons = decoded['addons'] as List;
    if (rawAddons.length > maxAddons) {
      throw const RepositoryException('Índice contém addons demais.');
    }
    final addons = <RepositoryAddon>[];
    final ids = <String>{};
    for (final raw in rawAddons) {
      if (raw is! Map) {
        throw const RepositoryException('Entrada de addon inválida.');
      }
      final id = raw['id'];
      final title = raw['name'];
      final version = raw['version'];
      final file = raw['file'];
      final sha = raw['sha256'];
      final description = raw['description'] ?? '';
      if (id is! String ||
          title is! String ||
          version is! String ||
          file is! String ||
          sha is! String ||
          description is! String ||
          description.length > 512 ||
          !_digestPattern.hasMatch(sha)) {
        throw const RepositoryException('Metadados de addon inválidos.');
      }
      try {
        PluginManifest.fromJson(<String, Object?>{
          'id': id,
          'name': title,
          'version': version,
          'entry': 'main.lua',
          'permissions': <Object?>[],
        });
      } on FormatException {
        throw RepositoryException('ID, nome ou versão inválidos: $id');
      }
      if (!ids.add(id)) {
        throw RepositoryException('ID duplicado no catálogo: $id');
      }
      if (file.length > 300 ||
          !_relativePackagePattern.hasMatch(file) ||
          file.startsWith('/') ||
          file.split('/').any((part) => part == '.' || part == '..' || part.isEmpty)) {
        throw RepositoryException('Caminho de pacote inseguro: $id');
      }
      final package = url.resolve(file);
      if (package.scheme != 'https' ||
          package.host != url.host ||
          package.port != url.port ||
          package.userInfo.isNotEmpty ||
          package.hasQuery ||
          package.hasFragment) {
        throw RepositoryException('Pacote fora da origem autorizada: $id');
      }
      addons.add(RepositoryAddon(
        id: id,
        name: title,
        version: version,
        description: description,
        file: package,
        sha256: sha.toLowerCase(),
        repository: url,
      ));
    }
    return RepositoryIndex(
      url: url,
      name: name,
      addons: List<RepositoryAddon>.unmodifiable(addons),
    );
  }

  Future<List<int>> download(RepositoryAddon addon) async {
    final bytes = await _fetcher(addon.file, PluginManager.maxPackageBytes);
    if (bytes.isEmpty || bytes.length > PluginManager.maxPackageBytes) {
      throw const RepositoryException('Tamanho do pacote .addko inválido.');
    }
    if (sha256.convert(bytes).toString() != addon.sha256) {
      throw const RepositoryException(
        'SHA-256 do pacote não confere com o índice. Instalação bloqueada.',
      );
    }
    return bytes;
  }

  static Future<List<int>> fetchHttps(Uri uri, int limit) async {
    if (uri.scheme != 'https' || !_publicHostname(uri.host)) {
      throw const RepositoryException('Somente origens HTTPS públicas são aceitas.');
    }
    final addresses = await InternetAddress.lookup(uri.host)
        .timeout(const Duration(seconds: 8));
    if (addresses.isEmpty || addresses.any((address) => !_isPublicAddress(address))) {
      throw const RepositoryException('Destino de rede local ou privado bloqueado.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw RepositoryException('Servidor retornou HTTP ${response.statusCode}.');
      }
      if (response.contentLength > limit) {
        throw const RepositoryException('Download excede o tamanho permitido.');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > limit) {
          throw const RepositoryException('Download excede o tamanho permitido.');
        }
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  static bool _isPublicAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal || address.isMulticast) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      final a = bytes[0];
      final b = bytes[1];
      return !(a == 0 ||
          a == 10 ||
          a == 127 ||
          a >= 224 ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 100 && b >= 64 && b <= 127) ||
          (a == 198 && (b == 18 || b == 19)));
    }
    if (bytes.length == 16) {
      if (bytes.every((b) => b == 0) || (bytes[0] & 0xfe) == 0xfc ||
          (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80)) {
        return false;
      }
      if (bytes.take(10).every((b) => b == 0) &&
          bytes[10] == 255 && bytes[11] == 255) {
        return false;
      }
    }
    return true;
  }
}
, caseSensitive: false);

  final File configFile;
  final RepositoryFetcher _fetcher;

  static Future<AddKoRepositoryManager> openDefault() async {
    final support = await getApplicationSupportDirectory();
    return AddKoRepositoryManager(
      File('${support.path}${Platform.pathSeparator}repositories.json'),
    );
  }

  static Uri parseRepositoryUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isEmpty ||
        !uri.path.toLowerCase().endsWith('.json') ||
        uri.host.length > 253 ||
        uri.toString().length > 2048 ||
        !_publicHostname(uri.host)) {
      throw const RepositoryException(
        'Informe a URL HTTPS direta de um índice JSON público.',
      );
    }
    return uri;
  }

  static bool _publicHostname(String host) {
    final value = host.toLowerCase();
    if (InternetAddress.tryParse(value) != null ||
        !value.contains('.') ||
        value.startsWith('.') ||
        value.endsWith('.') ||
        value.endsWith('.local') ||
        value.endsWith('.localhost') ||
        value.endsWith('.internal') ||
        value.endsWith('.home.arpa') ||
        value.endsWith('.test') ||
        value.endsWith('.invalid')) {
      return false;
    }
    return RegExp(r'^[a-z0-9.-]+$').hasMatch(value);
  }

  Future<List<Uri>> savedUrls() async {
    if (!await configFile.exists()) return <Uri>[];
    if (await configFile.length() > 64 * 1024) {
      throw const RepositoryException('Arquivo de repositórios grande demais.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(await configFile.readAsString());
    } on Object {
      throw const RepositoryException('Lista de repositórios corrompida.');
    }
    if (decoded is! List || decoded.length > maxRepositories) {
      throw const RepositoryException('Lista de repositórios inválida.');
    }
    final urls = <Uri>[];
    final seen = <String>{};
    for (final value in decoded) {
      if (value is! String) {
        throw const RepositoryException('URL de repositório inválida.');
      }
      final url = parseRepositoryUrl(value);
      if (!seen.add(url.toString())) {
        throw const RepositoryException('Repositório duplicado no arquivo.');
      }
      urls.add(url);
    }
    return urls;
  }

  Future<RepositoryIndex> add(String source) async {
    final url = parseRepositoryUrl(source);
    final existing = await savedUrls();
    if (existing.any((item) => item == url)) {
      throw const RepositoryException('Esse repositório já está cadastrado.');
    }
    if (existing.length >= maxRepositories) {
      throw const RepositoryException('Limite de repositórios atingido.');
    }
    final index = await loadIndex(url);
    await _persist(<Uri>[...existing, url]);
    return index;
  }

  Future<void> remove(Uri url) async {
    final existing = await savedUrls();
    await _persist(existing.where((item) => item != url).toList());
  }

  Future<void> _persist(List<Uri> urls) async {
    await configFile.parent.create(recursive: true);
    final temp = File('${configFile.path}.tmp');
    try {
      await temp.writeAsString(
        jsonEncode(urls.map((url) => url.toString()).toList()),
        flush: true,
      );
      await temp.rename(configFile.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<List<RepositoryStatus>> refresh() async {
    final urls = await savedUrls();
    final statuses = <RepositoryStatus>[];
    for (final url in urls) {
      try {
        statuses.add(RepositoryStatus(url: url, index: await loadIndex(url)));
      } on Object catch (error) {
        statuses.add(RepositoryStatus(url: url, error: '$error'));
      }
    }
    return statuses;
  }

  Future<RepositoryIndex> loadIndex(Uri url) async {
    final bytes = await _fetcher(url, maxIndexBytes);
    if (bytes.length > maxIndexBytes) {
      throw const RepositoryException('Índice excede o limite de 512 KiB.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object {
      throw const RepositoryException('Índice JSON inválido ou não UTF-8.');
    }
    if (decoded is! Map ||
        decoded['schema'] != 1 ||
        decoded['name'] is! String ||
        decoded['addons'] is! List) {
      throw const RepositoryException('Índice não segue o esquema AddKo v1.');
    }
    final name = (decoded['name'] as String).trim();
    if (name.isEmpty || name.length > 120) {
      throw const RepositoryException('Nome de repositório inválido.');
    }
    final rawAddons = decoded['addons'] as List;
    if (rawAddons.length > maxAddons) {
      throw const RepositoryException('Índice contém addons demais.');
    }
    final addons = <RepositoryAddon>[];
    final ids = <String>{};
    for (final raw in rawAddons) {
      if (raw is! Map) {
        throw const RepositoryException('Entrada de addon inválida.');
      }
      final id = raw['id'];
      final title = raw['name'];
      final version = raw['version'];
      final file = raw['file'];
      final sha = raw['sha256'];
      final description = raw['description'] ?? '';
      if (id is! String ||
          title is! String ||
          version is! String ||
          file is! String ||
          sha is! String ||
          description is! String ||
          description.length > 512 ||
          !_digestPattern.hasMatch(sha)) {
        throw const RepositoryException('Metadados de addon inválidos.');
      }
      try {
        PluginManifest.fromJson(<String, Object?>{
          'id': id,
          'name': title,
          'version': version,
          'entry': 'main.lua',
          'permissions': <Object?>[],
        });
      } on FormatException {
        throw RepositoryException('ID, nome ou versão inválidos: $id');
      }
      if (!ids.add(id)) {
        throw RepositoryException('ID duplicado no catálogo: $id');
      }
      if (file.length > 300 ||
          !_relativePackagePattern.hasMatch(file) ||
          file.startsWith('/') ||
          file.split('/').any((part) => part == '.' || part == '..' || part.isEmpty)) {
        throw RepositoryException('Caminho de pacote inseguro: $id');
      }
      final package = url.resolve(file);
      if (package.scheme != 'https' ||
          package.host != url.host ||
          package.port != url.port ||
          package.userInfo.isNotEmpty ||
          package.hasQuery ||
          package.hasFragment) {
        throw RepositoryException('Pacote fora da origem autorizada: $id');
      }
      addons.add(RepositoryAddon(
        id: id,
        name: title,
        version: version,
        description: description,
        file: package,
        sha256: sha.toLowerCase(),
        repository: url,
      ));
    }
    return RepositoryIndex(
      url: url,
      name: name,
      addons: List<RepositoryAddon>.unmodifiable(addons),
    );
  }

  Future<List<int>> download(RepositoryAddon addon) async {
    final bytes = await _fetcher(addon.file, PluginManager.maxPackageBytes);
    if (bytes.isEmpty || bytes.length > PluginManager.maxPackageBytes) {
      throw const RepositoryException('Tamanho do pacote .addko inválido.');
    }
    if (sha256.convert(bytes).toString() != addon.sha256) {
      throw const RepositoryException(
        'SHA-256 do pacote não confere com o índice. Instalação bloqueada.',
      );
    }
    return bytes;
  }

  static Future<List<int>> fetchHttps(Uri uri, int limit) async {
    if (uri.scheme != 'https' || !_publicHostname(uri.host)) {
      throw const RepositoryException('Somente origens HTTPS públicas são aceitas.');
    }
    final addresses = await InternetAddress.lookup(uri.host)
        .timeout(const Duration(seconds: 8));
    if (addresses.isEmpty || addresses.any((address) => !_isPublicAddress(address))) {
      throw const RepositoryException('Destino de rede local ou privado bloqueado.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw RepositoryException('Servidor retornou HTTP ${response.statusCode}.');
      }
      if (response.contentLength > limit) {
        throw const RepositoryException('Download excede o tamanho permitido.');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > limit) {
          throw const RepositoryException('Download excede o tamanho permitido.');
        }
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  static bool _isPublicAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal || address.isMulticast) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      final a = bytes[0];
      final b = bytes[1];
      return !(a == 0 ||
          a == 10 ||
          a == 127 ||
          a >= 224 ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 100 && b >= 64 && b <= 127) ||
          (a == 198 && (b == 18 || b == 19)));
    }
    if (bytes.length == 16) {
      if (bytes.every((b) => b == 0) || (bytes[0] & 0xfe) == 0xfc ||
          (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80)) {
        return false;
      }
      if (bytes.take(10).every((b) => b == 0) &&
          bytes[10] == 255 && bytes[11] == 255) {
        return false;
      }
    }
    return true;
  }
}
