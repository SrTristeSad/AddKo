import 'dart:convert';
import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/lua_runtime.dart';

class InstalledPlugin {
  const InstalledPlugin({
    required this.directory,
    required this.manifest,
  });

  final Directory directory;
  final PluginManifest manifest;

  File get entryFile => File(_resolvePackagePath(directory.path, manifest.entry));

  Future<String> runEntrypoint() async {
    final file = entryFile;
    if (!await file.exists()) {
      throw StateError('Entrypoint não encontrado: ${manifest.entry}');
    }

    final source = await file.readAsString(encoding: utf8);
    final runtime = LuaRuntime.open();
    try {
      return runtime.evaluate(source);
    } finally {
      runtime.dispose();
    }
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
