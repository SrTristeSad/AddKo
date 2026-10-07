import 'dart:io';

import 'package:addko/core/runtime/legacy/legacy_plugin_invocation.dart';
import 'package:addko/core/runtime/legacy/legacy_runtime_request.dart';
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

    final executor = ProcessPythonExecutor(
      pythonExecutable: python,
      workerScriptPath: _workerPath(),
    );

    final result = await executor.invoke(
      _invocation(
        temp: temp,
        addon: addon,
        profile: profile,
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

  test('runs WindowXML callbacks through the bidirectional bridge', () async {
    final python = await const PythonExecutableResolver().resolve();
    if (python == null) {
      return;
    }

    final temp = await Directory.systemTemp.createTemp('addko-windowxml-test-');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final addon = Directory(p.join(temp.path, 'plugin.video.demo'));
    final profile = Directory(p.join(temp.path, 'addon_data', 'plugin.video.demo'));
    final skin = Directory(
      p.join(addon.path, 'resources', 'skins', 'Default', '720p'),
    );
    await skin.create(recursive: true);
    await profile.create(recursive: true);

    await File(p.join(addon.path, 'addon.xml')).writeAsString('''
<addon id="plugin.video.demo" name="Demo" version="1.0.0" provider-name="AddKo">
  <requires><import addon="xbmc.python" version="3.0.0" /></requires>
  <extension point="xbmc.python.pluginsource" library="default.py"><provides>video</provides></extension>
</addon>
''');
    await File(p.join(skin.path, 'dialog.xml')).writeAsString('''
<window>
  <controls>
    <control type="label" id="9"><posx>20</posx><posy>20</posy><width>300</width><height>40</height><label>Título</label></control>
    <control type="button" id="10"><posx>20</posx><posy>80</posy><width>250</width><height>50</height><label>Original</label></control>
  </controls>
</window>
''');
    await File(p.join(addon.path, 'default.py')).writeAsString('''
import sys
import xbmcaddon
import xbmcgui
import xbmcplugin

class DemoWindow(xbmcgui.WindowXML):
    def onInit(self):
        self.getControl(10).setLabel("Abrir")

    def onClick(self, control_id):
        if control_id == 10:
            item = xbmcgui.ListItem(label="Clicado")
            xbmcplugin.addDirectoryItem(int(sys.argv[1]), sys.argv[0] + "?clicked=1", item, True)
            self.close()

window = DemoWindow(
    "dialog.xml",
    xbmcaddon.Addon().getAddonInfo("path"),
    "Default",
    "720p",
)
window.doModal()
xbmcplugin.endOfDirectory(int(sys.argv[1]))
''');

    var windowRequests = 0;
    final executor = ProcessPythonExecutor(
      pythonExecutable: python,
      workerScriptPath: _workerPath(),
      requestHandler: (LegacyRuntimeRequest request) async {
        if (request.method != 'xbmcgui.WindowXML.doModal') {
          return request.defaultValue;
        }
        windowRequests += 1;
        final rawControls = request.params['controls'];
        expect(rawControls, isA<List<Object?>>());
        final controls = (rawControls! as List)
            .whereType<Map>()
            .map((item) => Map<String, Object?>.from(item))
            .toList();
        final button = controls.firstWhere((item) => item['id'] == 10);
        expect(button['label'], 'Abrir');
        return const {
          'action': 'click',
          'control_id': 10,
        };
      },
    );

    final result = await executor.invoke(
      _invocation(
        temp: temp,
        addon: addon,
        profile: profile,
      ),
    );

    expect(result.succeeded, isTrue, reason: result.logs.join('\n'));
    expect(windowRequests, 1);
    expect(result.items, hasLength(1));
    expect(result.items.single.label, 'Clicado');
  });
}

String _workerPath() {
  return p.join(Directory.current.path, 'runtime', 'python', 'addko_worker.py');
}

LegacyPluginInvocation _invocation({
  required Directory temp,
  required Directory addon,
  required Directory profile,
}) {
  final root = Directory.current.path;
  return LegacyPluginInvocation(
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
  );
}
