#!/usr/bin/env python3
"""Builds the static web flasher: page files plus firmware from GhostWave-Releases.

The page needs the firmware on its own origin (GitHub's download URLs send no
CORS headers), so each release UF2 becomes firmware.bin + firmware.dat here.

  build_site.py --out dist/webflasher
  build_site.py --convert file.uf2 --sd-fwid 182 --app-start 155648 --out dir
"""
import hashlib
import argparse
import json
import pathlib
import re
import shutil
import struct
import subprocess
import tempfile

from bundles import unpack_bundle, verify_esp

HERE = pathlib.Path(__file__).resolve().parent
REPO = "TheLogsAreScreaming/GhostWave-Releases"
UF2_MAGIC = (0x0A324655, 0x9E5D5157, 0x0AB16F30)
NRF52840_FAMILY = 0xADA52840


def crc16(data, crc=0xFFFF):
    for b in data:
        crc = ((crc >> 8) & 0xFF) | ((crc << 8) & 0xFF00)
        crc ^= b
        crc ^= (crc & 0xFF) >> 4
        crc ^= (crc << 8) << 4
        crc ^= ((crc & 0xFF) << 4) << 1
        crc &= 0xFFFF
    return crc


def uf2_to_bin(raw, app_start):
    if not raw or len(raw) % 512:
        raise ValueError("not a UF2 file")
    blocks = {}
    numbers = set()
    total_blocks = len(raw) // 512
    for i in range(0, len(raw), 512):
        block = raw[i : i + 512]
        m0, m1, flags, addr, size, _no, _total, family = struct.unpack("<8I", block[:32])
        end = struct.unpack("<I", block[508:512])[0]
        if (m0, m1, end) != UF2_MAGIC:
            raise ValueError("bad UF2 block")
        if flags & (0x00000001 | 0x00001000):
            raise ValueError("UF2 contains a non-application block")
        if not flags & 0x2000 or family != NRF52840_FAMILY:
            raise ValueError("UF2 is not for the nRF52840")
        if size == 0 or size > 476:
            raise ValueError("invalid UF2 payload size")
        if _total != total_blocks or _no >= _total or _no in numbers:
            raise ValueError("inconsistent or duplicate UF2 block numbering")
        if addr in blocks:
            raise ValueError("duplicate UF2 target address")
        if addr + size > 0x100000:
            raise ValueError("UF2 payload outside application flash")
        numbers.add(_no)
        blocks[addr] = block[32 : 32 + size]
    if min(blocks) != app_start:
        raise ValueError(f"UF2 starts at {min(blocks):#x}, this board needs {app_start:#x}")
    out = bytearray()
    for addr in sorted(blocks):
        if app_start + len(out) != addr:
            raise ValueError(f"gap in UF2 at {addr:#x}")
        out += blocks[addr]
    return bytes(out)


def init_packet(image, sd_fwid):
    # adafruit-nrfutil: device type 0x52, revision and app version "any", one required SoftDevice
    return struct.pack("<HHIHHH", 0x52, 0xFFFF, 0xFFFFFFFF, 1, sd_fwid, crc16(image))


def convert(uf2, sd_fwid, app_start, out):
    image = uf2_to_bin(pathlib.Path(uf2).read_bytes(), app_start)
    out = pathlib.Path(out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "firmware.bin").write_bytes(image)
    (out / "firmware.dat").write_bytes(init_packet(image, sd_fwid))
    return len(image)


def version_key(v):
    core, separator, suffix = v.split("+", 1)[0].partition("-")
    numbers = tuple(int(part) for part in re.findall(r"\d+", core))
    prerelease = tuple((0, int(part)) if part.isdigit() else (1, part) for part in suffix.split("."))
    return numbers, not bool(separator), prerelease


def releases():
    text = subprocess.check_output(
        ["gh", "release", "list", "-R", REPO, "--limit", "200", "--exclude-drafts", "--json", "tagName,isPrerelease"], text=True
    )
    return json.loads(text)


