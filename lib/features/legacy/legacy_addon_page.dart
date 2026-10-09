import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/addons/domain/installed_addon.dart';
import '../../core/addons/domain/kodi_version.dart';
import '../../core/player/playback_request.dart';
import '../../core/repositories/application/repository_registry.dart';
import '../../core/repositories/application/repository_store_controller.dart';
import '../../core/repositories/domain/repository_catalog.dart';
import '../../core/runtime/legacy/kodi_builtin_command.dart';
import '../../core/runtime/legacy/legacy_plugin_item.dart';
import '../../core/runtime/legacy/legacy_plugin_result.dart';
import '../../core/runtime/legacy/legacy_plugin_runtime.dart';
import '../../core/ui/kodi_text.dart';
import '../player/player_page.dart';
import 'legacy_addon_settings_page.dart';

class LegacyAddonPage extends StatefulWidget {
  const LegacyAddonPage({
    required this.addon,
    required this.runtime,
    required this.repositoryRegistry,
    required this.repositoryStoreController,
    super.key,
  });

  final InstalledAddon addon;
  final LegacyPluginRuntime runtime;
  final RepositoryRegistry repositoryRegistry;
  final RepositoryStoreController repositoryStoreController;

  @override
  State<LegacyAddonPage> createState() => _LegacyAddonPageState();
}

class _LegacyAddonPageState extends State<LegacyAddonPage> {
  final List<String> _history = [];

