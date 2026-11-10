#!/usr/bin/env python3
"""Verify package contents without a compiler or physical radio."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('packager', ROOT / 'scripts/package-board-firmware.py')
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class Packages(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.build = self.root / 'build'
        self.build.mkdir()
        self.images = {
            'firmware.uf2': b'uf2 fixture', 'firmware.bin': b'application',
            'bootloader.bin': b'bootloader', 'partitions.bin': b'partitions',
        }
        for name, data in self.images.items():
            (self.build / name).write_bytes(data)

    def test_all_targets_have_exact_images_and_independent_checksums(self):
        for board, kind in packager.BOARDS.items():
            with self.subTest(board=board):
                out = self.root / board
                packager.package(board, self.build, out, 'source-sha')
                expected = ['firmware.uf2'] if kind == 'uf2' else ['firmware.bin', 'bootloader.bin', 'partitions.bin']
                self.assertEqual({p.name for p in out.iterdir()}, set(expected) | {'README.txt', 'manifest.json', 'SHA256SUMS'})
                manifest = json.loads((out / 'manifest.json').read_text())
                self.assertEqual(manifest['source_commit'], 'source-sha')
                self.assertEqual(manifest['board'], board)
                for name in expected:
                    self.assertEqual((out / name).read_bytes(), self.images[name])
                    digest = hashlib.sha256(self.images[name]).hexdigest()
                    self.assertEqual(manifest['sha256'][name], digest)
                    self.assertIn(f'{digest}  {name}\n', (out / 'SHA256SUMS').read_text())

    def test_missing_and_empty_images_leave_no_output(self):
        for board, name in [('rak4631', 'firmware.uf2'), ('heltec_v3', 'bootloader.bin')]:
            for empty in [True, False]:
                with self.subTest(board=board, empty=empty):
                    target = self.build / name
                    target.write_bytes(b'') if empty else target.unlink()
                    out = self.root / 'rejected'
                    with self.assertRaises(ValueError):
                        packager.package(board, self.build, out, 'source-sha')
                    self.assertFalse(out.exists())
                    target.write_bytes(self.images[name])

    def test_existing_output_is_not_overwritten(self):
        out = self.root / 'existing'
        out.mkdir()
        (out / 'keep').write_text('original')
        with self.assertRaises(FileExistsError):
            packager.package('rak4631', self.build, out, 'source-sha')
        self.assertEqual((out / 'keep').read_text(), 'original')


if __name__ == '__main__':
    unittest.main()