def build(out):
    out = pathlib.Path(out)
    if out.is_symlink() or (out.exists() and not out.is_dir()):
        raise ValueError("Expected an output directory")
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=out.parent) as staging:
        staged = pathlib.Path(staging) / "new"
        staged.mkdir()
        boards = build_into(staged)
        previous = pathlib.Path(staging) / "previous"
        if out.exists():
            out.rename(previous)
        try:
            staged.rename(out)
        except OSError:
            if previous.exists():
                previous.rename(out)
            raise
        return boards


def build_into(out):
    for name in ("index.html", "flasher.js", "dfu.js", "installer.js", "esp.html", "esp.js"):
        shutil.copy(HERE / name, out / name)
    boards = json.loads((HERE / "boards.json").read_text())["boards"]
    rels = releases()
    for b in boards:
        found = []
        for r in rels:
            m = re.fullmatch(rf"fw-{re.escape(b['id'])}-v(.+)", r["tagName"])
            if m:
                if not re.fullmatch(r"[0-9][A-Za-z0-9._+-]*", m.group(1)):
                    raise ValueError(f"Invalid firmware version in tag: {r['tagName']}")
                found.append((m.group(1), r["tagName"], r["isPrerelease"]))
        found.sort(key=lambda f: version_key(f[0]), reverse=True)
        b["versions"] = []
        for version, tag, pre in found[:5]:
            if b.get('transport') == 'esp-web-tools':
                with tempfile.TemporaryDirectory() as tmp:
                    subprocess.check_call(['gh', 'release', 'download', tag, '-R', REPO, '-p', '*-installer.zip', '-D', tmp])
                    archives = list(pathlib.Path(tmp).glob('*.zip'))
                    if len(archives) != 1:
                        raise ValueError(f'{tag}: expected exactly one installer ZIP')
                    dest = out / 'firmware' / b['id'] / version
                    dest.mkdir(parents=True)
                    unpack_bundle(archives[0], dest)
                    provenance = verify_esp(dest, b['id'], b['flashSize'])
                    shutil.copy(archives[0], dest / 'installer.zip')
                    digest = hashlib.sha256(archives[0].read_bytes()).hexdigest()
                    b['versions'].append({'version': version, 'prerelease': pre, 'sha256': digest, 'sourceCommit': provenance['commit']})
                continue
            with tempfile.TemporaryDirectory() as tmp:
                subprocess.check_call(
                    ["gh", "release", "download", tag, "-R", REPO, "-p", "*.uf2", "-D", tmp]
                )
                uf2s = list(pathlib.Path(tmp).glob("*.uf2"))
                if len(uf2s) != 1:
                    raise ValueError(f"{tag}: expected one UF2, found {len(uf2s)}")
                digest = hashlib.sha256(uf2s[0].read_bytes()).hexdigest()
                convert(uf2s[0], b["sdFwid"], b["appStart"], out / "firmware" / b["id"] / version)
                shutil.copy(uf2s[0], out / "firmware" / b["id"] / version / "firmware.uf2")
            b["versions"].append({"version": version, "prerelease": pre, "sha256": digest})
    catalog = json.loads((HERE / "board-catalog.json").read_text())["boards"]
    enabled = {board["id"]: board for board in boards}
    for item in catalog:
        if item["id"] in enabled:
            enabled[item["id"]]["name"] = item["name"]
        else:
            boards.append({**item, "versions": [], "checks": [], "catalogOnly": True})
    (out / "manifest.json").write_text(json.dumps({"boards": boards}, indent=1))
    return boards


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--convert")
    ap.add_argument("--sd-fwid", type=int)
    ap.add_argument("--app-start", type=int)
    a = ap.parse_args()
    if a.convert:
        print(convert(a.convert, a.sd_fwid, a.app_start, a.out), "bytes")
    else:
        for b in build(a.out):
            print(b["id"], [v["version"] for v in b["versions"]])


if __name__ == "__main__":
    main()
