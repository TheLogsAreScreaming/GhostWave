import { installerFor } from './installer.js';
const $ = id => document.getElementById(id);
async function init() {
  const response = await fetch('manifest.json', { cache: 'no-cache' });
  if (!response.ok) throw new Error(`Firmware list unavailable (${response.status})`);
  const params = new URLSearchParams(location.search);
  const board = (await response.json()).boards.find(b => b.id === params.get('board'));
  const release = board?.versions.find(v => v.version === params.get('version'));
  const selected = installerFor(board, release);
  if (selected?.transport !== 'esp-web-tools') throw new Error('No published ESP32 installer matches this selection. Return to board selection.');
  $('boardName').textContent = board.name;
  $('version').textContent = `${release.version} · ESP32-S3 · ${board.flashSize / 1048576} MB flash`;
  $('installer').setAttribute('manifest', `${selected.directory}/install.json`);
  $('download').href = selected.download;
  $('details').hidden = false;
  // Pin the maintained installer. It owns port selection, progress, chip-family
  // matching, cancellation and recovery; Nordic DFU is never loaded here.
  await import('https://unpkg.com/esp-web-tools@10.1.0/dist/web/install-button.js?module');
  $('status').textContent = 'Confirm your board, then choose its USB port. Progress and errors appear in the installer dialog.';
  $('confirm').addEventListener('change', () => { $('activate').disabled = !$('confirm').checked; });
}
init().catch(error => { $('status').textContent = `Installer unavailable: ${error.message}`; });
