#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('bundle', Path(__file__).with_name('package-esp32-bundle.py'))
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.layout = {'schema': 1, 'chip': 'esp32s3', 'board': 'heltec_v3', 'flashSize': '8MB', 'images': []}
        for i, offset in enumerate([0, 0x8000, 0xE000, 0x10000]):
            path = self.root / f'{i}.bin'
            path.write_bytes(bytes([i]) * 128)
            self.layout['images'].append({'source': str(path), 'offset': offset})

    def run_bundle(self):
        path = self.root / 'layout.json'
        path.write_text(json.dumps(self.layout))
        bundle.package(path, self.root / 'out', 'abc123')

    def test_complete_layout(self):
        self.run_bundle()
        manifest = json.loads((self.root / 'out/install.json').read_text())
        self.assertEqual([p['offset'] for p in manifest['builds'][0]['parts']], [0, 0x8000, 0xE000, 0x10000])
        self.assertEqual(len(list((self.root / 'out').glob('*.bin'))), 4)

    def test_overlap(self):
        self.layout['images'][1]['offset'] = 0
        with self.assertRaisesRegex(ValueError, 'Overlapping'):
            self.run_bundle()
        self.assertFalse((self.root / 'out').exists())

    def test_missing(self):
        Path(self.layout['images'][0]['source']).unlink()
        with self.assertRaisesRegex(ValueError, 'Missing'):
            self.run_bundle()

    def test_flash_bounds(self):
        self.layout['images'][-1]['offset'] = 8 * 1024 * 1024
        with self.assertRaisesRegex(ValueError, 'exceeds'):
            self.run_bundle()

    def test_alignment(self):
        self.layout['images'][0]['offset'] = 1
        with self.assertRaisesRegex(ValueError, 'unaligned'):
            self.run_bundle()


if __name__ == '__main__':
    unittest.main()
