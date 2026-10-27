import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'verify_app.py'


class BuiltAppGateTests(unittest.TestCase):
    def test_rejects_wrong_bundle_ipad_and_missing_compiled_catalog(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            info = {'CFBundleIdentifier': 'com.infinityball.delve', 'UIDeviceFamily': [1],
                    'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIcon'}}}
            def run_gate():
                (app / 'Info.plist').write_bytes(plistlib.dumps(info))
                return subprocess.run([sys.executable, str(SCRIPT), str(app)], capture_output=True).returncode
            self.assertNotEqual(run_gate(), 0)
            (app / 'Assets.car').write_bytes(b'fixture catalog presence; actual compiler runs only on macOS')
            self.assertNotEqual(run_gate(), 0)
            (app / 'AppIcon60x60@2x.png').write_bytes(b'fixture raster; actual compiler runs only on macOS')
            self.assertEqual(run_gate(), 0)
            del info['CFBundleIcons']  # Xcode 26 may omit icon metadata for a single-size icon.
            self.assertEqual(run_gate(), 0)
            info['CFBundleIcons'] = {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIcon'}}
            self.assertEqual(run_gate(), 0)
            info['UIDeviceFamily'] = [1, 2]
            self.assertNotEqual(run_gate(), 0)
            info['UIDeviceFamily'] = [1]
            info['CFBundleIdentifier'] = 'wrong.bundle'
            self.assertNotEqual(run_gate(), 0)
            info['CFBundleIdentifier'] = 'com.infinityball.delve'
            info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'] = 'WrongIcon'
            self.assertNotEqual(run_gate(), 0)
