// Nordic legacy serial DFU, as spoken by the Adafruit nRF52 bootloader.
// Follows adafruit-nrfutil's dfu_transport_serial.py and dfu.py. No DOM here,
// so flasher/tests drives it against a simulated bootloader.

const DIP = 1, RELIABLE = 1, HCI_TYPE = 14;
const PKT_INIT = 1, PKT_START = 3, PKT_DATA = 4, PKT_STOP = 5;
const MODE_APP = 4;
const CHUNK = 512;
const PAGE = 4096;
const PAGE_ERASE_MS = 89.7;
const PAGE_WRITE_MS = (PAGE / 4) * 0.1;
const ACK_TIMEOUT_MS = 1000;

export function crc16(bytes, crc = 0xffff) {
  for (const b of bytes) {
    crc = ((crc >> 8) & 0xff) | ((crc << 8) & 0xff00);
    crc ^= b;
    crc ^= (crc & 0xff) >> 4;
    crc ^= (crc << 8) << 4;
    crc ^= ((crc & 0xff) << 4) << 1;
    crc &= 0xffff;
  }
  return crc;
}

export function header(seq, len) {
  const h = [
    seq | (((seq + 1) % 8) << 3) | (DIP << 6) | (RELIABLE << 7),
    HCI_TYPE | ((len & 0xf) << 4),
    (len & 0xff0) >> 4,
  ];
  h.push((~(h[0] + h[1] + h[2]) + 1) & 0xff);
  return h;
}

export function slipEncode(bytes) {
  const out = [];
  for (const b of bytes) {
    if (b === 0xc0) out.push(0xdb, 0xdc);
    else if (b === 0xdb) out.push(0xdb, 0xdd);
    else out.push(b);
  }
  return out;
}

export function slipDecode(bytes) {
  const out = [];
  for (let i = 0; i < bytes.length; i++) {
    if (bytes[i] !== 0xdb) {
      out.push(bytes[i]);
      continue;
    }
    const next = bytes[++i];
    if (next === 0xdc) out.push(0xc0);
    else if (next === 0xdd) out.push(0xdb);
    else throw new Error("bad SLIP escape");
  }
  return out;
}

export function hciFrame(seq, payload) {
  const body = [...header(seq, payload.length), ...payload];
  const crc = crc16(body);
  body.push(crc & 0xff, crc >> 8);
  return Uint8Array.from([0xc0, ...slipEncode(body), 0xc0]);
}

function u32(v) {
  return [v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff];
}

// Time the bootloader spends erasing, during which it cannot listen.
export function eraseWaitMs(appSize) {
  return Math.max(500, (Math.floor(appSize / PAGE) + 1) * PAGE_ERASE_MS);
}

const realSleep = (ms) => new Promise((r) => setTimeout(r, ms));

// io: { write(Uint8Array), readAck(timeoutMs) -> Uint8Array of one C0..C0 frame or null }
export async function flash(io, { bin, dat, onProgress = () => {}, onLog = () => {}, sleep = realSleep }) {
  let seq = 0;
  let mismatches = 0;
  const send = async (payload, what) => {
    seq = (seq + 1) % 8;
    await io.write(hciFrame(seq, payload));
    const ack = await io.readAck(ACK_TIMEOUT_MS);
    if (!ack) throw new Error(`The bootloader did not answer (${what}).`);
    const decoded = slipDecode([...ack].filter((_, i, a) => i !== 0 && i !== a.length - 1));
    if (((decoded[0] >> 3) & 7) !== (seq + 1) % 8) mismatches++;
  };

  await send([...u32(PKT_START), ...u32(MODE_APP), ...u32(0), ...u32(0), ...u32(bin.length)], "start");
  onLog("Erasing the old firmware");
  await sleep(eraseWaitMs(bin.length));

  await send([...u32(PKT_INIT), ...dat, 0, 0], "firmware check data");

  const total = Math.ceil(bin.length / CHUNK);
  for (let n = 0; n < total; n++) {
    await send([...u32(PKT_DATA), ...bin.subarray(n * CHUNK, (n + 1) * CHUNK)], `block ${n + 1} of ${total}`);
    onProgress((n + 1) / total);
    if (n % 8 === 0) await sleep(PAGE_WRITE_MS);   // the CPU stops while flash is written
  }
  await sleep(PAGE_WRITE_MS);
  await send(u32(PKT_STOP), "finish");
  if (mismatches) onLog(`${mismatches} acknowledgement numbers looked out of order; the bootloader's own CRC check covers this.`);
  await sleep(PAGE_ERASE_MS + PAGE_WRITE_MS);   // saving bootloader settings; do not disturb the port
}

// Adapts an open Web Serial port to the io interface above.
export class SerialIo {
  constructor(port) {
    this.port = port;
    this.buf = [];
    this.inputClosed = false;
    this.waiter = null;
    this.reader = port.readable.getReader();
    this.writer = port.writable.getWriter();
    this.pump = this.#run();
  }

  async #run() {
    try {
      for (;;) {
        const { value, done } = await this.reader.read();
        if (done) break;
        this.buf.push(...value);
        this.waiter?.();
      }
    } catch {
      // the port went away: the board rebooted or the cable came out
    }
    this.inputClosed = true;
    this.waiter?.();
  }

  write(bytes) {
    return this.writer.write(bytes);
  }

  #takeFrame() {
    const start = this.buf.indexOf(0xc0);
    if (start < 0) return null;
    const end = this.buf.indexOf(0xc0, start + 1);
    if (end < 0) return null;
    const frame = this.buf.slice(start, end + 1);
    this.buf.splice(0, end + 1);
    return Uint8Array.from(frame);
  }

  async readAck(timeoutMs) {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const f = this.#takeFrame();
      if (f) return f;
      if (this.inputClosed) throw new Error('The bootloader serial connection closed.');
      const left = deadline - Date.now();
      if (left <= 0) return null;
      await new Promise((resolve) => {
        const t = setTimeout(resolve, left);
        this.waiter = () => {
          clearTimeout(t);
          resolve();
        };
      });
      this.waiter = null;
    }
  }

  async close() {
    try { await this.reader.cancel(); } catch {}
    await this.pump;
    this.reader.releaseLock();
    try { await this.writer.close(); } catch {}
    this.writer.releaseLock();
    try { await this.port.close(); } catch {}
  }
}
