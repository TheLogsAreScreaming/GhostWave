"""Validate release bundles before making them available to a browser."""
import hashlib
import json
from pathlib import Path
import re
import zipfile


def unpack_bundle(archive, destination):
    with zipfile.ZipFile(archive) as z:
        names = set()
        if sum(i.file_size for i in z.infolist()) > 32 * 1024 * 1024:
            raise ValueError('Firmware bundle exceeds size limit')
        for info in z.infolist():
            name = info.filename
            if not re.fullmatch(r'[A-Za-z0-9_.-]+', name) or name in ('.', '..') or name in names or info.is_dir() or (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Invalid or duplicate bundle path')
            names.add(name)
        z.extractall(destination)


def verify_esp(directory, board_id, flash_size):
    directory = Path(directory)
    provenance = json.loads((directory / 'provenance.json').read_text())
    manifest = json.loads((directory / 'install.json').read_text())
    if provenance.get('board') != board_id or not re.fullmatch(r'[0-9a-f]{40}', provenance.get('commit', '')):
        raise ValueError('Firmware board or source commit mismatch')
    if provenance.get('browserReady') is not True or provenance.get('flashSize') != flash_size:
        raise ValueError('Bundle is not browser-ready for this flash size; rebuild with merged-image packaging')
    if manifest.get('version') != provenance['commit'] or manifest.get('builds') != [{'chipFamily': 'ESP32-S3', 'parts': [{'path': 'firmware-merged.bin', 'offset': 0}]}]:
        raise ValueError('Unexpected ESP32 installer layout')
    hashes = provenance.get('sha256', {})
    if set(hashes) != {'install.json', 'firmware-merged.bin'}:
        raise ValueError('Incomplete firmware checksum inventory')
    for name, digest in hashes.items():
        path = directory / name
        if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f'Checksum mismatch: {name}')
    image = (directory / 'firmware-merged.bin').read_bytes()
    if not 0x10000 < len(image) <= flash_size or image[0] != 0xE9:
        raise ValueError('Invalid ESP32 merged image size or header')
    return provenance
