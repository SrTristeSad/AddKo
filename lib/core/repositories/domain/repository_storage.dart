import 'repository_source.dart';

abstract interface class RepositoryStorage {
  Future<List<RepositorySource>> load();

  Future<void> save(List<RepositorySource> sources);
}
