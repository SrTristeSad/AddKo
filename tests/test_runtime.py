import importlib.util
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHIMS = ROOT / 'runtime/python/shims'
spec = importlib.util.spec_from_file_location('worker', ROOT / 'runtime/python/addko_worker.py')
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)

class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.addon = self.base / 'addons/plugin.video.test'
        self.addon.mkdir(parents=True)
        self.context = dict(shims_path=str(SHIMS), addon_path=str(self.addon),
            addons_root=str(self.addon.parent), plugin_url='plugin://plugin.video.test/',
            handle=1, query='', entrypoint_path=str(self.addon/'default.py'),
            special_paths={'special://profile': str(self.base/'profile')})
    def tearDown(self):
        self.tmp.cleanup()
    def run_worker(self, source):
        (self.addon/'default.py').write_text(source)
        path = self.base/'context.json'
        path.write_text(json.dumps(self.context))
        result = subprocess.run([sys.executable, str(ROOT/'runtime/python/addko_worker.py'),str(path)],
            capture_output=True, text=True, timeout=10)
        events = [json.loads(line[len('ADDKO_RPC '):]) for line in result.stdout.splitlines() if line.startswith('ADDKO_RPC ')]
        return result, events
    def test_directory(self):
        result, events = self.run_worker("import xbmcgui, xbmcplugin\nxbmcplugin.addDirectoryItem(1, 'plugin://plugin.video.test/page2', xbmcgui.ListItem('Pagina 2'), True)\nxbmcplugin.endOfDirectory(1, updateListing=True, cacheToDisc=False)\n")
        self.assertEqual(result.returncode,0,result.stderr)
        item = next(e for e in events if e['method']=='xbmcplugin.addDirectoryItem')
        self.assertTrue(item['params']['is_folder'])
        end = next(e for e in events if e['method']=='xbmcplugin.endOfDirectory')
        self.assertTrue(end['params']['update_listing'])
        self.assertFalse(end['params']['cache_to_disc'])
    def test_resolved_video(self):
        result, events = self.run_worker("import xbmcgui, xbmcplugin\ni=xbmcgui.ListItem(path='https://example.test/video.m3u8')\ni.setProperty('inputstream', 'inputstream.adaptive')\nxbmcplugin.setResolvedUrl(1, True, i)\n")
        self.assertEqual(result.returncode,0,result.stderr)
        item=next(e for e in events if e['method']=='xbmcplugin.setResolvedUrl')['params']['item']
        self.assertEqual(item['path'],'https://example.test/video.m3u8')
        self.assertEqual(item['properties']['inputstream'],'inputstream.adaptive')
    def test_string_exit_is_failure(self):
        result, events=self.run_worker("raise SystemExit('erro real')")
        self.assertEqual(result.returncode,1)
        self.assertTrue(any(e['method']=='invocation.error' for e in events))
        self.assertFalse(any(e['method']=='invocation.complete' for e in events))
    def test_traceback_keeps_addon_location(self):
        result, events=self.run_worker("raise ValueError('teste')")
        self.assertEqual(result.returncode,1)
        error=next(e for e in events if e['method']=='invocation.error')
        self.assertIn('default.py:1',error['params']['addon_location'])
    def test_entrypoint_outside_addon_rejected(self):
        outside=self.base/'outside.py';outside.write_text("raise Exception('must not execute')")
        self.context['entrypoint_path']=str(outside)
        result, events=self.run_worker('pass')
        self.assertEqual(result.returncode,3)
    def test_addon_installed_during_execution_detected(self):
        result, events=self.run_worker("import xbmc\nfrom pathlib import Path\nassert not xbmc.getCondVisibility('System.HasAddon(plugin.video.new)')\np=Path(__file__).parent.parent/'plugin.video.new'\np.mkdir()\n(p/'addon.xml').write_text('<addon/>')\nassert xbmc.getCondVisibility('System.HasAddon(plugin.video.new)')\n")
        self.assertEqual(result.returncode,0,result.stderr+result.stdout)
    def test_disabled_database_record_preserved(self):
        self.context['installed_addons']={'plugin.video.test':'1.0'}
        worker._ensure_kodi_addon_database(self.context)
        db=self.base/'profile/Database/Addons33.db'
        with closing(sqlite3.connect(db)) as con:
            with con:
                con.execute('UPDATE installed SET enabled=0')
        with self.assertRaises(sqlite3.ProgrammingError):
            con.execute('SELECT 1')
        worker._ensure_kodi_addon_database(self.context)
        with closing(sqlite3.connect(db)) as con:
            self.assertEqual(con.execute('SELECT enabled FROM installed').fetchone()[0],0)
        with self.assertRaises(sqlite3.ProgrammingError):
            con.execute('SELECT 1')
    def test_standalone_call_does_not_wait_on_stdin(self):
        env=dict(os.environ);env.pop('ADDKO_CONTEXT_FILE',None)
        result=subprocess.run([sys.executable,'-c',"import sys;sys.path.insert(0,sys.argv[1]);import addko_bridge;assert addko_bridge.request('test', default=21)==21",str(SHIMS)],capture_output=True,text=True,timeout=3,env=env)
        self.assertEqual(result.returncode,0,result.stderr)

if __name__=='__main__':
    unittest.main()