  LegacyPluginResult? _result;
  String? _currentUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_open('plugin://${widget.addon.manifest.id}/', pushHistory: false));
  }

  Future<void> _open(String url, {bool pushHistory = true}) async {
    if (_loading && _currentUrl == url) {
      return;
    }

    final previousUrl = _currentUrl;
    setState(() {
      _loading = true;
      _currentUrl = url;
    });

    final result = await widget.runtime.invokeUrl(url);
    if (!mounted) {
      return;
    }

    if (pushHistory && previousUrl != null && result.succeeded) {
      _history.add(previousUrl);
    }

    setState(() {
      _loading = false;
      _result = result;
    });

    await _processResultActions(result);
  }

  Future<void> _processResultActions(LegacyPluginResult result) async {
    if (!result.succeeded || !mounted) {
      return;
    }

    final resolved = result.resolvedItem;
    if (resolved != null) {
      _openPlayback(resolved);
      return;
    }

    for (final rawCommand in result.builtins) {
      if (!mounted) return;
      await _executeBuiltin(KodiBuiltinCommand.parse(rawCommand));
    }
  }

  Future<void> _executeBuiltin(KodiBuiltinCommand command) async {
    if (command.isEmpty || !mounted) return;

    switch (command.normalizedName) {
      case 'runplugin':
        final target = command.argument(0)?.trim();
        if (target != null && target.startsWith('plugin://')) {
          await _runPlugin(target);
        }
        return;
      case 'runaddon':
        final addonId = command.argument(0)?.trim();
        if (addonId == null || addonId.isEmpty) return;
        final addon = widget.runtime.addonInstallController.installedById(addonId);
        if (addon?.manifest.isPythonPlugin == true) {
          await _open('plugin://$addonId/');
        } else if (addon?.manifest.isPythonScript == true) {
          await _runScript(addonId, const []);
        }
        return;
      case 'runscript':
        final target = command.argument(0)?.trim();
        if (target == null || target.isEmpty) return;
        if (target.startsWith('plugin://')) {
          await _runPlugin(target);
          return;
        }
        await _runScript(
          target,
          command.arguments.skip(1).toList(growable: false),
        );
        return;
      case 'container.update':
        final target = command.argument(0)?.trim();
        if (target == null || !target.startsWith('plugin://')) return;
        final replace = command.arguments.skip(1).any(
              (value) => value.trim().toLowerCase() == 'replace',
            );
        await _open(target, pushHistory: !replace);
        return;
      case 'container.refresh':
        final current = _currentUrl;
        if (current != null) {
          await _open(current, pushHistory: false);
        }
        return;
      case 'playmedia':
        final target = command.argument(0)?.trim();
        if (target == null || target.isEmpty) return;
        if (target.startsWith('plugin://')) {
          await _runPlugin(target);
        } else {
          _openPlayback(
            LegacyPluginItem(
              label: command.argument(1)?.trim() ?? '',
              path: target,
              url: target,
              isFolder: false,
            ),
          );
        }
        return;
      case 'activatewindow':
        final pluginTarget = command.arguments
            .map((value) => value.trim())
            .where((value) => value.startsWith('plugin://'))
            .firstOrNull;
        if (pluginTarget != null) {
          await _open(pluginTarget);
          return;
        }
        final window = command.argument(0)?.trim().toLowerCase();
        if (window == 'home') {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        return;
      case 'addon.opensettings':
        await _openAddonSettings(command.argument(0)?.trim());
        return;
      case 'installaddon':
        final addonId = command.argument(0)?.trim();
        if (addonId != null && addonId.isNotEmpty) {
          await _installAddonFromRepositories(addonId);
        }
        return;
      case 'updateaddonrepos':
        await _updateAddonRepositories();
        return;
      case 'updatelocaladdons':
        await _refreshLocalAddons();
        return;
      case 'notification':
        final heading = command.argument(0)?.trim() ?? 'AddKo';
        final message = command.argument(1)?.trim() ?? '';
        final rawDuration = int.tryParse(command.argument(2)?.trim() ?? '') ?? 3000;
        final durationMs = rawDuration < 800
            ? 800
            : rawDuration > 30000
                ? 30000
                : rawDuration;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: KodiText(
              message.isEmpty ? heading : '$heading\n$message',
            ),
            duration: Duration(milliseconds: durationMs),
          ),
        );
        return;
      default:
        debugPrint('AddKo: Kodi built-in ainda não implementado: ${command.raw}');
    }
  }

  Future<void> _installAddonFromRepositories(String rawAddonId) async {
    final addonId = _normalizeAddonId(rawAddonId);
    if (addonId.isEmpty) {
      _showMessage('O addon solicitou uma dependência sem identificador válido.');
      return;
    }

    try {
      await widget.repositoryRegistry.initialize();
      await widget.runtime.addonInstallController.initialize();

      if (widget.runtime.addonInstallController.installedById(addonId) != null) {
        return;
      }

      // Binary video components such as inputstream.adaptive and
      // inputstream.ffmpegdirect live in the official Kodi Omega catalog.
      await widget.repositoryStoreController.ensureKodiSystemCatalog();

      var candidate = _bestAvailableAddon(addonId);
      if (candidate == null) {
        await widget.repositoryStoreController.synchronizeAll(
          widget.repositoryRegistry.sources,
        );
        candidate = _bestAvailableAddon(addonId);
      }

      if (!mounted) return;
      if (candidate == null) {
        _showMessage('Addon não encontrado nos repositórios disponíveis: $addonId');
        return;
      }

      final plan = await widget.runtime.addonInstallController.install(
        addon: candidate,
        catalogs: widget.repositoryStoreController.catalogs,
      );
      if (!mounted) return;

      if (!plan.canInstall) {
        final detail = plan.issues.map((issue) => issue.toString()).join('\n');
        _showMessage(
          detail.isEmpty
              ? 'Não foi possível instalar $addonId.'
              : 'Não foi possível instalar $addonId:\n$detail',
        );
        return;
      }

      _showMessage('${candidate.manifest.name} instalado pela Loja do AddKo.');
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Falha ao instalar $addonId: $error');
    }
  }

  String _normalizeAddonId(String rawValue) {
    var value = rawValue.trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1).trim();
    }
    value = value.replaceAll('\\', '/');
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    final slash = value.lastIndexOf('/');
    if (slash >= 0) {
      value = value.substring(slash + 1);
    }
    return value.trim();
  }

  RepositoryAddonEntry? _bestAvailableAddon(String addonId) {
    final normalizedId = addonId.toLowerCase();
    RepositoryAddonEntry? selected;
    for (final catalog in widget.repositoryStoreController.catalogs) {
      for (final entry in catalog.addons) {
        if (entry.manifest.id.toLowerCase() != normalizedId ||
            entry.packageUri == null) {
          continue;
        }
        if (selected == null ||
            KodiVersion(entry.manifest.version)
                    .compareTo(KodiVersion(selected.manifest.version)) >
                0) {
          selected = entry;
        }
      }
    }
    return selected;
  }

  Future<void> _updateAddonRepositories() async {
    try {
      await widget.repositoryRegistry.initialize();
      await Future.wait([
        widget.repositoryStoreController.ensureKodiSystemCatalog(),
        widget.repositoryStoreController.synchronizeAll(
          widget.repositoryRegistry.sources,
        ),
      ]);
      if (!mounted) return;

      final failed = widget.repositoryRegistry.sources.where((source) {
        return widget.repositoryStoreController.stateFor(source.uri).status ==
            RepositorySyncStatus.failed;
      }).length;
      if (failed == 0) {
        _showMessage('Repositórios atualizados.');
      } else {
        _showMessage(
          'Repositórios atualizados com $failed falha${failed == 1 ? '' : 's'}.',
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Falha ao atualizar repositórios: $error');
    }
  }

  Future<void> _refreshLocalAddons() async {
    try {
      await widget.runtime.addonInstallController.refreshInstalled();
      if (!mounted) return;
      _showMessage('Lista local de addons atualizada.');
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Falha ao atualizar addons locais: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: KodiText(message)),
    );
  }

  Future<void> _runPlugin(String target) async {
    final result = await widget.runtime.invokeUrl(target);
    if (!mounted) return;
    if (!result.succeeded) {
      _showRuntimeCommandError(result);
      return;
    }
    await _processResultActions(result);
  }

  Future<void> _runScript(String addonId, List<String> arguments) async {
    final result = await widget.runtime.invokeScriptAddon(
      addonId,
      arguments: arguments,
    );
    if (!mounted) return;
    if (!result.succeeded) {
      _showRuntimeCommandError(result);
      return;
    }
    await _processResultActions(result);
  }

  void _showRuntimeCommandError(LegacyPluginResult result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.errorMessage ?? 'Falha ao executar comando do addon.',
        ),
      ),
    );
  }

  Future<void> _openAddonSettings(String? requestedAddonId) async {
    final addonId = requestedAddonId?.isNotEmpty == true
        ? requestedAddonId!
        : widget.addon.manifest.id;
    final addon = widget.runtime.addonInstallController.installedById(addonId);
    if (addon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Addon não instalado: $addonId')),
      );
      return;
    }

    final directories = await widget.runtime.addonInstallController.directories();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegacyAddonSettingsPage(
          addon: addon,
          addonDataRootPath: directories.addonDataRootPath,
        ),
      ),
    );
  }

  Future<bool> _goBack() async {
    if (_history.isEmpty) {
      return true;
    }
    final previous = _history.removeLast();
    await _open(previous, pushHistory: false);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final title = result?.category?.trim().isNotEmpty == true
        ? '${widget.addon.manifest.name} • ${result!.category}'
        : widget.addon.manifest.name;

    return PopScope(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _history.isNotEmpty) {
          unawaited(_goBack());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: () async {
              if (await _goBack() && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: KodiText(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Configurações do addon',
              onPressed: () => unawaited(_openAddonSettings(null)),
              icon: const Icon(Icons.tune_rounded),
            ),
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _currentUrl == null || _loading
                  ? null
                  : () => unawaited(_open(_currentUrl!, pushHistory: false)),
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _body(result),
      ),
    );
  }

  Widget _body(LegacyPluginResult? result) {
    if (_loading && result == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (result == null) {
      return const Center(child: Text('O addon não retornou conteúdo.'));
    }

    if (!result.succeeded) {
      return _RuntimeError(
        message: result.errorMessage ?? 'Falha desconhecida ao executar o addon.',
        logs: result.logs,
        onRetry: _currentUrl == null
            ? null
            : () => unawaited(_open(_currentUrl!, pushHistory: false)),
      );
    }

    if (result.items.isEmpty) {
      return Stack(
        children: [
          const Center(child: Text('O addon não adicionou itens a esta pasta.')),
          if (_loading) const LinearProgressIndicator(),
        ],
      );
    }

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          itemCount: result.items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = result.items[index];
            return _LegacyItemTile(
              item: item,
              onTap: () => _activate(item),
              onContextCommand: (command) =>
                  unawaited(_executeBuiltin(KodiBuiltinCommand.parse(command))),
            );
          },
        ),
        if (_loading) const LinearProgressIndicator(),
      ],
    );
  }

  void _activate(LegacyPluginItem item) {
    final target = item.url.isNotEmpty ? item.url : item.path;
    if (target.startsWith('plugin://')) {
      unawaited(_open(target));
      return;
    }

    if (item.isFolder) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Caminho de pasta ainda não suportado: $target')),
      );
      return;
    }

    _openPlayback(item);
  }

  void _openPlayback(LegacyPluginItem item) {
    final request = PlaybackRequest.fromLegacyItem(item);
    if (request.uri.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O addon não informou um caminho de mídia.'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(request: request),
      ),
    );
  }
}

