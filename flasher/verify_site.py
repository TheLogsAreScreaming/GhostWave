#!/usr/bin/env python3
"""Check a generated site before deployment: python3 flasher/verify_site.py DIST."""
import argparse
import hashlib
import json
from pathlib import Path
import re

from bundles import verify_esp
from build_site import init_packet, uf2_to_bin


def verify(root):
    boards = json.loads((root / 'manifest.json').read_text())['boards']
    seen = set()
    count = 0
    for board in boards:
        board_id = board['id']
        if not re.fullmatch(r'[A-Za-z0-9_-]+', board_id) or board_id in seen:
            raise ValueError(f'Invalid or duplicate board ID: {board_id}')
        seen.add(board_id)
        versions = set()
        for release in board['versions']:
            version = release['version']
            if not re.fullmatch(r'[0-9][A-Za-z0-9._+-]*', version) or version in versions:
                raise ValueError(f'Invalid or duplicate version for {board_id}')
            versions.add(version)
            directory = root / 'firmware' / board_id / version
            if board.get('transport') == 'esp-web-tools':
                provenance = verify_esp(directory, board_id, board['flashSize'])
                if provenance['commit'] != release['sourceCommit'] or hashlib.sha256((directory / 'installer.zip').read_bytes()).hexdigest() != release['sha256']:
                    raise ValueError('ESP32 release provenance or archive checksum mismatch')
                count += 1
                continue
            raw = (directory / 'firmware.uf2').read_bytes()
            if hashlib.sha256(raw).hexdigest() != release['sha256']:
                raise ValueError(f'{board_id} {version}: UF2 checksum mismatch')
            image = uf2_to_bin(raw, board['appStart'])
            for name, expected in [('firmware.bin', image), ('firmware.dat', init_packet(image, board['sdFwid']))]:
                if (directory / name).read_bytes() != expected:
                    raise ValueError(f'{board_id} {version}: {name} differs from expected payload')
            count += 1
    return count


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('site', type=Path)
    args = parser.parse_args()
    try:
        print(f'Verified {verify(args.site)} firmware versions')
    except (ValueError, KeyError, TypeError, OSError) as error:
        parser.exit(1, f'Flasher verification failed: {error}\n')
