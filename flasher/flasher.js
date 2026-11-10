import { flash, SerialIo } from "./dfu.js";

const $ = (id) => document.getElementById(id);
const GUIDES = "https://github.com/TheLogsAreScreaming/GhostWave/blob/main/docs/hardware/";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let boards = [];
let busy = false;

const board = () => boards.find((b) => b.id === $("board").value);
const version = () => board()?.versions.find((v) => v.version === $("version").value);
const dir = () => `firmware/${board().id}/${version().version}`;
const log = (text) => { $("log").textContent += text + "\n"; };

function result(text, cls = "") {
  $("result").textContent = text;
  $("result").className = cls;
}

function updateButtons() {
  const ready = version() && [...document.querySelectorAll("#confirm input")].every((c) => c.checked);
  $("start").disabled = busy || !ready;
  $("already").disabled = busy || !ready;
}

function renderVersions() {
  const b = board();
  $("boardDetail").textContent = b.catalogOnly ? `${b.name} · experimental build target` : `${b.detail}. Needs the ${b.softdevice} bootloader.`;
  $("version").replaceChildren(...b.versions.map((v) => new Option(`${v.version}${v.prerelease ? " (test build)" : ""}`, v.version)));
  $("version").disabled = !b.versions.length;
  $("noFirmware").textContent = b.catalogOnly ? "Browser installation is unavailable for this model." : "No firmware has been published for this board yet.";
  $("noFirmware").hidden = !!b.versions.length;
  $("confirm").hidden = $("flash").hidden = !b.versions.length;
  $("checks").replaceChildren(...b.checks.map((text, i) => {
    const row = document.createElement("div");
    row.className = "check";
    const input = document.createElement("input");
    input.type = "checkbox";
    input.id = `c${i}`;
    input.addEventListener("change", updateButtons);
    const label = document.createElement("label");
    label.htmlFor = input.id;
    label.textContent = text;
    row.append(input, label);
    return row;
  }));
  $("replace").checked = false;
  $("enterHint").textContent = b.enter || "";
  if (b.guide) $("guide").href = GUIDES + b.guide;
  else $("guide").removeAttribute("href");
  renderVersion();
}

function renderVersion() {
  const v = version();
  let checksum = $("uf2Checksum");
  if (!checksum) {
    checksum = document.createElement("p");
    checksum.id = "uf2Checksum";
    checksum.className = "small";
    checksum.style.overflowWrap = "anywhere";
    $("uf2").parentElement.after(checksum);
  }
  checksum.hidden = !v?.sha256;
  checksum.textContent = v?.sha256 ? `UF2 SHA-256: ${v.sha256}` : "";
  $("preNote").hidden = !v?.prerelease;
  if (v) {
    $("uf2").href = `${dir()}/firmware.uf2`;
    $("uf2").download = `ghostwave-${board().id}-${v.version}.uf2`;
  }
  updateButtons();
}

async function fetchBytes(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`Couldn't download ${url} (${r.status}).`);
  return new Uint8Array(await r.arrayBuffer());
}

function explain(err) {
  if (err?.name === "NotFoundError") return "No port was chosen.";
  if (err?.name === "NetworkError" || err?.name === "InvalidStateError")
    return "Couldn't open the port. Close anything else using it (serial monitors, the Meshtastic site), then try again.";
  return err?.message || String(err);
}

// Opening at 1200 baud and dropping DTR asks a running board to restart in update mode.
async function touchToBootloader(port) {
  await port.open({ baudRate: 1200 });
  await port.setSignals({ dataTerminalReady: false });
  await sleep(100);
  await port.close();
}

async function runFlash() {
  const port = await navigator.serial.requestPort();
  busy = true;
  updateButtons();
  $("secondStep").hidden = true;
  $("progressWrap").hidden = false;
  $("bar").value = 0;
  result("Flashing. Don't unplug the board.");
  let io;
  try {
    const [bin, dat] = await Promise.all([fetchBytes(`${dir()}/firmware.bin`), fetchBytes(`${dir()}/firmware.dat`)]);
    log(`Firmware ${version().version}, ${bin.length} bytes`);
    await port.open({ baudRate: 115200 });
    await port.setSignals({ dataTerminalReady: true, requestToSend: true });
    await sleep(100);
    io = new SerialIo(port);
    await flash(io, { bin, dat, onProgress: (x) => ($("bar").value = x), onLog: log });
    result("Done. The board restarts by itself.", "ok");
    log("Check it on the serial console at 115200: type status, and the radio should say ok.");
  } catch (err) {
    result(`Flashing failed: ${explain(err)}`, "bad");
    log("The old firmware may be gone, but the bootloader is untouched. Put the board in update mode and try again, or use the UF2.");
    log(`The bootloader refuses firmware built for a different one, so check it's ${board().softdevice} if this keeps failing.`);
  } finally {
    if (io) await io.close();
    else await port.close().catch(() => {});
    busy = false;
    updateButtons();
  }
}

async function start() {
  let port;
  try {
    port = await navigator.serial.requestPort();
    result("Asking the board to restart in update mode.");
    await touchToBootloader(port);
    await sleep(1500);
    result("");
    $("secondStep").hidden = false;
  } catch (err) {
    result(explain(err), "bad");
  }
}

const guarded = (fn) => () => fn().catch((err) => { busy = false; updateButtons(); result(explain(err), "bad"); });

async function init() {
  if (!("serial" in navigator)) {
    $("unsupported").hidden = false;
    return;
  }
  try {
    const r = await fetch("manifest.json");
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    boards = (await r.json()).boards;
  } catch (err) {
    $("loadError").hidden = false;
    $("loadErrorText").textContent = `Couldn't load the list of firmware: ${err.message}`;
    return;
  }
  $("board").replaceChildren(...boards.map((b) => new Option(b.name, b.id)));
  $("pick").hidden = false;
  $("board").addEventListener("change", renderVersions);
  $("version").addEventListener("change", renderVersion);
  $("replace").addEventListener("change", updateButtons);
  $("start").addEventListener("click", guarded(start));
  $("already").addEventListener("click", guarded(runFlash));
  $("connect").addEventListener("click", guarded(runFlash));
  window.addEventListener("beforeunload", (e) => { if (busy) e.preventDefault(); });
  renderVersions();
}

init();
