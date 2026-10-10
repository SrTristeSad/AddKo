"""Runs inside Kodi's CPython, using native xbmc modules (never AddKo shims)."""
import importlib
import json
import os
import sys
import xbmc
import xbmcgui
import xbmcvfs


def rpc(method, **params):
    request = {'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}
    response = json.loads(xbmc.executeJSONRPC(json.dumps(request)))
    if 'error' in response:
        raise RuntimeError('%s: %s' % (method, response['error']))
    return response.get('result')


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else 'open'
    addon_id = sys.argv[2] if len(sys.argv) > 2 else ''
    xbmc.executebuiltin('UpdateLocalAddons', True)
    if action == 'refresh':
        return
    if action == 'settings':
        import xbmcaddon
        xbmcaddon.Addon(addon_id).openSettings()
        return
    if action == 'selftest':
        modules = {}
        for name in ('xbmc', 'xbmcaddon', 'xbmcgui', 'xbmcplugin', 'xbmcvfs', 'xbmcdrm', 'xbmcwsgi'):
            try:
                module = importlib.import_module(name)
                modules[name] = {'loaded': True, 'origin': getattr(module, '__file__', 'builtin')}
            except ImportError as error:
                modules[name] = {'loaded': False, 'error': str(error)}
        version = rpc('Application.GetProperties', properties=['version', 'name'])
        streams = {}
        for name in ('inputstream.adaptive', 'inputstream.ffmpegdirect'):
            streams[name] = rpc('Addons.GetAddonDetails', addonid=name, properties=['version', 'enabled'])['addon']
        report = {'engine': 'official-libkodi', 'application': version, 'python': sys.version,
                  'modules': modules, 'inputstream': streams,
                  'passed': all(x['loaded'] for x in modules.values()) and all(x['enabled'] for x in streams.values()),
                  'playback_tested': False, 'drm_tested': False}
        filename = xbmcvfs.translatePath('special://profile/addko-core-health.json')
        with open(filename + '.tmp', 'w', encoding='utf-8') as handle:
            json.dump(report, handle, ensure_ascii=False, indent=2)
        os.replace(filename + '.tmp', filename)
        xbmcgui.Dialog().ok('Teste do núcleo Kodi', 'APIs nativas e InputStream: %s\nReprodução e DRM precisam de teste com mídia.' % ('OK' if report['passed'] else 'FALHOU'))
        return
    if addon_id:
        # Kodi enables required dependencies through its real addon manager.
        rpc('Addons.SetAddonEnabled', addonid=addon_id, enabled=True)
        # Native RunAddon chooses Videos/Music/Pictures/Programs/Games or a
        # script according to the addon's actual extension/content type.
        xbmc.executebuiltin('RunAddon(%s)' % addon_id, True)
    else:
        rpc('GUI.ActivateWindow', window='addonbrowser')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        xbmc.log('AddKo core bridge: %s' % error, xbmc.LOGERROR)
        xbmcgui.Dialog().ok('AddKo — núcleo Kodi', str(error))
