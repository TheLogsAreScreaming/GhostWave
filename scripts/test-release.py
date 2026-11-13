#!/usr/bin/env python3
"""Offline tests for scripts/release.py: version detection, UF2 checks, the next
app version, change lists, site link rewrites and the notes. No network."""
import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release', ROOT / 'scripts/release.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)

failures = 0


def check(cond, what):
    global failures
    print(('ok   ' if cond else 'FAIL ') + what)
    failures += 0 if cond else 1


def raises(fn, what):
    try:
        fn()
    except ValueError:
        check(True, what)
    else:
        check(False, what)


def uf2(payload: bytes) -> bytes:
    out = bytearray()
    chunks = [payload[i:i + 256] for i in range(0, len(payload), 256)] or [b'']
    for n, c in enumerate(chunks):
        block = bytearray(512)
        block[0:4] = b'UF2\n'
        block[4:8] = (0x9E5D5157).to_bytes(4, 'little')
        block[12:16] = (0x26000 + n * 256).to_bytes(4, 'little')
        block[16:20] = len(c).to_bytes(4, 'little')
        block[20:24] = n.to_bytes(4, 'little')
        block[24:28] = len(chunks).to_bytes(4, 'little')
        block[32:32 + len(c)] = c
        block[508:512] = bytes.fromhex('306fb10a')
        out += block
    return bytes(out)


# firmware version
main_cpp = 'x\n#define GW_FW_VERSION "0.1.0-dev.9"\ny'
check(r.firmware_version(main_cpp) == '0.1.0-dev.9', 'reads GW_FW_VERSION')
raises(lambda: r.firmware_version('no version'), 'no GW_FW_VERSION is an error')

# UF2 payload: a version string split across two blocks is still found
body = b'A' * 250 + b'ghostwave 0.1.0-dev.9 build' + b'B' * 300
check(b'0.1.0-dev.9' in r.uf2_payload(uf2(body)), 'version found across a UF2 block boundary')
check(b'0.1.0-dev.8' not in r.uf2_payload(uf2(body)), 'an older version is not mistaken for it')
raises(lambda: r.uf2_payload(b'x' * 100), 'a truncated UF2 is refused')
bad = bytearray(uf2(body))
bad[0] = 0
raises(lambda: r.uf2_payload(bytes(bad)), 'a UF2 with a bad block magic is refused')

# next app version
check(r.next_app_version({'app-v0.1.0-dev.9', 'app-v0.1.0-dev.24', 'fw-rak4631-v0.1.0-dev.9'}) == '0.1.0-dev.25',
      'next app version is numeric, not alphabetical (24 > 9)')
check(r.next_app_version(set()) == '0.1.0-dev.1', 'first app version')

# source commit from release notes
sha = 'f05676cdb220cee7fa6da3f70a5fe3e7797f6e96'
check(r.source_commit(f'blah\n\nSource commit: {sha}. [App CI run]') == sha, 'finds the source commit')
check(r.source_commit('nothing here') is None, 'no source commit')

# change list from squash and merge commits
rec = lambda s, b='': f'{s}\x1f{b}\x1e\n'
log = (rec('Signal strength in the app (#262)') + rec('Merge pull request #267 from x/chat', 'App: chat polish\n\nmore')
       + rec('fix typo', 'body') + rec('Merge pull request #9 from x/y') + rec('App: node cards (#266)'))
check(r.pr_lines(log) == ['- Signal strength in the app (#262)', '- App: chat polish (#267)', '- #9',
                          '- App: node cards (#266)'],
      'PR lines from squash and merge commits (title from the body); plain commits skipped')

# site rewrite: any older dev number, links and labels
html = ('<p>Version 0.1.0-dev.23 · 64-bit ARM</p><a href="https://x/releases/download/app-v0.1.0-dev.23/'
        'ghostwave-app-0.1.0-dev.23-arm64.apk">'
        '<p>The dev.19 redesign</p>')
new = r.rewrite_downloads(html, '0.1.0-dev.25')
check('app-v0.1.0-dev.25/ghostwave-app-0.1.0-dev.25-arm64.apk' in new and 'Version 0.1.0-dev.25' in new,
      'downloads and labels move to the new version')
check('dev.23' not in new and 'The dev.19 redesign' in new, 'prose about older versions is left alone')

# notes
n = r.nrf_notes('t1000e', '0.1.0-dev.9', sha, 'https://ci', 'S140 7.3.0', 'ab' * 32)
check('S140 7.3.0' in n and 'ghostwave-t1000e-0.1.0-dev.9.uf2' in n and 'ab' * 32 in n, 'nRF notes name bootloader, file, hash')
a = r.app_notes('0.1.0-dev.25', 171, sha, 'https://ci', 'cd' * 32, ['- Trip (#268)'])
check('1.0.0 (2171)' in a and '- Trip (#268)' in a and f'Source commit: {sha}' in a, 'app notes: build shown, changes, source commit')
check(r.source_commit(a) == sha, 'app notes round-trip their source commit for the next release')
check('Maintenance build' in r.app_notes('v', 1, sha, 'u', 's', []), 'no changes still reads sensibly')

print(f'{failures} failed' if failures else 'all passed')
sys.exit(1 if failures else 0)
