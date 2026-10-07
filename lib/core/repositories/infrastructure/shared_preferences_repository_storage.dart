import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/repository_source.dart';
import '../domain/repository_storage.dart';

class SharedPreferencesRepositoryStorage implements RepositoryStorage {
  const SharedPreferencesRepositoryStorage();

  static const _storageKey = 'addko.repository_sources.v1';

  @override
  Future<List<RepositorySource>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }

    final sources = <RepositorySource>[];
    for (final entry in decoded) {
      if (entry is! Map) {
        continue;
      }

      try {
        sources.add(
          RepositorySource.fromJson(
            Map<String, Object?>.from(entry),
          ),
        );
      } on FormatException {
        // Ignore corrupted individual entries and keep the remaining sources.
      }
    }

    return List.unmodifiable(sources);
  }

  @override
  Future<void> save(List<RepositorySource> sources) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = jsonEncode(
      sources.map((source) => source.toJson()).toList(growable: false),
    );
    await preferences.setString(_storageKey, payload);
  }
}
