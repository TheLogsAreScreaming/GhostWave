#!/usr/bin/env python3
"""Create a web-install manifest from a build-resolved ESP32 flash layout."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


def package(layout_path, out, commit, esptool=None):
    layout = json.loads(layout_path.read_text())
    if layout.get('schema') != 1 or layout.get('chip') != 'esp32s3':
        raise ValueError('Unsupported flash-layout schema or chip')
    board = layout.get('board', '')
    if not re.fullmatch(r'[a-z0-9_]+', board):
        raise ValueError('Invalid board identifier')
    size = re.fullmatch(r'(\d+)MB', layout.get('flashSize', ''))
    if not size:
        raise ValueError('Missing flash size')
    limit = int(size[1]) * 1024 * 1024
    images, end = [], 0
    for image in sorted(layout['images'], key=lambda item: item['offset']):
        offset, source = image['offset'], Path(image['source'])
        if not isinstance(offset, int) or offset < end or offset % 4096:
            raise ValueError('Overlapping or unaligned flash images')
        if not source.is_file() or not source.stat().st_size:
            raise ValueError('Missing flash image')
        end = offset + source.stat().st_size
        if end > limit:
            raise ValueError('Image exceeds flash size')
        images.append((offset, source))
    if len(images) < 3:
        raise ValueError('Incomplete flash layout')
    if esptool:
        if layout.get('flashMode') not in ('dio', 'dout', 'qio', 'qout') or layout.get('flashFreq') not in ('20m', '26m', '40m', '80m', '120m'):
            raise ValueError('Missing resolved flash mode or frequency; rebuild the firmware')
    out.mkdir(parents=True, exist_ok=False)
    parts, checksums = [], {}
    for index, (offset, source) in enumerate(images):
        name = f'image-{index}-{offset:x}.bin'
        shutil.copyfile(source, out / name)
        checksums[name] = hashlib.sha256((out / name).read_bytes()).hexdigest()
        parts.append({'path': name, 'offset': offset})
    if esptool:
        # esptool updates the bootloader header with the same settings as pio upload.
        try:
            subprocess.run([
                sys.executable, str(esptool), '--chip', 'esp32s3', 'merge_bin',
                '--flash_mode', layout['flashMode'], '--flash_freq', layout['flashFreq'],
                '--flash_size', layout['flashSize'], '-o', str(out / 'firmware-merged.bin'),
                *[arg for offset, source in images for arg in (hex(offset), str(source))],
            ], check=True)
        except BaseException:
            shutil.rmtree(out)
            raise
        for part in parts:
            (out / part['path']).unlink()
        checksums = {'firmware-merged.bin': hashlib.sha256((out / 'firmware-merged.bin').read_bytes()).hexdigest()}
        parts = [{'path': 'firmware-merged.bin', 'offset': 0}]
    manifest = {
        'name': f'GhostWave {board}', 'version': commit,
        'builds': [{'chipFamily': 'ESP32-S3', 'parts': parts}],
        'new_install_prompt_erase': True, 'new_install_improv_wait_time': 0,
    }
    (out / 'install.json').write_text(json.dumps(manifest, indent=2) + '\n')
    checksums['install.json'] = hashlib.sha256((out / 'install.json').read_bytes()).hexdigest()
    (out / 'provenance.json').write_text(json.dumps({
        'board': board, 'commit': commit, 'sha256': checksums,
        'hardwareQualification': 'not established by build',
        'flashSize': limit, 'browserReady': bool(esptool),
    }, indent=2) + '\n')
    (out / 'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in checksums.items()))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--layout', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--esptool', type=Path, help='Pinned PlatformIO esptool.py; produces a browser-ready merged image')
    args = parser.parse_args()
    package(args.layout, args.out, args.commit, args.esptool)
