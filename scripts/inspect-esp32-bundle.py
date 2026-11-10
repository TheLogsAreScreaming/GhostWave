#!/usr/bin/env python3
"""Inspect a GhostWave ESP32 installer bundle without connecting a device."""
import argparse
import hashlib
import json
from pathlib import Path


def inspect(directory):
    manifest = json.loads((directory / 'install.json').read_text())
    provenance = json.loads((directory / 'provenance.json').read_text())
    builds = manifest['builds']
    if len(builds) != 1 or builds[0]['chipFamily'] != 'ESP32-S3' or not builds[0]['parts']:
        raise ValueError('Unsupported or empty flash layout')
    if manifest['version'] != provenance['commit']:
        raise ValueError('Source commit mismatch')
    digests = provenance['sha256']
    manifest_digest = hashlib.sha256((directory / 'install.json').read_bytes()).hexdigest()
    if digests.get('install.json') != manifest_digest:
        raise ValueError('Installer manifest checksum mismatch')
    rows, names, end = [], set(), 0
    for part in sorted(builds[0]['parts'], key=lambda item: item['offset']):
        name, offset = part['path'], part['offset']
        if not isinstance(name, str) or Path(name).name != name or not name.endswith('.bin') or name in names:
            raise ValueError('Invalid or duplicate image name')
        image = directory / name
        if image.is_symlink() or not image.is_file():
            raise ValueError(f'Missing or invalid image: {name}')
        data = image.read_bytes()
        if type(offset) is not int or offset < end or offset % 4096 or not data:
            raise ValueError(f'Invalid flash range: {name}')
        if hashlib.sha256(data).hexdigest() != digests.get(name):
            raise ValueError(f'Checksum mismatch: {name}')
        end = offset + len(data)
        names.add(name)
        rows.append(f'{offset:#010x}  {len(data):8d} bytes  {name}')
    if names | {'install.json'} != set(digests):
        raise ValueError('Image inventory differs from provenance')
    return rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    try:
        print('\n'.join(inspect(args.directory)))
    except (ValueError, TypeError, KeyError, OSError) as error:
        parser.exit(1, f'Inspection failed: {error}\n')
