import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PythonRuntimeBundle {
  PythonRuntimeBundle({
    Future<Directory> Function()? supportDirectoryProvider,
  })  : _usesSharedCache = supportDirectoryProvider == null,
        _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const _version = 'v6';
  static const _workerAsset = 'runtime/python/addko_worker.py';
  static const _shimAssets = <String>[
    'runtime/python/shims/addko_bridge.py',
    'runtime/python/shims/addko_window.py',
    'runtime/python/shims/kodi_proxy.py',
    'runtime/python/shims/xbmc.py',
    'runtime/python/shims/xbmcaddon.py',
    'runtime/python/shims/xbmcdrm.py',
    'runtime/python/shims/xbmcgui.py',
    'runtime/python/shims/xbmcplugin.py',
    'runtime/python/shims/xbmcvfs.py',
    'runtime/python/shims/xbmcwsgi.py',
  ];

  static Future<PythonRuntimeFiles>? _sharedMaterialization;

  final bool _usesSharedCache;
  final Future<Directory> Function() _supportDirectoryProvider;

  Future<PythonRuntimeFiles> materialize() async {
    if (!_usesSharedCache) {
      return _materializeInternal();
    }

    final cached = _sharedMaterialization;
    if (cached != null) {
      return cached;
    }

    final operation = _materializeInternal();
    _sharedMaterialization = operation;
    try {
      return await operation;
    } on Object {
      if (identical(_sharedMaterialization, operation)) {
        _sharedMaterialization = null;
      }
      rethrow;
    }
  }

  Future<PythonRuntimeFiles> _materializeInternal() async {
    final support = await _supportDirectoryProvider();
    final runtimeRoot = Directory(
      p.join(support.path, 'runtime', 'python', _version),
    );
    final shims = Directory(p.join(runtimeRoot.path, 'shims'));
    await shims.create(recursive: true);

    final worker = File(p.join(runtimeRoot.path, 'addko_worker.py'));
    await _writeAsset(_workerAsset, worker);

    for (final asset in _shimAssets) {
      final file = File(p.join(shims.path, p.basename(asset)));
      await _writeAsset(asset, file);
    }

    return PythonRuntimeFiles(
      workerPath: worker.path,
      shimsPath: shims.path,
    );
  }

  Future<void> _writeAsset(String assetPath, File target) async {
    final source = await rootBundle.loadString(assetPath);
    if (await target.exists()) {
      final current = await target.readAsString();
      if (current == source) {
        return;
      }
    }

    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    if (await temporary.exists()) {
      await temporary.delete();
    }
    await temporary.writeAsString(source, flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    await temporary.rename(target.path);
  }
}

class PythonRuntimeFiles {
  const PythonRuntimeFiles({
    required this.workerPath,
    required this.shimsPath,
  });

  final String workerPath;
  final String shimsPath;
}
