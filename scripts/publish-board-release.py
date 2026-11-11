#!/usr/bin/env python3
"""Validate a successful main-branch build, then publish experimental board releases.

Defaults to validation/staging only. --publish explicitly creates releases.
Uses the signed-in gh account; no release credentials are stored in the repo.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'flasher'))
from bundles import unpack_bundle, verify_esp
from build_site import uf2_to_bin

SOURCE = 'TheLogsAreScreaming/GhostWave'
RELEASES = 'TheLogsAreScreaming/GhostWave-Releases'


def gh(*args):
    return subprocess.check_output(['gh', *map(str, args)], text=True)


def api(path):
    return json.loads(gh('api', path))


def prepare(run_id, out):
    run = api(f'repos/{SOURCE}/actions/runs/{run_id}')
    if run['conclusion'] != 'success' or run['head_branch'] != 'main' or run['path'] != '.github/workflows/board-packages.yml' or run['event'] not in ('push', 'workflow_dispatch'):
        raise ValueError('Expected a successful main-branch Selected board firmware packages run')
    commit = run['head_sha']
    comparison = api(f'repos/{SOURCE}/compare/{commit}...main')
    if comparison['status'] not in ('ahead', 'identical'):
        raise ValueError('Build source is not on main')
    source = api(f'repos/{SOURCE}/contents/firmware/mcu/src/main.cpp?ref={commit}')
    text = base64.b64decode(source['content']).decode()
    match = re.search(r'#define GW_FW_VERSION "([0-9][A-Za-z0-9.+-]*)"', text)
    if not match:
        raise ValueError('Cannot determine embedded firmware version')
    version = match[1].split('+')[0] + '+build.' + commit[:12]
    artifacts = api(f'repos/{SOURCE}/actions/runs/{run_id}/artifacts?per_page=100')['artifacts']
    catalog = json.loads((ROOT / 'flasher/board-catalog.json').read_text())['boards']
    configs = {b['id']: b for b in json.loads((ROOT / 'flasher/boards.json').read_text())['boards']}
    releases = []
    for board in catalog:
        board_id = board['id']
        esp = board['packageFormat'] == 'esp32'
        name = f"ghostwave-{board_id}{'-installer' if esp else ''}-{commit}"
        matches = [a for a in artifacts if a['name'] == name and not a['expired']]
        if len(matches) != 1:
            raise ValueError(f'Missing or duplicate artifact: {name}')
        artifact = matches[0]
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / 'artifact.zip'
            with archive.open('wb') as stream:
                subprocess.run(['gh', 'api', f'repos/{SOURCE}/actions/artifacts/{artifact["id"]}/zip'], stdout=stream, check=True)
            if artifact.get('digest') != 'sha256:' + hashlib.sha256(archive.read_bytes()).hexdigest():
                raise ValueError(f'{board_id}: GitHub artifact digest mismatch')
            directory = out / board_id
            directory.mkdir(parents=True)
            unpack_bundle(archive, directory)
        if esp:
            provenance = verify_esp(directory, board_id, configs[board_id]['flashSize'])
            if provenance['commit'] != commit:
                raise ValueError('ESP32 source commit mismatch')
            asset = out / f'ghostwave-{board_id}-{version}-installer.zip'
            with zipfile.ZipFile(asset, 'w', zipfile.ZIP_DEFLATED) as archive:
                for file in sorted(directory.iterdir()):
                    archive.write(file, file.name)
            assets = [asset]
        else:
            manifest = json.loads((directory / 'manifest.json').read_text())
            raw = (directory / 'firmware.uf2').read_bytes()
            if manifest.get('board') != board_id or manifest.get('source_commit') != commit or manifest.get('format') != 'uf2' or manifest.get('sha256') != {'firmware.uf2': hashlib.sha256(raw).hexdigest()}:
                raise ValueError(f'{board_id}: UF2 provenance mismatch')
            uf2_to_bin(raw, configs[board_id]['appStart'])
            asset = out / f'ghostwave-{board_id}-{version}.uf2'
            shutil.copyfile(directory / 'firmware.uf2', asset)
            assets = [asset, directory / 'manifest.json', directory / 'SHA256SUMS']
        notes = out / f'{board_id}-notes.md'
        notes.write_text(f'Experimental GhostWave firmware for {board["name"]}.\n\n'
                         f'Source: https://github.com/{SOURCE}/commit/{commit}\n'
                         f'Build: {run["html_url"]}\n\n'
                         'Compilation and package checks passed. Physical-board flashing, radio operation and recovery are not yet verified. '
                         'Use the exact board and matching bootloader described in SELECTED_TARGET_REFERENCE.md.\n')
        releases.append({'tag': f'fw-{board_id}-v{version}', 'assets': assets, 'notes': notes})
    return releases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=int, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    if args.out.exists():
        parser.error('--out must be a new directory')
    args.out.mkdir(parents=True)
    releases = prepare(args.run, args.out)
    print(f'Validated {len(releases)} board releases in {args.out}')
    if not args.publish:
        return
    existing = set(gh('api', '--paginate', f'repos/{RELEASES}/releases?per_page=100', '--jq', '.[].tag_name').splitlines())
    if any(r['tag'] in existing for r in releases):
        raise ValueError('A release tag already exists; nothing was changed')
    # Upload everything as drafts first. Do not replace or overwrite old releases.
    for release in releases:
        gh('release', 'create', release['tag'], *release['assets'], '-R', RELEASES,
           '--draft', '--prerelease', '--title', release['tag'], '--notes-file', release['notes'])
    for release in releases:
        gh('release', 'edit', release['tag'], '-R', RELEASES, '--draft=false', '--prerelease', '--latest=false')
        print('Published', release['tag'])


if __name__ == '__main__':
    main()
