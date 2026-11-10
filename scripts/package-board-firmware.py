#!/usr/bin/env python3
"""Package a successful PlatformIO build without claiming hardware qualification."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

BOARDS = {
    'rak4631': 'uf2', 't1000e': 'uf2', 'heltec_t114': 'uf2',
    'wio_tracker_l1': 'uf2', 't_echo': 'uf2',
    'heltec_v4': 'esp32', 'heltec_v3': 'esp32', 't3s3': 'esp32',
    't_deck': 'esp32', 'heltec_wireless_tracker_v2': 'esp32',
    'heltec_wsl_v3': 'esp32',
}


def package(board, build_dir, out, commit):
    kind = BOARDS[board]
    names = ['firmware.uf2'] if kind == 'uf2' else ['firmware.bin', 'bootloader.bin', 'partitions.bin']
    # Validate before writing anything; missing boot components must fail the job.
    for name in names:
        source = build_dir / name
        if not source.is_file() or source.stat().st_size == 0:
            raise ValueError(f'{board}: missing or empty {source}')
    out.mkdir(parents=True, exist_ok=False)
    hashes = {}
    for name in names:
        shutil.copyfile(build_dir / name, out / name)
        hashes[name] = hashlib.sha256((out / name).read_bytes()).hexdigest()
    (out / 'manifest.json').write_text(json.dumps({
        'schema': 1, 'board': board, 'source_commit': commit,
        'hardware_qualification': 'not established by this build',
        'format': kind, 'sha256': hashes,
    }, indent=2) + '\n')
    (out / 'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in hashes.items()))
    (out / 'README.txt').write_text(
        f'GhostWave development build for {board}\nSource: {commit}\n'
        'A successful build does not establish hardware compatibility or qualification.\n'
        'Use only the exact board revision and matching bootloader documented by the project.\n'
        + ('UF2 application only; preserves the existing compatible bootloader.\n' if kind == 'uf2' else
           'Separate ESP32 images, not a merged factory image. Do not flash all files at address zero.\n'
           'Flash offsets and the framework boot_app0 image must be resolved from the PlatformIO upload configuration.\n'
           'Use the matching source and PlatformIO upload target until a board-specific installer is verified.\n'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--board', required=True, choices=BOARDS)
    parser.add_argument('--build-dir', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    package(args.board, args.build_dir, args.out, args.commit)
