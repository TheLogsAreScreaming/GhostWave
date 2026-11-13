#!/usr/bin/env python3
"""One-command GhostWave release: firmware, app, web flasher and site PR.

    python3 scripts/release.py --out /tmp/gw-release            # dry run: download, check, stage
    python3 scripts/release.py --out /tmp/gw-release --publish  # create the releases, open the site PR

From one commit on main (default: main's head) whose CI, App and board-package
runs all passed, it:

1. Firmware, if this commit's GW_FW_VERSION has no release yet: the nRF UF2s
   from the CI run (each checked to embed that version), plus the 11 board
   packages via publish-board-release.py. An unchanged version is skipped.
2. App: the next app-v0.1.0-dev.N with the APK, Windows and macOS builds,
   SHA256SUMS, and notes listing the PRs merged since the last app release.
3. Web flasher: rebuilt with flasher/build_site.py and checked with verify_site.py.
4. Site (with --site PATH to a meshmayhem-site clone): a branch with the new
   flasher and the GhostWave page's downloads moved to the new app, pushed as a
   pull request. It never merges or deploys: that stays a person's call.

Nothing is published without --publish. Existing tags are never overwritten.
Uses the signed-in gh account; no credentials are stored in the repo.
"""
import argparse
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'TheLogsAreScreaming/GhostWave'
RELEASES = 'TheLogsAreScreaming/GhostWave-Releases'
SITE_REPO = 'TheLogsAreScreaming/meshmayhem-site'

# nRF boards published from the CI workflow's UF2 artifacts, with the
# bootloader each needs (what INFO_UF2.TXT must say).
NRF_UF2 = {
    'rak4631': 'S140 6.1.1',
    'rak3401_1w': 'S140 6.1.1',
    't1000e': 'S140 7.3.0',
    'rak_wismesh_tag': 'S140 6.1.1',
}
APP_ASSETS = {  # artifact name -> (file pattern in it, published suffix)
    'ghostwave-app-apk': ('*.apk', 'arm64.apk'),
    'ghostwave-windows': ('*.zip', 'windows-x64.zip'),
    'ghostwave-macos': ('*.zip', 'macos.zip'),
}
WORKFLOWS = {'ci': '.github/workflows/ci.yml', 'app': '.github/workflows/app.yml',
             'boards': '.github/workflows/board-packages.yml'}


# ------------------------------------------------------------ pure helpers --

def firmware_version(main_cpp: str) -> str:
    """GW_FW_VERSION from firmware/mcu/src/main.cpp."""
    m = re.search(r'#define GW_FW_VERSION "([0-9][A-Za-z0-9.+-]*)"', main_cpp)
    if not m:
        raise ValueError('cannot find GW_FW_VERSION')
    return m[1]


def uf2_payload(data: bytes) -> bytes:
    """The bytes a UF2 file writes to flash, in block order."""
    if len(data) % 512:
        raise ValueError('UF2 size is not a multiple of 512')
    out = bytearray()
    for i in range(0, len(data), 512):
        block = data[i:i + 512]
        if block[:4] != b'UF2\n' or block[508:512] != bytes.fromhex('30 6f b1 0a'.replace(' ', '')):
            raise ValueError(f'bad UF2 block at {i}')
        size = int.from_bytes(block[16:20], 'little')
        out += block[32:32 + size]
    return bytes(out)


def next_app_version(tags) -> str:
    """The next 0.1.0-dev.N after the highest app-v0.1.0-dev.N tag."""
    nums = [int(m[1]) for t in tags if (m := re.fullmatch(r'app-v0\.1\.0-dev\.(\d+)', t))]
    return f'0.1.0-dev.{max(nums, default=0) + 1}'


def source_commit(release_body: str):
    """The 40-hex source commit a release's notes name, or None."""
    m = re.search(r'Source commit: ([0-9a-f]{40})', release_body or '')
    return m[1] if m else None


LOG_FORMAT = '%s%x1f%b%x1e'


