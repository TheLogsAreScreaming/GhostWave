"""PBM (P1) to PNG, 4x, white pixels drawn in the RAK1921's blue-white on black."""
import struct, sys, zlib

def png(path, rows, w, h, s=4, on=(225, 240, 255), off=(6, 8, 12)):
    raw = b""
    for row in rows:
        line = b"".join(bytes(on if p else off) * s for p in row)
        raw += (b"\x00" + line) * s
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w * s, h * s, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(data)

for p in sys.argv[1:]:
    tok = open(p).read().split()
    w, h = int(tok[1]), int(tok[2])
    bits = "".join(tok[3:])
    rows = [[bits[y * w + x] == "1" for x in range(w)] for y in range(h)]
    png(p[:-4] + ".png", rows, w, h)
