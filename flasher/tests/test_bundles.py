import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bundles import unpack_bundle, verify_esp

class Bundles(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.commit = 'a' * 40
        (self.root / 'firmware-merged.bin').write_bytes(b'\xe9' + b'\xff' * 0x10000)
        self.manifest = {'version': self.commit, 'builds': [{'chipFamily': 'ESP32-S3', 'parts': [{'path': 'firmware-merged.bin', 'offset': 0}]}]}
        (self.root / 'install.json').write_text(json.dumps(self.manifest))
        self.provenance = {'board': 'heltec_v3', 'commit': self.commit, 'flashSize': 8*1024*1024, 'browserReady': True, 'sha256': {n: hashlib.sha256((self.root / n).read_bytes()).hexdigest() for n in ['install.json', 'firmware-merged.bin']}}
        self.save()

    def save(self):
        (self.root / 'provenance.json').write_text(json.dumps(self.provenance))

    def verify(self):
        return verify_esp(self.root, 'heltec_v3', 8*1024*1024)

    def test_valid(self):
        self.assertEqual(self.verify()['commit'], self.commit)

    def test_corrupt_payload(self):
        (self.root / 'firmware-merged.bin').write_bytes(b'bad')
        with self.assertRaisesRegex(ValueError, 'Checksum'): self.verify()

    def test_wrong_board(self):
        self.provenance['board'] = 't_deck'; self.save()
        with self.assertRaisesRegex(ValueError, 'board'): self.verify()

    def test_old_unmerged_bundle(self):
        del self.provenance['browserReady']; self.save()
        with self.assertRaisesRegex(ValueError, 'browser-ready'): self.verify()

    def test_wrong_flash_size(self):
        self.provenance['flashSize'] = 16*1024*1024; self.save()
        with self.assertRaisesRegex(ValueError, 'flash size'): self.verify()

    def test_zip_traversal(self):
        archive = self.root / 'bad.zip'
        with zipfile.ZipFile(archive, 'w') as z: z.writestr('../escaped.bin', b'bad')
        with self.assertRaisesRegex(ValueError, 'path'): unpack_bundle(archive, self.root / 'out')
        self.assertFalse((self.root / 'escaped.bin').exists())

    def test_zip_duplicate(self):
        archive = self.root / 'bad.zip'
        with zipfile.ZipFile(archive, 'w') as z:
            z.writestr('same.bin', b'one'); z.writestr('same.bin', b'two')
        with self.assertRaisesRegex(ValueError, 'duplicate'): unpack_bundle(archive, self.root / 'out')

if __name__ == '__main__': unittest.main()
