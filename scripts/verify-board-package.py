#!/usr/bin/env python3
"""Verify an extracted GhostWave board package against an expected board and commit."""
import argparse
import hashlib
import json
from pathlib import Path

from importlib.util import module_from_spec, spec_from_file_location


def verify(directory, board, commit):
    manifest = json.loads((directory / 'manifest.json').read_text())
    if manifest['schema'] != 1 or manifest['board'] != board or manifest['source_commit'] != commit:
        raise ValueError('Package identity differs from expected board or source commit')
    spec = spec_from_file_location('board_packages', Path(__file__).with_name('package-board-firmware.py'))
    packages = module_from_spec(spec)
    spec.loader.exec_module(packages)
    kind = packages.BOARDS[board]
    expected = {'firmware.uf2'} if kind == 'uf2' else {'firmware.bin', 'bootloader.bin', 'partitions.bin'}
    if manifest['format'] != kind or set(manifest['sha256']) != expected:
        raise ValueError('Unexpected package format or image inventory')
    for name in sorted(expected):
        image = directory / name
        if image.is_symlink() or not image.is_file() or image.stat().st_size == 0:
            raise ValueError(f'Missing or invalid image: {name}')
        if hashlib.sha256(image.read_bytes()).hexdigest() != manifest['sha256'][name]:
            raise ValueError(f'Checksum mismatch: {name}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--board', required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    try:
        verify(args.directory, args.board, args.commit)
    except (ValueError, KeyError, TypeError, OSError) as error:
        parser.exit(1, f'Verification failed: {error}\n')
    print(f'Package checks passed for {args.board} at {args.commit}')
