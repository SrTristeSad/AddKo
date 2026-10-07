import '../../addons/domain/addon_manifest.dart';

class RepositoryCatalog {
  const RepositoryCatalog({
    required this.repositoryName,
    required this.sourceUri,
    required this.addons,
    required this.fetchedAt,
    this.packageBaseUri,
    this.skippedAddons = 0,
  });

  final String repositoryName;
  final Uri sourceUri;
  final Uri? packageBaseUri;
  final List<RepositoryAddonEntry> addons;
  final DateTime fetchedAt;
  final int skippedAddons;

  Map<RepositoryAddonCategory, List<RepositoryAddonEntry>> get grouped {
    final result = <RepositoryAddonCategory, List<RepositoryAddonEntry>>{};
    for (final addon in addons) {
      result.putIfAbsent(addon.category, () => []).add(addon);
    }
    return result;
  }
}

class RepositoryAddonEntry {
  const RepositoryAddonEntry({
    required this.manifest,
    required this.category,
    this.packageUri,
    this.iconUri,
  });

  final AddonManifest manifest;
  final RepositoryAddonCategory category;
  final Uri? packageUri;
  final Uri? iconUri;
}

enum RepositoryAddonCategory {
  video('Vídeo'),
  audio('Música'),
  images('Imagens'),
  programs('Programas'),
  services('Serviços'),
  subtitles('Legendas'),
  repositories('Repositórios'),
  modules('Módulos Python'),
  inputStream('InputStream'),
  pvr('PVR'),
  other('Outros');

  const RepositoryAddonCategory(this.label);

  final String label;
}
