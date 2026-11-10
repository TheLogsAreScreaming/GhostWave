#!/usr/bin/env python3
"""Create a web-install manifest from a build-resolved ESP32 flash layout."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


def package(layout_path, out, commit):
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
    out.mkdir(parents=True, exist_ok=False)
    parts, checksums = [], {}
    for index, (offset, source) in enumerate(images):
        name = f'image-{index}-{offset:x}.bin'
        shutil.copyfile(source, out / name)
        checksums[name] = hashlib.sha256((out / name).read_bytes()).hexdigest()
        parts.append({'path': name, 'offset': offset})
    manifest = {
        'name': f'GhostWave {board}', 'version': commit,
        'builds': [{'chipFamily': 'ESP32-S3', 'parts': parts}],
    }
    (out / 'install.json').write_text(json.dumps(manifest, indent=2) + '\n')
    checksums['install.json'] = hashlib.sha256((out / 'install.json').read_bytes()).hexdigest()
    (out / 'provenance.json').write_text(json.dumps({
        'board': board, 'commit': commit, 'sha256': checksums,
        'hardwareQualification': 'not established by build',
    }, indent=2) + '\n')
    (out / 'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in checksums.items()))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--layout', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    package(args.layout, args.out, args.commit)
