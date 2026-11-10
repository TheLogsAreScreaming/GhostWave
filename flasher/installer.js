// Keep transport routing explicit: an ESP32 image must never reach Nordic DFU.
export function installerFor(board, release) {
  if (!board || !release || board.catalogOnly) return null;
  if (!/^[a-z0-9_]+$/.test(board.id) || !/^[0-9][A-Za-z0-9._+-]*$/.test(release.version)) throw new Error('Invalid firmware selection');
  const directory = `firmware/${board.id}/${release.version}`;
  switch (board.transport ?? 'nrf-dfu') {
    case 'nrf-dfu': return { transport: 'nrf-dfu', directory, download: `${directory}/firmware.uf2`, extension: 'uf2' };
    case 'esp-web-tools': return { transport: 'esp-web-tools', directory, download: `${directory}/installer.zip`, extension: 'zip' };
    default: throw new Error('Unsupported installer transport');
  }
}
