import 'repository_source.dart';

/// Hidden system repository used to resolve the standard Kodi dependencies
/// that third-party repositories normally expect Kodi itself to provide.
class KodiSystemRepository {
  const KodiSystemRepository._();

  static final RepositorySource omega = RepositorySource(
    uri: Uri.parse('https://mirrors.kodi.tv/addons/omega/addons.xml.gz'),
    packageBaseUri: Uri.parse('https://mirrors.kodi.tv/addons/omega/'),
    name: 'Kodi Add-on Repository (Omega)',
    enabled: true,
  );
}
