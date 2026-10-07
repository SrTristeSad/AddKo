import 'dart:io';

import 'package:addko/core/runtime/legacy/legacy_plugin_invocation.dart';
import 'package:addko/core/runtime/legacy/process_python_executor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('executes a Kodi-style Python plugin and collects directory items', () async {
    final python = await const PythonExecutableResolver().resolve();
    if (python == null) {
      return;
    }

    final temp = await Directory.systemTemp.createTemp('addko-python-test-');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final addon = Directory(p.join(temp.path, 'plugin.video.demo'));
    final profile = Directory(p.join(temp.path, 'addon_data', 'plugin.video.demo'));
    await addon.create(recursive: true);
    await profile.create(recursive: true);

    await File(p.join(addon.path, 'default.py')).writeAsString('''
import sys
import xbmcgui
import xbmcplugin

handle = int(sys.argv[1])
item = xbmcgui.ListItem(label="Filmes")
item.setArt({"icon": "https://example.com/icon.png"})
item.setProperty("IsPlayable", "false")
xbmcplugin.addDirectoryItem(
    handle,
    sys.argv[0] + "?action=movies",
    item,
    isFolder=True,
)
xbmcplugin.setContent(handle, "movies")
xbmcplugin.endOfDirectory(handle)
''');

    final root = Directory.current.path;
    final executor = ProcessPythonExecutor(
      pythonExecutable: python,
      workerScriptPath: p.join(root, 'runtime', 'python', 'addko_worker.py'),
    );

    final result = await executor.invoke(
      LegacyPluginInvocation(
        addonId: 'plugin.video.demo',
        addonPath: addon.path,
        entrypointPath: p.join(addon.path, 'default.py'),
        pluginUrl: 'plugin://plugin.video.demo/',
        handle: 7,
        query: '',
        profilePath: profile.path,
        addonsRoot: temp.path,
        addonDataRoot: p.join(temp.path, 'addon_data'),
        shimsPath: p.join(root, 'runtime', 'python', 'shims'),
        pythonPaths: const [],
        specialPaths: {
          'special://home': temp.path,
          'special://profile': temp.path,
          'special://userdata': temp.path,
          'special://temp': temp.path,
        },
      ),
    );

    expect(result.succeeded, isTrue, reason: result.logs.join('\n'));
    expect(result.contentType, 'movies');
    expect(result.items, hasLength(1));
    expect(result.items.single.label, 'Filmes');
    expect(result.items.single.isFolder, isTrue);
    expect(
      result.items.single.url,
      'plugin://plugin.video.demo/?action=movies',
    );
  });
}
