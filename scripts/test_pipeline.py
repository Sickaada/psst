import importlib.util
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path
spec = importlib.util.spec_from_file_location('pipeline', Path(__file__).with_name('pipeline.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)

class PipelineTests(unittest.TestCase):
    def test_stale_or_foreign_status_rejected(self):
        self.assertFalse(p.fresh_status({'pid':4,'updatedAt':'2026-01-01T00:00:00Z'}, {4}, 1800000000))
        self.assertFalse(p.fresh_status({'pid':5,'updatedAt':'2026-01-01T00:00:00Z'}, {4}, 0))
        self.assertFalse(p.fresh_status({}, {4}, 0))
        self.assertTrue(p.fresh_status({'pid':4,'updatedAt':'2026-01-01T00:00:00Z'}, {4}, 0))
    def test_replace_failure_restores_old_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); live=root/'AlienPing.app'; candidate=root/'candidate.app'; backup=root/'old.app'
            live.mkdir(); (live/'version').write_text('old')
            with self.assertRaises(FileNotFoundError): p.swap_bundle(candidate,live,backup)
            self.assertEqual((live/'version').read_text(),'old')
    def test_swap_retains_backup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); live=root/'AlienPing.app'; candidate=root/'candidate.app'; backup=root/'old.app'
            live.mkdir(); candidate.mkdir()
            (live/'version').write_text('old'); (candidate/'version').write_text('new')
            p.swap_bundle(candidate,live,backup)
            self.assertEqual((live/'version').read_text(),'new')
            self.assertEqual((backup/'version').read_text(),'old')
    def test_startup_failure_rolls_back_and_relaunches(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); live=root/'AlienPing.app'; candidate=root/'candidate.app'; backup=root/'old.app'
            live.mkdir(); candidate.mkdir()
            (live/'version').write_text('old'); (candidate/'version').write_text('new')
            with patch.object(p,'LIVE',live), patch.object(p,'stop'), patch.object(p,'launch',side_effect=[RuntimeError('startup failed'), ({},0)]) as launch:
                with self.assertRaisesRegex(RuntimeError,'startup failed'):
                    p.install_and_start(candidate,backup,False,root/'failed.app')
                self.assertEqual((live/'version').read_text(),'old')
                self.assertEqual((root/'failed.app/version').read_text(),'new')
                self.assertEqual(launch.call_count,2)
    def test_update_launch_is_background_without_test_alerts(self):
        with tempfile.TemporaryDirectory() as tmp:
            logs=Path(tmp); (logs/'AlienPing-status.json').write_text('{}')
            with patch.object(p,'LOGS',logs), patch.object(p,'run') as run, patch.object(p,'pids',return_value=set()), patch.object(p,'fresh_status',return_value=True):
                p.launch()
                self.assertEqual(run.call_args.args[0],['open','-n','-g',str(p.LIVE),'--args','--background'])
    def test_process_match_is_exact(self):
        path='/test space/AlienPing.app/Contents/MacOS/AlienPing'
        self.assertEqual(p.match_pids('12 '+path+' --preview-all\n13 cat '+path+'\n14 '+path+'Other',path),{12})

if __name__=='__main__': unittest.main()
