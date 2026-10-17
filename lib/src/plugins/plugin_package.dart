import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/basic_plugin_host.dart';
import 'package:addko/src/runtime/lua_plugin_session.dart';
import 'package:addko/src/runtime/lua_runtime.dart';
import 'package:addko/src/runtime/media_plugin_host.dart';
import 'package:addko/src/runtime/plugin_dependency_host.dart';
import 'package:addko/src/runtime/plugin_host.dart';
import 'package:addko/src/runtime/plugin_player.dart';

class InstalledPlugin {
  const InstalledPlugin({
    required this.directory,
    required this.manifest,
  });

  final Directory directory;
  final PluginManifest manifest;

  File get entryFile => File(_resolvePackagePath(directory.path, manifest.entry));

  /// Legacy/smoke execution path kept for tiny one-file examples.
  Future<String> runEntrypoint() async {
    final file = entryFile;
    if (!await file.exists()) {
      throw StateError('Entrypoint não encontrado: ${manifest.entry}');
    }

    final source = await file.readAsString(encoding: utf8);
    final runtime = LuaRuntime.open(pluginRoot: directory.path);
    try {
      return runtime.evaluate(source);
    } finally {
      runtime.dispose();
    }
  }

  /// Opens the persistent Plugin v2 session used by real mini-apps.
  ///
  /// Unlike [runEntrypoint], this keeps the Lua state alive, injects the
  /// generic AddKo host API and supports coroutine-based asynchronous calls.
  Future<LuaPluginSession> openSession({
    PluginPlayer? player,
    PluginUiHandler? uiHandler,
    PluginDependencyCaller? dependencyCaller,
  }) async {
    final supportRoot = directory.parent.parent;
    final dataDirectory = Directory(
      _resolvePackagePath(
        supportRoot.path,
        'plugin-data/${manifest.id}',
      ),
    );
    await dataDirectory.create(recursive: true);

    PluginHost host = player == null
        ? BasicPluginHost(
            manifest: manifest,
            pluginDirectory: directory,
            dataDirectory: dataDirectory,
            uiHandler: uiHandler,
          )
        : MediaPluginHost(
            manifest: manifest,
            pluginDirectory: directory,
            dataDirectory: dataDirectory,
            uiHandler: uiHandler,
            player: player,
          );

    if (dependencyCaller != null && manifest.dependencies.isNotEmpty) {
      host = PluginDependencyHost(
        inner: host,
        manifest: manifest,
        caller: dependencyCaller,
      );
    }

    final locale = _locale();
    return LuaPluginSession.open(
      pluginRoot: directory.path,
      dataRoot: dataDirectory.path,
      entry: manifest.entry,
      platform: <String, Object?>{
        'os': Platform.operatingSystem,
        'arch': _currentArch(),
      },
      locale: locale,
      host: host,
    );
  }
}

String resolvePluginPath(String root, String relativePath) {
  return _resolvePackagePath(root, relativePath);
}

String _resolvePackagePath(String root, String relativePath) {
  final separator = Platform.pathSeparator;
  final suffix = relativePath.split('/').join(separator);
  return root.endsWith(separator) ? '$root$suffix' : '$root$separator$suffix';
}

Map<String, Object?> _locale() {
  final raw = Platform.localeName.split('.').first.replaceAll('-', '_');
  final parts = raw.split('_').where((value) => value.isNotEmpty).toList();
  final language = parts.isEmpty ? 'en' : parts.first.toLowerCase();
  final region = parts.length > 1 ? parts[1].toUpperCase() : 'US';
  return <String, Object?>{
    'language': language,
    'region': region,
    'second_language': '',
  };
}

String _currentArch() {
  final abi = Abi.current();
  if (abi == Abi.androidArm64 ||
      abi == Abi.linuxArm64 ||
      abi == Abi.macosArm64 ||
      abi == Abi.iosArm64 ||
      abi == Abi.windowsArm64) {
    return 'arm64';
  }
  if (abi == Abi.androidArm || abi == Abi.linuxArm || abi == Abi.iosArm) {
    return 'armv7';
  }
  if (abi == Abi.androidX64 ||
      abi == Abi.linuxX64 ||
      abi == Abi.macosX64 ||
      abi == Abi.iosX64 ||
      abi == Abi.windowsX64) {
    return 'x64';
  }
  if (abi == Abi.androidIA32 ||
      abi == Abi.linuxIA32 ||
      abi == Abi.windowsIA32) {
    return 'x86';
  }
  return abi.toString();
}
