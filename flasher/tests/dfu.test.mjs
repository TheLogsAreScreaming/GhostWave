import assert from "node:assert/strict";
import { test } from "node:test";
import { crc16, eraseWaitMs, flash, header, hciFrame, slipDecode, slipEncode } from "../dfu.js";

// A bootloader that checks framing, CRC, sequence and packet order.
class FakeBootloader {
  constructor({ silentAfter = Infinity } = {}) {
    Object.assign(this, { silentAfter, frames: 0, stage: "start", image: [], dat: null, appSize: 0, seq: 0, pending: null });
  }
  async write(frame) {
    assert.equal(frame[0], 0xc0);
    assert.equal(frame.at(-1), 0xc0);
    assert.ok(!frame.slice(1, -1).includes(0xc0), "unescaped C0 inside a frame");
    const d = slipDecode([...frame.slice(1, -1)]);
    assert.equal((d[0] + d[1] + d[2] + d[3]) & 0xff, 0, "header checksum");
    const seq = d[0] & 7;
    assert.equal(seq, (this.seq + 1) % 8, "sequence number");
    this.seq = seq;
    const len = (d[1] >> 4) | (d[2] << 4);
    assert.equal(d.length, 4 + len + 2, "length field");
    assert.equal(crc16(d.slice(0, -2)), d.at(-2) | (d.at(-1) << 8), "frame CRC");
    const p = d.slice(4, -2);
    const type = p[0] | (p[1] << 8);
    const rest = p.slice(4);
    if (type === 3) {
      assert.equal(this.stage, "start");
      assert.equal(rest[0], 4, "application mode");
      this.appSize = rest[12] | (rest[13] << 8) | (rest[14] << 16);
      this.stage = "init";
    } else if (type === 1) {
      assert.equal(this.stage, "init");
      assert.deepEqual(rest.slice(-2), [0, 0], "init padding");
      this.dat = rest.slice(0, -2);
      this.stage = "data";
    } else if (type === 4) {
      assert.equal(this.stage, "data");
      assert.ok(rest.length <= 512);
      this.image.push(...rest);
    } else if (type === 5) {
      assert.equal(this.stage, "data");
      this.stage = "done";
    } else assert.fail(`unknown packet ${type}`);
    this.pending = (seq + 1) % 8;
    this.frames++;
  }
  async readAck() {
    if (this.frames > this.silentAfter) return null;
    const ack = this.pending << 3;
    return Uint8Array.from([0xc0, ...slipEncode([ack, 0, 0, (~ack + 1) & 0xff]), 0xc0]);
  }
}

const sleep = async () => {};
const image = (n) => Uint8Array.from({ length: n }, (_, i) => (i * 7) & 0xff);   // has C0 and DB bytes
const dat = Uint8Array.from([0x52, 0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 1, 0, 0xb6, 0, 0xaa, 0xed]);

test("crc16 matches the CRC-16/CCITT-FALSE check value", () => {
  assert.equal(crc16(Uint8Array.from([0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39])), 0x29b1);
});

test("SLIP round trip", () => {
  const b = [0xc0, 1, 0xdb, 0xdc, 0xdd];
  assert.deepEqual(slipDecode(slipEncode(b)), b);
  assert.throws(() => slipDecode([0xdb, 1]));
});

test("header carries a checksum and long lengths", () => {
  const h = header(3, 524);
  assert.equal((h[0] + h[1] + h[2] + h[3]) & 0xff, 0);
  assert.equal((h[1] >> 4) | (h[2] << 4), 524);
});

for (const size of [1, 512, 513, 4096, 409888 % 70000]) {
  test(`delivers a ${size} byte image intact and in order`, async () => {
    const b = new FakeBootloader();
    const bin = image(size);
    let last = 0;
    await flash(b, { bin, dat, sleep, onProgress: (x) => (last = x) });
    assert.equal(b.stage, "done");
    assert.equal(b.appSize, size);
    assert.deepEqual(b.dat, [...dat]);
    assert.deepEqual(b.image, [...bin]);
    assert.equal(last, 1);
  });
}

test("waits for the erase before sending more", async () => {
  const waits = [];
  await flash(new FakeBootloader(), { bin: image(40960), dat, sleep: async (ms) => waits.push(ms) });
  assert.equal(waits[0], eraseWaitMs(40960));
  assert.ok(eraseWaitMs(1) >= 500);
});

test("stops with a clear error when the bootloader goes quiet", async () => {
  const b = new FakeBootloader({ silentAfter: 3 });
  await assert.rejects(flash(b, { bin: image(4096), dat, sleep }), /did not answer \(block 2 of 8\)/);
});

test("frames use sequence numbers that wrap at 8", () => {
  assert.equal(hciFrame(7, [1])[1] & 7, 7);
});
