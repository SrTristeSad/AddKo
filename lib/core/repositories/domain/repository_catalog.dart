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

/// Store groups derived from Kodi 21's official top-level addon type mappings.
///
/// Not every group has a functional host yet (for example PVR/game/VFS binary
/// instances), but AddKo must still preserve and present those packages instead
/// of flattening most of the Kodi ecosystem into "Outros".
enum RepositoryAddonCategory {
  video('Vídeo'),
  audio('Música'),
  images('Imagens'),
  programs('Programas'),
  weather('Clima'),
  lyrics('Letras'),
  subtitles('Legendas'),
  services('Serviços'),
  repositories('Repositórios'),
  modules('Módulos e bibliotecas Python'),
  metadata('Scrapers e metadados'),
  skins('Skins'),
  webInterfaces('Interfaces web'),
  resources('Recursos'),
  inputStream('InputStream'),
  pvr('PVR / TV ao vivo'),
  games('Jogos e emuladores'),
  gameControllers('Controles de jogos'),
  peripherals('Periféricos'),
  audioCodecs('Codecs de áudio'),
  imageDecoders('Decodificadores de imagem'),
  vfs('VFS / sistemas de arquivos'),
  screensavers('Protetores de tela'),
  visualizations('Visualizações de música'),
  other('Outros');

  const RepositoryAddonCategory(this.label);

  final String label;
}