def pr_lines(log: str):
    """'- title (#123)' lines from `git log --format=LOG_FORMAT`: squash merges
    carry the title in the subject, merge commits in the body's first line."""
    lines = []
    for record in log.split('\x1e'):
        subject, _, body = record.strip().partition('\x1f')
        subject = subject.strip()
        if m := re.fullmatch(r'(.+?) \(#(\d+)\)', subject):
            lines.append(f'- {m[1]} (#{m[2]})')
        elif m := re.fullmatch(r'Merge pull request #(\d+) from \S+', subject):
            title = body.strip().splitlines()[0].strip() if body.strip() else ''
            lines.append(f'- {title} (#{m[1]})' if title else f'- #{m[1]}')
    return lines


def rewrite_downloads(html: str, version: str) -> str:
    """Points the GhostWave page's app downloads and version labels at [version]."""
    html = re.sub(r'app-v0\.1\.0-dev\.\d+/ghostwave-app-0\.1\.0-dev\.\d+',
                  f'app-v{version}/ghostwave-app-{version}', html)
    return re.sub(r'Version 0\.1\.0-dev\.\d+', f'Version {version}', html)


def nrf_notes(board, version, commit, run_url, bootloader, sha256) -> str:
    return (f'**Test build.** Built by [CI]({run_url}) from main at {commit[:7]}.\n\n'
            f'- **Bootloader:** `INFO_UF2.TXT` must say **{bootloader}**. **Pairing key:** `654321`. '
            '**Transmit is off** on a fresh board until `tx on`. Settings, identity and `tx on` survive an update.\n\n'
            f'**Flashing:** the [web flasher](https://www.meshmayhem.org/webflasher/), or drag '
            f'`ghostwave-{board}-{version}.uf2` onto the UF2 drive.\n\nSHA-256: `{sha256}`\n')


def app_notes(version, build, commit, run_url, apk_sha, changes) -> str:
    listed = '\n'.join(changes) if changes else '- Maintenance build.'
    return (f'Development prerelease. Android arm64 APK signed with the GhostWave development key, plus Windows (x64) '
            f'and macOS builds. Shows as **1.0.0 ({2000 + build})** in Android\'s app info.\n\n'
            f'Merged since the last app release:\n\n{listed}\n\n'
            f'Source commit: {commit}. [App CI run]({run_url}). Windows and macOS builds have not been opened on '
            f'a computer by this script.\n\nAPK SHA-256: `{apk_sha}`\n')


# ----------------------------------------------------------------- GitHub --

def gh(*args, text=True):
    return subprocess.check_output(['gh', *map(str, args)], text=text)


def api(path):
    return json.loads(gh('api', path))


def release_tags():
    return set(gh('api', '--paginate', f'repos/{RELEASES}/releases?per_page=100', '--jq', '.[].tag_name').split())


def runs_for(commit, keys):
    """The newest successful run of each workflow in [keys] for [commit] on main."""
    runs = api(f'repos/{SOURCE}/actions/runs?head_sha={commit}&branch=main&per_page=50')['workflow_runs']
    found = {}
    for key in keys:
        path = WORKFLOWS[key]
        mine = [r for r in runs if r['path'] == path and r['event'] in ('push', 'workflow_dispatch')]
        if not mine:
            hint = (' (it runs only when firmware/ changes: release firmware from the commit that changed it, '
                    'or pass --skip-firmware)') if key == 'boards' else ''
            raise ValueError(f'no {key} run for {commit[:7]} on main{hint}')
        run = max(mine, key=lambda r: r['run_number'])
        if run['status'] != 'completed' or run['conclusion'] != 'success':
            raise ValueError(f'{key} run {run["html_url"]} is {run["status"]}/{run["conclusion"]}, not a success')
        found[key] = run
    return found


def download(run_id, artifact, dest: Path):
    dest.mkdir(parents=True, exist_ok=True)
    gh('run', 'download', run_id, '-R', SOURCE, '-n', artifact, '-D', dest)
    files = [p for p in dest.rglob('*') if p.is_file()]
    if not files:
        raise ValueError(f'artifact {artifact} is empty')
    return files