class _LegacyItemTile extends StatelessWidget {
  const _LegacyItemTile({
    required this.item,
    required this.onTap,
    required this.onContextCommand,
  });

  final LegacyPluginItem item;
  final VoidCallback onTap;
  final ValueChanged<String> onContextCommand;

  @override
  Widget build(BuildContext context) {
    final artwork = item.art['thumb'] ??
        item.art['icon'] ??
        item.art['poster'] ??
        item.art['fanart'];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      leading: SizedBox.square(
        dimension: 52,
        child: _Artwork(
          url: artwork,
          fallback: item.isFolder
              ? Icons.folder_rounded
              : Icons.play_circle_outline_rounded,
        ),
      ),
      title: KodiText(
        item.label.isEmpty ? '(sem nome)' : item.label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: item.label2.isEmpty
          ? null
          : KodiText(
              item.label2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: item.contextMenu.isEmpty
          ? Icon(
              item.isFolder
                  ? Icons.chevron_right_rounded
                  : Icons.play_arrow_rounded,
            )
          : PopupMenuButton<String>(
              tooltip: 'Opções',
              onSelected: onContextCommand,
              itemBuilder: (_) => [
                for (final action in item.contextMenu)
                  PopupMenuItem<String>(
                    value: action.command,
                    child: KodiText(action.label),
                  ),
              ],
            ),
      onTap: onTap,
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.fallback});

  final String? url;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final value = url?.trim();
    if (value == null || value.isEmpty) {
      return Icon(fallback, size: 38);
    }

    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          value,
          fit: BoxFit.cover,
          cacheWidth: 112,
          cacheHeight: 112,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, __, ___) => Icon(fallback, size: 38),
        ),
      );
    }

    return Icon(fallback, size: 38);
  }
}

class _RuntimeError extends StatelessWidget {
  const _RuntimeError({
    required this.message,
    required this.logs,
    required this.onRetry,
  });

  final String message;
  final List<String> logs;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 58,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (logs.isNotEmpty) ...[
                const SizedBox(height: 18),
                ExpansionTile(
                  title: const Text('Log do addon'),
                  children: [
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 260),
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        child: SelectableText(logs.join('\n')),
                      ),
                    ),
                  ],
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
