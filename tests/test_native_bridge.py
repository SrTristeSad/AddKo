"""Offline bridge contract tests. The on-device self-test exercises actual native APIs."""
from contextlib import ExitStack
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'third_party/kodi_21_3/assets/addons/script.addko.bridge/default.py'

class NativeBridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.calls = []
        self.builtins = []
        self.dialogs = []
        self.error_method = None
        self.stack = ExitStack()
        def execute(raw):
            request = json.loads(raw)
            self.calls.append(request)
            method = request['method']
            if method == self.error_method: return json.dumps({'error': {'message':'rejected'}})
            if method == 'Application.GetProperties': result = {'version': {'major':21,'minor':3},'name':'Kodi'}
            elif method == 'Addons.GetAddonDetails': result = {'addon': {'addonid':request['params']['addonid'],'enabled':True,'version':'21'}}
            else: result='OK'
            return json.dumps({'result': result})
        modules={name:types.ModuleType(name) for name in ('xbmc','xbmcaddon','xbmcgui','xbmcplugin','xbmcvfs','xbmcdrm','xbmcwsgi')}
        modules['xbmc'].executeJSONRPC=execute
        modules['xbmc'].executebuiltin=lambda *args:self.builtins.append(args)
        modules['xbmcgui'].Dialog=lambda:types.SimpleNamespace(ok=lambda *args:self.dialogs.append(args))
        modules['xbmcvfs'].translatePath=lambda _:str(Path(self.tmp.name)/'health.json')
        self.stack.enter_context(patch.dict(sys.modules,modules))
        spec=importlib.util.spec_from_file_location('native_bridge_test',SCRIPT)
        self.bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.bridge)
    def tearDown(self):
        self.stack.close();self.tmp.cleanup()
    def test_enable_and_open_addon_via_kodi_manager(self):
        with patch.object(sys,'argv',['default.py','open','plugin.video.example']): self.bridge.main()
        self.assertEqual(self.builtins,[('UpdateLocalAddons',True),('RunAddon(plugin.video.example)',True)])
        self.assertEqual([c['method'] for c in self.calls],['Addons.SetAddonEnabled'])
    def test_failed_enable_does_not_open_blank_folder(self):
        self.error_method='Addons.SetAddonEnabled'
        with patch.object(sys,'argv',['default.py','open','plugin.video.example']):
            with self.assertRaises(RuntimeError):self.bridge.main()
        self.assertEqual(self.builtins,[('UpdateLocalAddons',True)])
    def test_selftest_records_native_api_state_but_not_playback(self):
        with patch.object(sys,'argv',['default.py','selftest','']):self.bridge.main()
        data=json.loads((Path(self.tmp.name)/'health.json').read_text())
        self.assertTrue(data['passed'])
        self.assertEqual(len(data['modules']),7)
        self.assertFalse(data['playback_tested'])
        self.assertFalse(data['drm_tested'])
        self.assertFalse((Path(self.tmp.name)/'health.json.tmp').exists())
    def test_root_opens_real_addon_browser(self):
        with patch.object(sys,'argv',['default.py','open','']):self.bridge.main()
        self.assertEqual(self.calls[-1]['params']['window'],'addonbrowser')
    def test_refresh_does_not_open_kodi_navigation(self):
        with patch.object(sys,'argv',['default.py','refresh','']):self.bridge.main()
        self.assertEqual(self.builtins,[('UpdateLocalAddons',True)])
        self.assertEqual(self.calls,[])

if __name__=='__main__':unittest.main()
