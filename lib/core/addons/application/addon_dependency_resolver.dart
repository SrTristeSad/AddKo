import '../domain/addon_dependency.dart';
import '../domain/installed_addon.dart';
import '../domain/kodi_version.dart';
import '../../repositories/domain/repository_catalog.dart';

class AddonInstallPlan {
  const AddonInstallPlan({
    required this.installOrder,
    required this.issues,
  });

  final List<RepositoryAddonEntry> installOrder;
  final List<AddonDependencyIssue> issues;

  bool get canInstall => issues.isEmpty;
}

class AddonDependencyIssue {
  const AddonDependencyIssue({
    required this.addonId,
    required this.message,
  });

  final String addonId;
  final String message;

  @override
  String toString() => '$addonId: $message';
}

class AddonDependencyResolver {
  const AddonDependencyResolver();

  AddonInstallPlan resolve({
    required RepositoryAddonEntry root,
    required Iterable<RepositoryCatalog> catalogs,
    required Iterable<InstalledAddon> installedAddons,
    bool installRoot = true,
  }) {
    final allAvailable = <String, List<RepositoryAddonEntry>>{};
    for (final catalog in catalogs) {
      for (final entry in catalog.addons) {
        allAvailable.putIfAbsent(entry.manifest.id, () => []).add(entry);
      }
    }

    final installed = {
      for (final addon in installedAddons) addon.manifest.id: addon,
    };
    final installOrder = <RepositoryAddonEntry>[];
    final issues = <AddonDependencyIssue>[];
    final visiting = <String>{};
    final planned = <String>{};

    void visit(RepositoryAddonEntry entry, {required bool explicitlySelected}) {
      final addonId = entry.manifest.id;
      if (planned.contains(addonId)) {
        return;
      }
      if (!visiting.add(addonId)) {
        issues.add(
          AddonDependencyIssue(
            addonId: addonId,
            message: 'Dependência circular detectada.',
          ),
        );
        return;
      }

      for (final dependency in entry.manifest.dependencies) {
        if (dependency.optional || _isHostCapability(dependency.id)) {
          continue;
        }

        final installedDependency = installed[dependency.id];
        if (installedDependency != null &&
            KodiVersion(installedDependency.manifest.version)
                .isAtLeast(dependency.version)) {
          continue;
        }

        final candidate = _bestCandidate(
          dependency,
          allAvailable[dependency.id] ?? const [],
        );
        if (candidate == null) {
          issues.add(
            AddonDependencyIssue(
              addonId: dependency.id,
              message: dependency.version == null
                  ? 'Dependência obrigatória não encontrada nos repositórios ativos.'
                  : 'Versão ${dependency.version} ou superior não encontrada nos repositórios ativos.',
            ),
          );
          continue;
        }

        visit(candidate, explicitlySelected: false);
      }

      visiting.remove(addonId);

      final current = installed[addonId];
      final alreadySatisfied = current != null &&
          KodiVersion(current.manifest.version)
              .compareTo(KodiVersion(entry.manifest.version)) >=
              0;

      if (entry.packageUri == null) {
        if (explicitlySelected || !alreadySatisfied) {
          issues.add(
            AddonDependencyIssue(
              addonId: addonId,
              message: 'O repositório não informou uma URL de pacote ZIP instalável.',
            ),
          );
        }
        planned.add(addonId);
        return;
      }

      if (explicitlySelected || !alreadySatisfied) {
        installOrder.add(entry);
      }
      planned.add(addonId);
    }

    visit(root, explicitlySelected: installRoot);

    return AddonInstallPlan(
      installOrder: List.unmodifiable(installOrder),
      issues: List.unmodifiable(issues),
    );
  }

  RepositoryAddonEntry? _bestCandidate(
    AddonDependency dependency,
    List<RepositoryAddonEntry> candidates,
  ) {
    RepositoryAddonEntry? selected;

    for (final candidate in candidates) {
      final candidateVersion = KodiVersion(candidate.manifest.version);
      if (!candidateVersion.isAtLeast(dependency.version)) {
        continue;
      }
      if (candidate.packageUri == null) {
        continue;
      }

      if (selected == null ||
          candidateVersion.compareTo(KodiVersion(selected.manifest.version)) >
              0) {
        selected = candidate;
      }
    }

    return selected;
  }

  bool _isHostCapability(String addonId) {
    return addonId.startsWith('xbmc.') || addonId.startsWith('kodi.');
  }
}
