import 'package:flutter/material.dart';

import '../../core/repositories/domain/repository_catalog.dart';

class RepositoryCatalogPage extends StatelessWidget {
  const RepositoryCatalogPage({
    required this.catalog,
    super.key,
  });

  final RepositoryCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final groups = catalog.grouped.entries.toList()
      ..sort((left, right) => left.key.index.compareTo(right.key.index));

    return Scaffold(
      appBar: AppBar(
        title: Text(catalog.repositoryName),
      ),
      body: groups.isEmpty
          ? const Center(child: Text('Este repositório não publicou addons.'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: ExpansionTile(
                    initiallyExpanded: index == 0,
                    title: Text(group.key.label),
                    subtitle: Text('${group.value.length} addon(s)'),
                    children: [
                      for (final addon in group.value)
                        ListTile(
                          leading: addon.iconUri == null
                              ? const Icon(Icons.extension_rounded)
                              : Image.network(
                                  addon.iconUri.toString(),
                                  width: 44,
                                  height: 44,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.extension_rounded),
                                ),
                          title: Text(addon.manifest.name),
                          subtitle: Text(
                            _subtitleFor(addon),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: addon.packageUri == null
                              ? const Icon(Icons.info_outline_rounded)
                              : const Icon(Icons.download_rounded),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  String _subtitleFor(RepositoryAddonEntry addon) {
    final provider = addon.manifest.providerName.trim();
    final parts = <String>['v${addon.manifest.version}'];
    if (provider.isNotEmpty) {
      parts.add(provider);
    }
    if (addon.manifest.summary case final summary? when summary.trim().isNotEmpty) {
      parts.add(summary.trim());
    }
    return parts.join(' • ');
  }
}