def load_board_publisher():
    spec = importlib.util.spec_from_file_location('publish_board_release', ROOT / 'scripts/publish-board-release.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ------------------------------------------------------------------- steps --

def firmware_to_release(commit, tags):
    """This commit's firmware version, and whether it still needs releasing."""
    src = api(f'repos/{SOURCE}/contents/firmware/mcu/src/main.cpp?ref={commit}')
    version = firmware_version(base64.b64decode(src['content']).decode())
    return version, not any(f'fw-{b}-v{version}' in tags for b in NRF_UF2)


def stage_firmware(commit, version, runs, tags, out: Path):
    plan = []
    for board, bootloader in NRF_UF2.items():
        files = download(runs['ci']['id'], f'ghostwave-{board}-uf2', out / 'uf2' / board)
        uf2 = next(f for f in files if f.suffix == '.uf2')
        raw = uf2.read_bytes()
        if version.encode() not in uf2_payload(raw):
            raise ValueError(f'{board}: UF2 does not embed {version}')
        asset = out / 'uf2' / f'ghostwave-{board}-{version}.uf2'
        shutil.copyfile(uf2, asset)
        sha = hashlib.sha256(raw).hexdigest()
        notes = out / 'uf2' / f'{board}-notes.md'
        notes.write_text(nrf_notes(board, version, commit, runs['ci']['html_url'], bootloader, sha))
        plan.append({'tag': f'fw-{board}-v{version}', 'assets': [asset], 'notes': notes})
        print(f'firmware {board}: {version} checked, sha256 {sha[:12]}…')
    boards = load_board_publisher().prepare(runs['boards']['id'], out / 'boards')
    if any(r['tag'] in tags for r in boards):
        raise ValueError('a board package tag already exists')
    print(f'firmware: {len(boards)} board packages checked')
    return plan, boards


def stage_app(commit, runs, tags, out: Path, version=None):
    version = version or next_app_version(tags)
    if f'app-v{version}' in tags:
        raise ValueError(f'app-v{version} already exists')
    previous = sorted((t for t in tags if t.startswith('app-v0.1.0-dev.')),
                      key=lambda t: int(t.rsplit('.', 1)[1]))
    changes = []
    if previous:
        body = gh('release', 'view', previous[-1], '-R', RELEASES, '--json', 'body', '--jq', '.body')
        since = source_commit(body)
        if since == commit:
            raise ValueError(f'{previous[-1]} was already built from {commit[:7]}: nothing new for the app '
                             '(pass --skip-app to release only firmware)')
        if since:
            subprocess.run(['git', '-C', ROOT, 'fetch', '-q', 'origin', 'main'], check=False)
            try:
                log = subprocess.check_output(['git', '-C', ROOT, 'log', f'--format={LOG_FORMAT}', f'{since}..{commit}'], text=True)
                changes = pr_lines(log)
            except subprocess.CalledProcessError:
                print('app: could not list changes (commits not in this clone); notes say so')
    assets = []
    for artifact, (pattern, suffix) in APP_ASSETS.items():
        files = download(runs['app']['id'], artifact, out / 'app' / artifact)
        src = next(f for f in files if f.match(pattern))
        dest = out / 'app' / f'ghostwave-app-{version}-{suffix}'
        shutil.copyfile(src, dest)
        assets.append(dest)
    sums = out / 'app' / 'SHA256SUMS'
    sums.write_text(''.join(f'{hashlib.sha256(a.read_bytes()).hexdigest()}  {a.name}\n' for a in assets))
    notes = out / 'app' / 'notes.md'
    apk_sha = hashlib.sha256(assets[0].read_bytes()).hexdigest()
    notes.write_text(app_notes(version, runs['app']['run_number'], commit, runs['app']['html_url'], apk_sha, changes))
    print(f'app {version}: {len(assets)} builds, {len(changes)} changes listed')
    return version, {'tag': f'app-v{version}', 'assets': [*assets, sums], 'notes': notes}


def build_flasher(out: Path):
    site = out / 'webflasher'
    subprocess.run([sys.executable, ROOT / 'flasher/build_site.py', '--out', site], check=True)
    subprocess.run([sys.executable, ROOT / 'flasher/verify_site.py', site], check=True)
    return site


def publish(release, title):
    gh('release', 'create', release['tag'], *release['assets'], '-R', RELEASES, '--draft', '--prerelease',
       '--title', title, '--notes-file', release['notes'])
    gh('release', 'edit', release['tag'], '-R', RELEASES, '--draft=false', '--prerelease', '--latest=false')
    print('published', release['tag'])


def site_pr(site_clone: Path, flasher: Path, app_version, fw_version, out: Path, push: bool):
    branch = f'release/ghostwave-{app_version}'
    if not push:
        # dry run: show the page change without touching the site clone
        preview = out / 'site-preview'
        preview.mkdir()
        current = subprocess.check_output(['git', '-C', site_clone, 'show', 'origin/main:public/GhostWave.html'], text=True)
        (preview / 'GhostWave.html').write_text(rewrite_downloads(current, app_version))
        print(f'site: would open {branch} with the flasher in {flasher} and {preview / "GhostWave.html"}')
        return
    work = out / 'site'
    subprocess.run(['git', '-C', site_clone, 'fetch', '-q', 'origin'], check=True)
    subprocess.run(['git', '-C', site_clone, 'worktree', 'add', '-q', '-b', branch, work, 'origin/main'], check=True)
    shutil.copytree(flasher, work / 'public/webflasher', dirs_exist_ok=True)  # older firmware paths stay
    page = work / 'public/GhostWave.html'
    page.write_text(rewrite_downloads(page.read_text(), app_version))
    subprocess.run(['git', '-C', work, 'add', '-A', 'public'], check=True)
    subprocess.run(['git', '-C', work, 'commit', '-q', '-m',
                    f'GhostWave: flasher firmware {fw_version}, downloads app {app_version}'], check=True)
    print(f'site: branch {branch} committed in {work}')
    subprocess.run(['git', '-C', work, 'push', '-q', '-u', 'origin', branch], check=True)
    url = gh('pr', 'create', '-R', SITE_REPO, '--base', 'main', '--head', branch,
             '--title', f'GhostWave: flasher {fw_version}, downloads {app_version}',
             '--body', 'Made by GhostWave scripts/release.py. Not deployed: merge it, then check the live page '
                       '(deploy with `npx wrangler deploy` from a clean main if Workers Builds does not run).').strip()
    print('site PR:', url)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--out', type=Path, required=True, help='a new directory for downloads and staging')
    p.add_argument('--commit', help='commit on main (default: main head)')
    p.add_argument('--app-version', help='e.g. 0.1.0-dev.25 (default: the next dev number)')
    p.add_argument('--site', type=Path, help='a meshmayhem-site clone, to prepare the site PR')
    p.add_argument('--skip-firmware', action='store_true')
    p.add_argument('--skip-app', action='store_true')
    p.add_argument('--publish', action='store_true', help='create the releases and push the site PR')
    a = p.parse_args()
    if a.out.exists():
        p.error('--out must be a new directory')
    a.out.mkdir(parents=True)
    commit = a.commit or api(f'repos/{SOURCE}/commits/main')['sha']
    if api(f'repos/{SOURCE}/compare/{commit}...main')['status'] not in ('ahead', 'identical'):
        p.error(f'{commit} is not on main')
    print(f'release from {commit[:7]}' + ('' if a.publish else ' (dry run: nothing is published)'))
    tags = release_tags()
    fw_version, fw_new = firmware_to_release(commit, tags)
    if a.skip_firmware or not fw_new:
        print(f'firmware {fw_version}: ' + ('skipped' if a.skip_firmware else 'already released, skipped'))
        fw_new = False
    # the App workflow skips firmware-only commits, so an app build is only
    # required when the app is being released
    runs = runs_for(commit, ['ci', *([] if a.skip_app else ['app']), *(['boards'] if fw_new else [])])
    nrf, boards = stage_firmware(commit, fw_version, runs, tags, a.out) if fw_new else ([], None)
    app_version, app = (None, None) if a.skip_app else stage_app(commit, runs, tags, a.out, a.app_version)
    flasher = build_flasher(a.out) if a.site else None
    if a.publish:
        for r in nrf:
            publish(r, r['tag'])
        if boards:
            for r in boards:
                publish(r, r['tag'])
        if app:
            publish(app, f'GhostWave app {app_version}')
    if a.site:
        if not app_version:
            p.error('--site needs an app release to point the downloads at')
        site_pr(a.site, flasher, app_version, fw_version, a.out, a.publish)
    print('done' if a.publish else f'dry run done; staged in {a.out}. Re-run with --publish to release.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as e:
        sys.exit(f'release stopped: {e}')
