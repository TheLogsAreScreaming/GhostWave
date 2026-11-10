#!/usr/bin/env python3
"""UF2 conversion and init packet checks for build_site.py."""
import pathlib
import struct
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
import build_site as b

START = 0x26000


def uf2(blocks, family=b.NRF52840_FAMILY):
    out = bytearray()
    for i, (addr, data) in enumerate(blocks):
        head = struct.pack("<8I", b.UF2_MAGIC[0], b.UF2_MAGIC[1], 0x2000, addr, len(data), i, len(blocks), family)
        out += head + data.ljust(476, b"\0") + struct.pack("<I", b.UF2_MAGIC[2])
    return bytes(out)


class T(unittest.TestCase):
    def test_crc(self):
        self.assertEqual(b.crc16(b"123456789"), 0x29B1)

    def test_joins_blocks_in_address_order(self):
        raw = uf2([(START + 256, b"B" * 100), (START, b"A" * 256)])
        self.assertEqual(b.uf2_to_bin(raw, START), b"A" * 256 + b"B" * 100)

    def test_wrong_start_is_refused(self):
        with self.assertRaisesRegex(ValueError, "needs 0x27000"):
            b.uf2_to_bin(uf2([(START, b"A")]), 0x27000)

    def test_gap_is_refused(self):
        with self.assertRaisesRegex(ValueError, "gap"):
            b.uf2_to_bin(uf2([(START, b"A" * 256), (START + 512, b"B")]), START)

    def test_wrong_family_is_refused(self):
        with self.assertRaisesRegex(ValueError, "nRF52840"):
            b.uf2_to_bin(uf2([(START, b"A")], family=1), START)

    def test_truncated_file_is_refused(self):
        with self.assertRaises(ValueError):
            b.uf2_to_bin(b"x" * 100, START)

    def test_duplicate_address_is_refused(self):
        with self.assertRaisesRegex(ValueError, "duplicate UF2 target"):
            b.uf2_to_bin(uf2([(START, b"A" * 4), (START, b"B" * 4)]), START)

    def test_oversized_payload_is_refused(self):
        raw = bytearray(uf2([(START, b"A" * 4)]))
        struct.pack_into("<I", raw, 16, 480)
        with self.assertRaisesRegex(ValueError, "payload size"):
            b.uf2_to_bin(raw, START)

    def test_inconsistent_block_count_is_refused(self):
        raw = bytearray(uf2([(START, b"A" * 4)]))
        struct.pack_into("<I", raw, 24, 2)
        with self.assertRaisesRegex(ValueError, "block numbering"):
            b.uf2_to_bin(raw, START)

    def test_flash_overrun_is_refused(self):
        with self.assertRaisesRegex(ValueError, "outside application flash"):
            b.uf2_to_bin(uf2([(0xFFFFC, b"A" * 8)]), 0xFFFFC)

    def test_init_packet_matches_nrfutil(self):
        # a firmware.dat written by adafruit-nrfutil, for an image with CRC 0xEDAA
        expected = bytes.fromhex("5200ffffffffffff0100b600aaed")
        import unittest.mock as m
        with m.patch.object(b, "crc16", return_value=0xEDAA):
            self.assertEqual(b.init_packet(b"x", 0xB6), expected)


if __name__ == "__main__":
    unittest.main()
